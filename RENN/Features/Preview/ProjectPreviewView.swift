import SwiftUI
import RENNDomain
import RENNFeatures

/// Simplified project preview (02 D05): large aspect-correct result, scrubber, before/after,
/// sound, loop, Look intensity and Export. No Edit button, no trim. Beat and indicator panels
/// arrive with M03/M05.
struct ProjectPreviewView: View {
    @State private var viewModel: ProjectPreviewViewModel
    @State private var player = PreviewPlayer()
    let engine: RenderEngine

    init(viewModel: @autoclosure () -> ProjectPreviewViewModel, engine: RenderEngine) {
        _viewModel = State(initialValue: viewModel())
        self.engine = engine
    }

    var body: some View {
        ZStack {
            RENNColor.backgroundBase.ignoresSafeArea()
            switch viewModel.loadState {
            case .loading:
                ProgressView()
            case .unavailable(let readiness):
                unavailable(readiness)
            case .ready:
                content
            }
        }
        .task {
            await viewModel.load()
            if let url = viewModel.sourceURL {
                await player.load(url: url)
                player.setMuted(viewModel.isMuted)
                player.play()
            }
        }
        .task { await viewModel.observeAccess() }
        .onChange(of: viewModel.isMuted) { _, muted in player.setMuted(muted) }
        .onChange(of: viewModel.isLooping) { _, looping in player.isLooping = looping }
        .onDisappear {
            player.tearDown()
            Task { await viewModel.flush() }
        }
        .sheet(isPresented: summaryBinding) {
            if case .summary(let summary) = viewModel.exportEntry {
                ExportSummarySheet(
                    summary: summary,
                    onExport: { viewModel.confirmExport() },
                    onUpgrade: { viewModel.upgradeForExport() },
                    onCancel: { viewModel.dismissExportEntry() })
            }
        }
        .alert(Text("export.requiresPro.title"), isPresented: requiresProBinding) {
            Button("export.requiresPro.upgrade") { viewModel.upgradeForExport() }
            Button("common.cancel", role: .cancel) { viewModel.dismissExportEntry() }
        } message: {
            Text("export.requiresPro.message")
        }
        .fullScreenCover(isPresented: statusBinding) {
            ExportStatusView(viewModel: viewModel)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            HStack {
                CloseButton { Task { await viewModel.close() } }
                Spacer()
                Text(verbatim: viewModel.name)
                    .font(RENNFont.bodyMedium)
                    .foregroundStyle(RENNColor.textPrimary)
                    .lineLimit(1)
                Spacer()
                Color.clear.frame(width: RENNMetrics.minimumTouchTarget, height: RENNMetrics.minimumTouchTarget)
            }
            .padding(.horizontal, RENNMetrics.sideMargin)

            MetalPreviewView(
                engine: engine, player: player, recipe: viewModel.recipe,
                sourceDimensions: viewModel.displayDimensions, showsWatermark: viewModel.showsWatermark,
                bypassCreative: viewModel.showsOriginal)
                .clipShape(RoundedRectangle(cornerRadius: RENNMetrics.cardRadius, style: .continuous))
                .padding(.horizontal, RENNMetrics.sideMargin)
                .accessibilityLabel(Text("preview.accessibility"))

            scrubber

            HStack(spacing: 12) {
                controlButton(
                    player.isPlaying ? "pause.fill" : "play.fill",
                    label: player.isPlaying ? "preview.pause" : "preview.play",
                    isOn: false) { player.togglePlayback() }
                controlButton("circle.lefthalf.filled", label: "preview.beforeAfter", isOn: viewModel.showsOriginal) {
                    viewModel.showsOriginal.toggle()
                }
                controlButton(
                    viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: viewModel.isMuted ? "preview.unmute" : "preview.mute",
                    isOn: viewModel.isMuted) { viewModel.toggleMute() }
                    .disabled(!viewModel.hasAudio)
                controlButton("repeat", label: "preview.loop", isOn: viewModel.isLooping) {
                    viewModel.isLooping.toggle()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("preview.intensity")
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.textSecondary)
                    Spacer()
                    if viewModel.recipe?.lookID?.rawValue.hasPrefix("dev.") == true {
                        DevelopmentFixtureBadge()
                    }
                }
                Slider(
                    value: Binding(get: { viewModel.intensity }, set: { viewModel.setIntensity($0) }),
                    in: 0...1)
                    .tint(RENNColor.brandYellow)
                    .accessibilityLabel(Text("preview.intensity"))
            }
            .padding(.horizontal, RENNMetrics.sideMargin)

            Button("preview.export") {
                Task { await viewModel.requestExport() }
            }
            .buttonStyle(.rennPrimary)
            .disabled(viewModel.exportState != .idle && isExportRunning)
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.bottom, 8)
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(get: { player.currentSeconds }, set: { player.seek(to: $0) }),
                in: 0...max(0.01, player.durationSeconds))
                .tint(RENNColor.textPrimary)
                .accessibilityLabel(Text("preview.position"))
            HStack {
                Text(verbatim: Self.timestamp(player.currentSeconds))
                Spacer()
                Text(verbatim: Self.timestamp(player.durationSeconds))
            }
            .font(RENNFont.roboto(12, relativeTo: .caption))
            .foregroundStyle(RENNColor.textSecondary)
            .monospacedDigit()
        }
        .padding(.horizontal, RENNMetrics.sideMargin)
    }

    private func controlButton(
        _ symbol: String, label: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isOn ? RENNColor.onPrimary : RENNColor.textPrimary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(isOn ? RENNColor.brandYellow : Color.white.opacity(0.08)))
        }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func unavailable(_ readiness: ProjectSummary.Readiness?) -> some View {
        VStack(spacing: 16) {
            HStack {
                CloseButton { Task { await viewModel.close() } }
                Spacer()
            }
            Spacer()
            Text(readiness == .sourceMissing
                 ? LocalizedStringKey("preview.unavailable.sourceMissing")
                 : LocalizedStringKey("preview.unavailable.generic"))
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(RENNMetrics.sideMargin)
    }

    private var isExportRunning: Bool {
        switch viewModel.exportState {
        case .preparing, .rendering, .finalizing, .savingToPhotos: true
        default: false
        }
    }

    private var summaryBinding: Binding<Bool> {
        Binding(
            get: { if case .summary = viewModel.exportEntry { true } else { false } },
            set: { if !$0, case .summary = viewModel.exportEntry { viewModel.dismissExportEntry() } })
    }

    private var requiresProBinding: Binding<Bool> {
        Binding(
            get: { viewModel.exportEntry == .requiresPro },
            set: { if !$0, viewModel.exportEntry == .requiresPro { viewModel.dismissExportEntry() } })
    }

    private var statusBinding: Binding<Bool> {
        Binding(get: { viewModel.exportState != .idle }, set: { _ in })
    }

    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
