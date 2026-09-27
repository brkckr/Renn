import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("App router (01 P02, 04 A02)")
struct RouterTests {
    private func router(dual: DualCameraAvailability = .supported) -> AppRouter {
        AppRouter(captureCapabilities: FixedCaptureCapabilities(dual))
    }

    @Test func launchRoutesOnceToOnboardingOrMain() {
        let first = router()
        first.finishSplash(hasCompletedOnboarding: false)
        #expect(first.launchPhase == .onboarding)
        first.finishSplash(hasCompletedOnboarding: true)
        #expect(first.launchPhase == .onboarding, "Splash completion must not replay")
        first.finishOnboarding()
        #expect(first.launchPhase == .main)
        #expect(first.selectedTab == .home)

        let returning = router()
        returning.finishSplash(hasCompletedOnboarding: true)
        #expect(returning.launchPhase == .main)
    }

    @Test func seeAllSelectsExistingProjectsTab() {
        let router = router()
        router.showAllProjects()
        #expect(router.selectedTab == .projects)
        #expect(router.presentedFlow == nil)
    }

    @Test func repeatedCreationTapsPresentOneDestination() {
        let router = router()
        router.openCreationMenu()
        router.choose(.recordVideo)
        router.choose(.recordVideo)
        router.choose(.importVideo)
        #expect(router.presentedFlow == .camera(lookID: nil))
    }

    @Test func unsupportedDualCamExplainsInsteadOfPaywall() {
        let router = router(dual: .unsupported(.hardwareNotSupported))
        router.openCreationMenu()
        router.choose(.recordWithBothCameras)
        #expect(router.presentedFlow == .dualCameraUnavailable(.hardwareNotSupported, lookID: nil))
        router.replaceFlow(with: .importVideo(lookID: nil))
        #expect(router.presentedFlow == .importVideo(lookID: nil))
    }

    @Test func supportedDualCamOpensDualCamera() {
        let router = router()
        router.openCreationMenu()
        router.choose(.recordWithBothCameras)
        #expect(router.presentedFlow == .dualCamera(lookID: nil))
    }

    @Test func createWithLookCarriesLookIntoFlow() {
        let router = router()
        router.select(.looks)
        router.inspectLook("dev.diagnostic")
        router.startCreation(withLook: "dev.diagnostic")
        #expect(router.inspectedLookID == nil)
        #expect(router.selectedTab == .home)
        #expect(router.isCreationMenuOpen)
        router.choose(.importVideo)
        #expect(router.presentedFlow == .importVideo(lookID: "dev.diagnostic"))
    }

    @Test func menuOnlyOpensOnHome() {
        let router = router()
        router.select(.settings)
        router.openCreationMenu()
        #expect(!router.isCreationMenuOpen)
    }

    @Test func onlyOneFlowAtATime() {
        let router = router()
        let first = ProjectID()
        router.openProject(first)
        router.openProject(ProjectID())
        router.showPaywall(.settings)
        #expect(router.presentedFlow == .projectPreview(first))
        router.dismissFlow()
        #expect(router.presentedFlow == nil)
    }

    @Test func nestedPaywallOnlyOverAFlowAndClearedOnDismiss() {
        let router = router()
        router.showNestedPaywall(.freeDurationLimit)
        #expect(router.nestedPaywall == nil)
        router.openCreationMenu()
        router.choose(.importVideo)
        router.showNestedPaywall(.freeDurationLimit)
        #expect(router.nestedPaywall == .freeDurationLimit)
        router.dismissFlow()
        #expect(router.nestedPaywall == nil)
    }

    @Test func emptyProjectsRouteOpensHomeCreation() {
        let router = router()
        router.select(.projects)
        router.goHomeAndOpenCreation()
        #expect(router.selectedTab == .home)
        #expect(router.isCreationMenuOpen)
    }
}
