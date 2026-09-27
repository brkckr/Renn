import CoreImage
import CoreMedia
import SwiftUI
import UIKit
import RENNDomain
import RENNFeatures

/// Ordinary camera (02 D06): large portrait viewfinder with the Look applied live, real REC
/// status/timer, pre-record front/rear switch, record/stop. Look/intensity are locked while
/// recording; timer and Look/Beat/Indicators panels arrive with M05.
struct CameraView: View {
    @State private var viewModel: CaptureFlowViewModel
    @State private var source: CameraFrameSource
    let engine: RenderEngine

    @Environment(\.openURL) private var openURL

    /// The view model and frame box come from the same capture controller.
    struct Parts {
        let viewModel: CaptureFlowViewModel
        let frames: CaptureFrameBox
    }

    init(parts: @autoclosure () -> Parts, engine: RenderEngine) {
        let made = parts()
        _viewModel = State(initialValue: made.viewModel)
        _source = State(initialValue: CameraFrameSource(box: made.frames))
        self.engine = engine
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MetalPreviewView(
                engine: engine, source: source, recipe: viewModel.previewRecipe,
                sourceDimensions: try? PixelDimensions(width: 1080, height: 1920),
                showsWatermark: false, bypassCreative: false)
                .ignoresSafeArea()
                .accessibilityLabel(Text("camera.viewfinder"))
            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(RENNMetrics.sideMargin)
            if case .failed(let failure) = viewModel.state {
                failureOverlay(failure)
            }
        }
        .task { await viewModel.start() }
        .task { await viewModel.observeEvents() }
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

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    Task { await viewModel.switchCamera() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(RENNColor.textPrimary)
                        .frame(width: 52, height: 52)
                        .glassBackground(Circle())
                }
                .disabled(viewModel.state != .ready)
                .opacity(viewModel.isRecording ? 0 : 1)
                .accessibilityLabel(Text("camera.switch"))

                Spacer()
                recordButton
                Spacer()
                Color.clear.frame(width: 52, height: 52)
            }
        }
        .padding(.bottom, 8)
    }

    private var recordButton: some View {
        Button {
            Task {
                if viewModel.isRecording {
                    await viewModel.stop()
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
        .disabled(!(viewModel.state == .ready || viewModel.isRecording))
        .accessibilityLabel(Text(viewModel.isRecording ? LocalizedStringKey("camera.stop") : LocalizedStringKey("camera.record")))
    }

    private func failureOverlay(_ failure: CaptureFlowViewModel.Failure) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(message(for: failure))
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

    private func message(for failure: CaptureFlowViewModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .cameraDenied: "camera.failed.denied"
        case .cameraUnavailable: "camera.failed.unavailable"
        case .recordingFailed: "camera.failed.recording"
        case .insufficientStorage: "camera.failed.storage"
        case .couldNotSave: "camera.failed.save"
        }
    }
}

/// Live camera frames for the Metal preview. Buffers already arrive portrait and mirrored.
@MainActor
final class CameraFrameSource: PreviewFrameSource {
    private let box: CaptureFrameBox
    private var lastTime: CMTime?
    private var firstTime: CMTime?

    init(box: CaptureFrameBox) {
        self.box = box
    }

    var frameOrientation: CGImagePropertyOrientation { .up }

    func nextFrame() -> (image: CIImage, time: RationalTime)? {
        guard let (image, time) = box.latest(), time != lastTime else { return nil }
        lastTime = time
        let first = firstTime ?? time
        firstTime = first
        let relative = CMTimeSubtract(time, first)
        return (image, (try? RationalTime(value: relative.value, timescale: relative.timescale)) ?? .zero)
    }
}
