import SwiftUI
import RENNDomain
import RENNFeatures

/// Home (02 D04): small RENN brand, one recommended-Look hero, last-four Looks when
/// available, recent project cases with See all. Creation lives in +, not in the hero.
/// Owner-approved additions: the hero plays the street demo live with the recommended Look,
/// catalog Looks are showcased until one is used, tapes stand on a shelf (an empty slot on first
/// use, never fake history) and a PRO badge opens the paywall for Free users.
struct HomeView: View {
    let viewModel: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .padding(.top, 8)

                recommendedSection

                if !viewModel.recentLooks.isEmpty {
                    lookRail(title: "home.recentLooks", looks: viewModel.recentLooks)
                } else if !viewModel.showcaseLooks.isEmpty {
                    lookRail(title: "home.lookShowcase", looks: viewModel.showcaseLooks)
                }

                projectsSection
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .task { await viewModel.observe() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            RENNWordmark(size: 22)
            Spacer()
            ProBadge(isPro: viewModel.isPro) { viewModel.showPaywall() }
        }
    }

    @ViewBuilder
    private var recommendedSection: some View {
        switch viewModel.catalogState {
        case .loading:
            RoundedRectangle(cornerRadius: RENNMetrics.panelRadius, style: .continuous)
                .fill(RENNColor.glassOpaqueFallback)
                .frame(height: 300)
                .overlay(ProgressView())
        case .failed:
            Label(
                "home.catalogError",
                systemImage: "exclamationmark.triangle")
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textSecondary)
        case .loaded:
            if let look = viewModel.recommendedLook {
                Button {
                    viewModel.inspect(look.id)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HomeHero(look: look)
                            .frame(height: 220)
                            .clipped()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("home.recommended")
                                .font(RENNFont.secondary)
                                .foregroundStyle(RENNColor.brandYellow)
                            Text(LocalizedStringKey(look.nameKey))
                                .font(RENNFont.heading)
                                .foregroundStyle(RENNColor.textPrimary)
                            Text(LocalizedStringKey(look.descriptionKey))
                                .font(RENNFont.secondary)
                                .foregroundStyle(RENNColor.textSecondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .glassBackground(cornerRadius: RENNMetrics.panelRadius)
                    .clipShape(RoundedRectangle(cornerRadius: RENNMetrics.panelRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("home.recommended.hint"))
            }
        }
    }

    /// Poster cards for recently used Looks, or catalog Looks to try before any is used.
    private func lookRail(title: LocalizedStringKey, looks: [LookDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(looks) { look in
                        Button {
                            viewModel.inspect(look.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                LookPoster(look: look)
                                    .frame(width: 112, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(LocalizedStringKey(look.nameKey))
                                    .font(RENNFont.roboto(13, medium: true, relativeTo: .footnote))
                                    .foregroundStyle(RENNColor.textPrimary)
                                    .lineLimit(2)
                                    .frame(width: 112, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(Text("looks.card.hint"))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "home.recentTapes") {
                if !viewModel.recentProjects.isEmpty {
                    Button("home.seeAll") { viewModel.seeAll() }
                        .font(RENNFont.roboto(14, medium: true, relativeTo: .subheadline))
                        .foregroundStyle(RENNColor.brandYellow)
                        .frame(minHeight: RENNMetrics.minimumTouchTarget)
                }
            }
            if viewModel.showsFirstUsePrompt {
                FirstTapeShelf()
            } else {
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(viewModel.recentProjects) { project in
                            Button {
                                viewModel.open(project.id)
                            } label: {
                                ProjectCaseView(project: project, loadPoster: { await viewModel.poster(for: $0) })
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(Text(verbatim: project.name.value))
                        }
                        ForEach(0..<max(0, HomeViewModel.maximumRecentProjects - viewModel.recentProjects.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)
                    ShelfPlank()
                        .frame(height: 10)
                }
            }
        }
    }
}

/// The recommended Look playing live over the street demo, with PLAY and date OSD; a still
/// poster under Reduce Motion or while Home is hidden.
private struct HomeHero: View {
    let look: LookDefinition

    @Environment(\.showcase) private var showcase
    @Environment(\.showcaseIsActive) private var isTabActive
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playback = DemoPlayback()

    private var isActive: Bool { isTabActive && scenePhase == .active && !reduceMotion }

    var body: some View {
        ZStack {
            LookPoster(look: look)
            if let showcase, !reduceMotion, playback.isReady {
                DemoVideoView(
                    engine: showcase.engine, player: playback.player,
                    recipe: ShowcaseMedia.recipe(for: look), isActive: isActive)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            OSDText("PLAY ▶").padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            OSDText(Self.stamp).padding(12)
        }
        .animation(.easeOut(duration: 0.25), value: playback.isReady)
        .accessibilityHidden(true)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            await playback.start(.street)
            playback.setActive(isActive)
        }
        .onChange(of: isActive) { _, active in playback.setActive(active) }
        .onDisappear { playback.stop() }
    }

    /// Today's date in the camcorder stamp format used by the date indicator (02 D06).
    private static var stamp: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return (try? StampDate(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1))?.text ?? ""
    }
}

private struct OSDText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(RENNFont.pressStart(10))
            .foregroundStyle(Color(white: 0.97))
            .shadow(color: .black.opacity(0.7), radius: 1.5, x: 0, y: 1)
    }
}

/// First use (02 D04): one empty tape slot on the shelf that points to +, with the create prompt.
private struct FirstTapeShelf: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(RENNColor.brandYellow.opacity(0.7))
                    .overlay {
                        RENNIcon.create.image
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(RENNColor.brandYellow)
                    }
                    .frame(width: 84, height: 126)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("home.firstUse.title")
                        .font(RENNFont.bodyMedium)
                        .foregroundStyle(RENNColor.textPrimary)
                    Text("home.firstUse.body")
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.textSecondary)
                    // Points to the + in the bottom bar.
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(RENNColor.brandYellow)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 8)
            ShelfPlank()
                .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
    }
}

/// PRO next to the wordmark: an upgrade button for Free users, a status badge for Pro.
private struct ProBadge: View {
    let isPro: Bool
    let action: () -> Void

    var body: some View {
        if isPro {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("home.pro.active"))
        } else {
            Button(action: action) {
                label
                    .frame(minHeight: RENNMetrics.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("home.pro.upgrade"))
            .accessibilityIdentifier("home.pro")
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            RENNIcon.crown.image
                .font(.system(size: 11, weight: .semibold))
            Text(verbatim: "PRO")
                .font(RENNFont.roboto(12, medium: true, relativeTo: .caption))
        }
        .foregroundStyle(isPro ? RENNColor.brandYellow : RENNColor.onPrimary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
            if isPro {
                Capsule().strokeBorder(RENNColor.brandYellow, lineWidth: 1.5)
            } else {
                Capsule().fill(RENNColor.brandYellow)
            }
        }
    }
}
