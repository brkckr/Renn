import SwiftUI
import RENNDomain
import RENNFeatures

/// Main tab shell. All four tab views stay alive so returning from a flow or another tab
/// preserves list positions (01 P02). Flows are full-screen and hide the tab navigation.
struct MainShellView: View {
    let composition: AppComposition

    @State private var homeViewModel: HomeViewModel
    @State private var looksViewModel: LooksViewModel
    @State private var projectsViewModel: ProjectsViewModel
    @State private var settingsViewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(composition: AppComposition) {
        self.composition = composition
        _homeViewModel = State(initialValue: composition.makeHomeViewModel())
        _looksViewModel = State(initialValue: composition.makeLooksViewModel())
        _projectsViewModel = State(initialValue: composition.makeProjectsViewModel())
        _settingsViewModel = State(initialValue: composition.makeSettingsViewModel())
    }

    var body: some View {
        @Bindable var router = composition.router
        ZStack(alignment: .bottom) {
            ZStack {
                tabContent(.home) { HomeView(viewModel: homeViewModel) }
                tabContent(.looks) { LooksView(viewModel: looksViewModel) }
                tabContent(.projects) { ProjectsView(viewModel: projectsViewModel) }
                tabContent(.settings) {
                    SettingsView(
                        viewModel: settingsViewModel,
                        configuration: composition.configuration,
                        effectiveLocalization: composition.localization.effectiveLocalization)
                }
            }
            // Reserve B+12+64+16 for content; the safe area itself is counted once by SwiftUI.
            .safeAreaPadding(.bottom, RENNMetrics.reservedContentBottom)

            if router.isCreationMenuOpen {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { router.dismissCreationMenu() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }

            if router.selectedTab == .projects && projectsViewModel.isSelecting {
                // Select mode on the shelf: its actions take the tab bar's place (like Photos).
                ProjectsSelectionBar(viewModel: projectsViewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                navigationBar
            }
        }
        .environment(\.coachMarks, composition.coachMarks)
        // Tips spotlight tab content and the bar alike, so the host sits above both.
        .coachMarkHost(composition.coachMarks)
        .task(id: coachMoment) { await startCoachTour(coachMoment) }
        .animation(reduceMotion ? RENNMotion.reducedDissolve : .easeOut(duration: 0.18), value: router.isCreationMenuOpen)
        .animation(
            reduceMotion ? RENNMotion.reducedDissolve : RENNMotion.emphasized,
            value: router.selectedTab == .projects && projectsViewModel.isSelecting)
        // Leaving the shelf (e.g. a flow that switches tabs) ends select mode.
        .onChange(of: router.selectedTab) { _, tab in
            if tab != .projects { projectsViewModel.endSelection() }
        }
        .fullScreenCover(item: $router.presentedFlow) { flow in
            PresentedFlowView(flow: flow, composition: composition)
                .environment(\.locale, composition.localization.locale)
                .environment(\.showcase, composition.showcase)
                .environment(\.coachMarks, composition.coachMarks)
        }
        .sheet(item: $router.inspectedLookID) { lookID in
            LookInspectionView(viewModel: composition.makeLookInspectionViewModel(lookID: lookID))
                .environment(\.locale, composition.localization.locale)
                .environment(\.showcase, composition.showcase)
        }
    }

    // MARK: Coach marks

    /// The tab whose tour may start now: its content is ready and nothing covers it (no flow,
    /// menu, Look sheet or select mode). Nil when no tour may start.
    private var coachMoment: CoachTour? {
        let router = composition.router
        guard scenePhase == .active, router.presentedFlow == nil, !router.isCreationMenuOpen,
              router.inspectedLookID == nil
        else { return nil }
        switch router.selectedTab {
        case .home:
            return homeViewModel.catalogState == .loaded && homeViewModel.recommendedLook != nil ? .home : nil
        case .looks:
            return looksViewModel.loadState == .loaded && !looksViewModel.visibleLooks.isEmpty ? .looks : nil
        case .projects:
            return projectsViewModel.hasLoaded && !projectsViewModel.projects.isEmpty
                && !projectsViewModel.isSelecting ? .projects : nil
        case .settings:
            return nil
        }
    }

    /// Waits for the screen to settle (tab switch, onboarding hand-off), then starts its tour
    /// once. A change of moment cancels the wait.
    private func startCoachTour(_ tour: CoachTour?) async {
        guard let tour, composition.coachMarks.isPending(tour) else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        composition.coachMarks.start(tour, steps: tour.steps.count)
    }

    private var navigationBar: some View {
        let router = composition.router
        return GlassNavigationBar(
            selectedTab: router.selectedTab,
            isMenuOpen: router.isCreationMenuOpen,
            dualCameraAvailability: router.dualCameraAvailability,
            onSelect: { router.select($0) },
            onToggleMenu: {
                if router.isCreationMenuOpen {
                    router.dismissCreationMenu()
                } else {
                    router.openCreationMenu()
                }
            },
            onChoose: { router.choose($0) })
    }

    private func tabContent<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = composition.router.selectedTab == tab
        return content()
            // Decorative playback runs only on the visible tab with no flow above it.
            .environment(\.showcaseIsActive, isSelected && composition.router.presentedFlow == nil)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

extension AppTab {
    var titleKey: LocalizedStringKey {
        switch self {
        case .home: "tab.home"
        case .looks: "tab.looks"
        case .projects: "tab.projects"
        case .settings: "tab.settings"
        }
    }

    var icon: RENNIcon {
        switch self {
        case .home: .home
        case .looks: .looks
        case .projects: .projects
        case .settings: .settings
        }
    }
}
