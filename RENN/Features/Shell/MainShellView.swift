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

            GlassNavigationBar(
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
        .animation(reduceMotion ? RENNMotion.reducedDissolve : .easeOut(duration: 0.18), value: router.isCreationMenuOpen)
        .fullScreenCover(item: $router.presentedFlow) { flow in
            PresentedFlowView(flow: flow, composition: composition)
                .environment(\.locale, composition.localization.locale)
        }
        .sheet(item: $router.inspectedLookID) { lookID in
            LookInspectionView(viewModel: composition.makeLookInspectionViewModel(lookID: lookID))
                .environment(\.locale, composition.localization.locale)
        }
    }

    private func tabContent<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = composition.router.selectedTab == tab
        return content()
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
