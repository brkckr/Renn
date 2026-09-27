import AVKit
import UIKit
import SwiftUI
import RENNDomain
import RENNFeatures

/// Export summary (01 P09, 02 D09): actual resolved output. No controls that could bypass
/// policy; explicit Pro intent is offered to Free users, never forced.
struct ExportSummarySheet: View {
    let summary: ExportSummary
    let onExport: () -> Void
    let onUpgrade: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("export.summary.title")
                .font(RENNFont.heading)
                .foregroundStyle(RENNColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                row("export.summary.resolution",
                    value: "\(summary.policy.dimensions.width) × \(summary.policy.dimensions.height)")
                row("export.summary.frameRate", value: Self.fps(summary.policy.frameRate))
                row("export.summary.duration", value: ProjectPreviewView.timestamp(summary.duration.approximateSeconds))
                rowKey("export.summary.sound",
                       value: summary.includesAudio ? "export.summary.soundOn" : "export.summary.soundOff")
                rowKey("export.summary.watermark",
                       value: summary.policy.requiresWatermark ? "export.summary.watermarkOn" : "export.summary.watermarkOff")
            }
            .padding(16)
            .glassBackground(cornerRadius: RENNMetrics.cardRadius)
            if summary.isHDRSource {
                Text("export.summary.hdr")
                    .font(RENNFont.secondary)
                    .foregroundStyle(RENNColor.textSecondary)
            }
            if summary.isLongOrHighQuality {
                Text("export.summary.longJob")
                    .font(RENNFont.secondary)
                    .foregroundStyle(RENNColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button("export.summary.cta", action: onExport)
                .buttonStyle(.rennPrimary)
            if summary.policy.tier == .free {
                Button("export.summary.upgrade", action: onUpgrade)
                    .buttonStyle(.rennSecondary)
            }
            Button("common.cancel", action: onCancel)
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: RENNMetrics.minimumTouchTarget)
        }
        .padding(RENNMetrics.sideMargin)
        .presentationDetents([.large])
        .presentationBackground(RENNColor.backgroundBase)
    }

    private func row(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(RENNColor.textSecondary)
            Spacer()
            Text(verbatim: value).foregroundStyle(RENNColor.textPrimary)
        }
        .font(RENNFont.body)
    }

    private func rowKey(_ title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        HStack {
            Text(title).foregroundStyle(RENNColor.textSecondary)
            Spacer()
            Text(value).foregroundStyle(RENNColor.textPrimary)
        }
        .font(RENNFont.body)
    }

    static func fps(_ rate: FrameRate) -> String {
        let value = rate.approximateFPS
        return value.rounded() == value ? "\(Int(value)) FPS" : String(format: "%.2f FPS", value)
    }
}

/// Processing and result (01 P09, 02 D09, 03 M06). Real stages and measured progress, Cancel
/// before commit, keep-open guidance, verified "Saved to Photos" only when true, save-only retry.
struct ExportStatusView: View {
    let viewModel: ProjectPreviewViewModel

    @State private var outputURL: URL?
    @State private var watching = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            RENNColor.backgroundBase.ignoresSafeArea()
            VStack(spacing: 20) {
                switch viewModel.exportState {
                case .idle:
                    EmptyView()
                case .preparing:
                    processing(title: "export.stage.preparing", progress: nil)
                case .rendering(_, let progress):
                    processing(title: "export.stage.rendering", progress: progress)
                case .finalizing:
                    processing(title: "export.stage.finalizing", progress: nil)
                case .savingToPhotos(_, let output):
                    result(output, saving: true)
                case .completed(_, let output), .saveFailed(_, let output):
                    result(output, saving: false)
                case .failed(_, let failure):
                    message(failure == .insufficientStorage ? "export.failed.storage" : "export.failed.generic")
                case .cancelled:
                    message("export.cancelled")
                }
            }
            .padding(RENNMetrics.sideMargin)
        }
        .sheet(isPresented: $watching) {
            if let outputURL {
                VideoPlayer(player: AVPlayer(url: outputURL))
                    .ignoresSafeArea()
            }
        }
    }

    private func processing(title: LocalizedStringKey, progress: Double?) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(title)
                .font(RENNFont.heading)
                .foregroundStyle(RENNColor.textPrimary)
            if let progress {
                ProgressView(value: progress)
                    .tint(RENNColor.brandYellow)
                Text(verbatim: "\(Int((progress * 100).rounded(.down)))%")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                    .monospacedDigit()
            } else {
                ProgressView()
            }
            Text("export.keepOpen")
                .font(RENNFont.secondary)
                .foregroundStyle(RENNColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("common.cancel") { viewModel.cancelExport() }
                .buttonStyle(.rennSecondary)
        }
    }

    private func result(_ output: OutputRecord, saving: Bool) -> some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                CloseButton { viewModel.acknowledgeExport() }
                    .disabled(saving)
            }
            Spacer()
            Button {
                watching = true
            } label: {
                VHSCaseShell(name: viewModel.name, variant: 0)
                    .frame(width: 140)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("export.result.watch"))
            Text("export.result.ready")
                .font(RENNFont.heading)
                .foregroundStyle(RENNColor.textPrimary)
            saveStatus(output, saving: saving)
            Spacer()
            if let outputURL {
                ShareLink(item: outputURL) {
                    Text("export.result.share")
                }
                .buttonStyle(.rennPrimary)
            }
            Button("export.result.watch") { watching = true }
                .buttonStyle(.rennSecondary)
                .disabled(outputURL == nil)
        }
        .task(id: output.id) { outputURL = await viewModel.url(for: output) }
    }

    @ViewBuilder
    private func saveStatus(_ output: OutputRecord, saving: Bool) -> some View {
        if saving {
            Label("export.result.saving", systemImage: "arrow.down.circle")
                .foregroundStyle(RENNColor.textSecondary)
        } else {
            switch output.photosSave {
            case .saved:
                // Shown only after the actual save succeeded (01 P09).
                Label("export.result.saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(RENNColor.brandYellow)
            case .permissionDenied:
                VStack(spacing: 8) {
                    Text("export.result.saveDenied")
                        .foregroundStyle(RENNColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("export.result.openSettings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    Button("export.result.retrySave") { Task { await viewModel.retryPhotosSave() } }
                }
            case .failed, .uncertain, .notAttempted, .inFlight:
                VStack(spacing: 8) {
                    Text("export.result.saveFailed")
                        .foregroundStyle(RENNColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("export.result.retrySave") { Task { await viewModel.retryPhotosSave() } }
                }
            }
        }
    }

    private func message(_ key: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(key)
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("common.close") { viewModel.acknowledgeExport() }
                .buttonStyle(.rennSecondary)
        }
    }
}
