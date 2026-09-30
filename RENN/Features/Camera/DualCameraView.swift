import CoreImage
import CoreMedia
import SwiftUI
import UIKit
import RENNDomain
import RENNFeatures

/// Dual-Cam (01 P05, 02 D06): composed live preview (main + rounded inset through the export
/// graph), inset corner chosen before recording, one-tap swap during recording, real REC timer.
/// No PiP dragging/resizing and no post-capture layout editor.
struct DualCameraView: View {
    @State private var viewModel: DualCaptureFlowViewModel
    @State private var source: DualCameraFrameSource
    let engine: RenderEngine
    /// The Indicators panel shows its own viewfinder; this one pauses meanwhile.
    @State private var viewfinderCovered = false

    @Environment(\.openURL) private var openURL

    struct Parts {
        let viewModel: DualCaptureFlowViewModel
        let rearFrames: CaptureFrameBox
        let frontFrames: CaptureFrameBox
    }

    init(parts: @autoclosure () -> Parts, engine: RenderEngine) {
        let made = parts()
        _viewModel = State(initialValue: made.viewModel)
        _source = State(initialValue: DualCameraFrameSource(rear: made.rearFrames, front: made.frontFrames))
        self.engine = engine
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MetalPreviewView(
                engine: engine, source: source, recipe: viewModel.previewRecipe,
                sourceDimensions: try? PixelDimensions(width: 1080, height: 1920),
                showsWatermark: false, bypassCreative: false, isPaused: viewfinderCovered)
                .ignoresSafeArea()
                .accessibilityLabel(Text("camera.viewfinder"))
            VStack {
                topBar
                Spacer()
                if viewModel.state == .ready {
                    // Dual-Cam's lower quality ceiling is disclosed before recording (05 V02).
                    Text("dual.quality.disclosure")
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassBackground(Capsule())
                        .padding(.bottom, 8)
                    CaptureRecipeControls(
                    draft: viewModel.draft, isSilent: viewModel.isSilent, engine: engine, source: source,
                    coversViewfinder: $viewfinderCovered)
                        .padding(.bottom, 12)
                    cornerPicker
                }
                bottomBar
            }
            .padding(RENNMetrics.sideMargin)
            if case .countdown(let remaining) = viewModel.state {
                Text(verbatim: "\(remaining)")
                    .font(RENNFont.roboto(96, medium: true, relativeTo: .largeTitle))
                    .foregroundStyle(RENNColor.textPrimary)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .accessibilityLabel(Text("camera.countdown \(remaining)"))
            }
            if case .failed(let failure) = viewModel.state {
                failureOverlay(failure)
            }
        }
        .task { await viewModel.start() }
        .task { await viewModel.observeEvents() }
        .onChange(of: viewModel.mainCamera, initial: true) { _, main in source.mainCamera = main }
        .onChange(of: viewModel.layout.insetCorner, initial: true) { _, corner in source.insetCorner = corner }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            CloseButton { Task { await viewModel.close() } }
            Spacer()
            if case .recording(let duration) = viewModel.state {
                HStack(spacing: 6) {
                    Circle().fill(RENNColor.brandRed).frame(width: 10, height: 10)
                    Text(verbatim: ProjectPreviewView.timestamp(duration.approximateSeconds))
                        .monospacedDigit()
                    if let limit = viewModel.recordingLimit {
                        Text(verbatim: "/ \(ProjectPreviewView.timestamp(limit.approximateSeconds))")
                            .foregroundStyle(RENNColor.textSecondary)
                    }
                }
                .font(RENNFont.bodyMedium)
                .foregroundStyle(RENNColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .glassBackground(Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("camera.recording"))
            } else if viewModel.isSilent {
                Label("camera.silent", systemImage: "mic.slash")
                    .font(RENNFont.secondary)
                    .foregroundStyle(RENNColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .glassBackground(Capsule())
            }
        }
    }

    /// Pre-record inset corner (fixed for the take).
    private var cornerPicker: some View {
        HStack(spacing: 8) {
            ForEach(DualCameraLayout.Corner.allCases, id: \.self) { corner in
                Button {
                    viewModel.chooseCorner(corner)
                } label: {
                    Image(systemName: Self.symbol(for: corner))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(viewModel.layout.insetCorner == corner ? RENNColor.onPrimary : RENNColor.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(
                            viewModel.layout.insetCorner == corner ? RENNColor.brandYellow : Color.white.opacity(0.12)))
                }
                .accessibilityLabel(Text(Self.label(for: corner)))
                .accessibilityAddTraits(viewModel.layout.insetCorner == corner ? .isSelected : [])
            }
        }
        .padding(8)
        .glassBackground(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("dual.corner"))
        .padding(.bottom, 12)
    }

