import Observation
import RENNDomain

/// Why the paywall is shown (06 C04 entry points only).
public enum PaywallReason: Hashable, Sendable, Identifiable {
    case settings
    case exportUpgrade
    case freeDurationLimit
    /// The PRO badge next to the Home wordmark (owner-approved).
    case home

    public var id: Self { self }
}

/// Full-screen flows that hide the global tab navigation (01 P02).
public enum PresentedFlow: Identifiable, Hashable, Sendable {
    case camera(lookID: LookID?)
    case dualCamera(lookID: LookID?)
    case dualCameraUnavailable(DualCameraUnsupportedReason, lookID: LookID?)
    case importVideo(lookID: LookID?)
    case projectPreview(ProjectID)
    case paywall(PaywallReason)

    public var id: Self { self }
}

public enum LaunchPhase: Equatable, Sendable {
    case splash
    case onboarding
    case main
}

/// Selected tab, typed routes and presented flows (04 A02). ViewModels never create
/// destination views; they call closures that the composition root binds to this router.
@MainActor
@Observable
public final class AppRouter {
    public private(set) var launchPhase: LaunchPhase = .splash
    public private(set) var navigation = MainNavigationState()
    public var presentedFlow: PresentedFlow?
    /// Look inspection sheet, a baseline subview of the catalog (02 D05).
    public var inspectedLookID: LookID?
    /// Paywall shown over a running flow (import Free limit, export upgrade intent), so the
    /// flow keeps its state and continues once after a verified upgrade (06 C03).
    public var nestedPaywall: PaywallReason?

    private let captureCapabilities: any CaptureCapabilityProviding

    public init(captureCapabilities: any CaptureCapabilityProviding) {
        self.captureCapabilities = captureCapabilities
    }

    public var selectedTab: AppTab { navigation.selectedTab }
    public var isCreationMenuOpen: Bool { navigation.isCreationMenuOpen }

    /// Unsupported Dual-Cam stays discoverable with an explanation (02 D04).
    public var dualCameraAvailability: DualCameraAvailability {
        captureCapabilities.dualCameraAvailability()
    }

    // MARK: Launch

    /// Called once when the in-app splash finishes. Never replays on foreground return (03 M01).
    public func finishSplash(hasCompletedOnboarding: Bool) {
        guard launchPhase == .splash else { return }
        launchPhase = hasCompletedOnboarding ? .main : .onboarding
    }

    public func finishOnboarding() {
        guard launchPhase == .onboarding else { return }
        navigation = MainNavigationState()
        launchPhase = .main
    }

    // MARK: Tabs and creation menu

    public func select(_ tab: AppTab) {
        navigation.select(tab)
    }

    /// Home "See all" selects the existing Projects tab; no duplicate collection screen.
    public func showAllProjects() {
        navigation.select(.projects)
    }

    public func openCreationMenu() {
        navigation.openCreationMenu()
    }

    public func dismissCreationMenu() {
        navigation.dismissCreationMenu()
    }

    /// Catalog "Create with this Look".
    public func startCreation(withLook lookID: LookID) {
        inspectedLookID = nil
        navigation.startCreation(withLook: lookID)
    }

    /// Captures the chosen row once, then presents its destination once.
    public func choose(_ action: CreationAction) {
        guard presentedFlow == nil, let request = navigation.choose(action) else { return }
        switch request.action {
        case .recordVideo:
            presentedFlow = .camera(lookID: request.lookID)
        case .recordWithBothCameras:
            switch captureCapabilities.dualCameraAvailability() {
            case .supported:
                presentedFlow = .dualCamera(lookID: request.lookID)
            case .unsupported(let reason):
                presentedFlow = .dualCameraUnavailable(reason, lookID: request.lookID)
            }
        case .importVideo:
            presentedFlow = .importVideo(lookID: request.lookID)
        }
    }

    /// Replaces the current flow (e.g. Dual-Cam unavailable -> normal camera/import).
    public func replaceFlow(with flow: PresentedFlow) {
        presentedFlow = flow
    }

    // MARK: Other routes

    public func inspectLook(_ lookID: LookID) {
        inspectedLookID = lookID
    }

    public func openProject(_ projectID: ProjectID) {
        guard presentedFlow == nil else { return }
        presentedFlow = .projectPreview(projectID)
    }

    public func showPaywall(_ reason: PaywallReason) {
        guard presentedFlow == nil else { return }
        presentedFlow = .paywall(reason)
    }

    public func showNestedPaywall(_ reason: PaywallReason) {
        guard presentedFlow != nil else { return }
        nestedPaywall = reason
    }

    /// Closing a flow returns to the originating tab; tab views stay alive, so list
    /// positions are preserved.
    public func dismissFlow() {
        nestedPaywall = nil
        presentedFlow = nil
    }

    /// Empty-state route from Projects back to Home creation.
    public func goHomeAndOpenCreation() {
        navigation.select(.home)
        navigation.openCreationMenu()
    }
}