    private var bottomBar: some View {
        HStack {
            // Swap: during recording only, an immediate media-timed cut (01 P05).
            Button {
                Task { await viewModel.swap() }
            } label: {
                Image(systemName: "rectangle.2.swap")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(RENNColor.textPrimary)
                    .frame(width: 52, height: 52)
                    .glassBackground(Circle())
            }
            .disabled(!viewModel.isRecording)
            .opacity(viewModel.isRecording ? 1 : 0)
            .accessibilityLabel(Text("dual.swap"))

            Spacer()
            recordButton
            Spacer()
            Button {
                viewModel.timer = CameraView.next(viewModel.timer)
            } label: {
                Text(CameraView.timerLabel(viewModel.timer))
                    .font(RENNFont.roboto(13, medium: true, relativeTo: .footnote))
                    .foregroundStyle(viewModel.timer == .off ? RENNColor.textPrimary : RENNColor.onPrimary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(viewModel.timer == .off ? Color.white.opacity(0.12) : RENNColor.brandYellow))
            }
            .disabled(viewModel.state != .ready)
            .opacity(viewModel.isRecording ? 0 : 1)
            .accessibilityLabel(Text("camera.timer"))
            .accessibilityValue(Text(CameraView.timerLabel(viewModel.timer)))
        }
        .padding(.bottom, 8)
    }

    private var recordButton: some View {
        Button {
            Task {
                if viewModel.isRecording {
                    await viewModel.stop()
                } else if viewModel.isCountingDown {
                    viewModel.cancelCountdown()
                } else {
                    await viewModel.record()
                }
            }
        } label: {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 78, height: 78)
                if viewModel.isRecording {
                    RoundedRectangle(cornerRadius: 6).fill(RENNColor.brandRed).frame(width: 30, height: 30)
                } else {
                    Circle().fill(RENNColor.brandRed).frame(width: 62, height: 62)
                }
                if viewModel.state == .finalizing || viewModel.state == .preparing {
                    ProgressView().tint(.white)
                }
            }
        }
        .disabled(!(viewModel.state == .ready || viewModel.isRecording || viewModel.isCountingDown))
        .accessibilityLabel(Text(viewModel.isRecording ? LocalizedStringKey("camera.stop") : LocalizedStringKey("camera.record")))
    }

    private func failureOverlay(_ failure: CaptureFlowViewModel.Failure) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(CameraView.message(for: failure))
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textPrimary)
                .multilineTextAlignment(.center)
            if failure == .cameraDenied {
                Button("camera.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.rennPrimary)
            }
            Button("creation.import.title") { viewModel.importInstead() }
                .buttonStyle(.rennSecondary)
            Spacer()
        }
        .padding(RENNMetrics.sideMargin)
        .background(RENNColor.backgroundBase.opacity(0.94).ignoresSafeArea())
    }

    static func symbol(for corner: DualCameraLayout.Corner) -> String {
        switch corner {
        case .topLeft: "arrow.up.left.square"
        case .topRight: "arrow.up.right.square"
        case .bottomLeft: "arrow.down.left.square"
        case .bottomRight: "arrow.down.right.square"
        }
    }

    static func label(for corner: DualCameraLayout.Corner) -> LocalizedStringKey {
        switch corner {
        case .topLeft: "dual.corner.topLeft"
        case .topRight: "dual.corner.topRight"
        case .bottomLeft: "dual.corner.bottomLeft"
        case .bottomRight: "dual.corner.bottomRight"
        }
    }
}

/// Live Dual-Cam frames: the main camera through `nextFrame`, the other as the inset. Buffers
/// arrive portrait, with the front mirror already applied, exactly as they are recorded.
@MainActor
final class DualCameraFrameSource: DualPreviewFrameSource {
    private let rear: CaptureFrameBox
    private let front: CaptureFrameBox
    private var lastTime: CMTime?
    private var firstTime: CMTime?
    var mainCamera: DualCameraLayout.Camera = .rear
    var insetCorner: DualCameraLayout.Corner = .topRight

    init(rear: CaptureFrameBox, front: CaptureFrameBox) {
        self.rear = rear
        self.front = front
    }

    var frameOrientation: CGImagePropertyOrientation { .up }

    func nextFrame() -> (image: CIImage, time: RationalTime)? {
        guard let (image, time) = (mainCamera == .rear ? rear : front).latest(), time != lastTime else { return nil }
        lastTime = time
        let first = firstTime ?? time
        firstTime = first
        let relative = CMTimeSubtract(time, first)
        return (image, (try? RationalTime(value: relative.value, timescale: relative.timescale)) ?? .zero)
    }

    func insetFrame() -> CIImage? {
        (mainCamera == .rear ? front : rear).latest()?.0
    }
}
