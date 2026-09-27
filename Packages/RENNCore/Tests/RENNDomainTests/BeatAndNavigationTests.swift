import Testing
@testable import RENNDomain

@Suite("Beat mute rule (01 P06)")
struct BeatTests {
    @Test("effectiveBeat truth table", arguments: [
        (true, false, true, true),
        (true, true, true, false),
        (true, false, false, false),
        (false, false, true, false),
        (false, true, false, false),
    ])
    func truthTable(enabled: Bool, muted: Bool, hasAudio: Bool, expected: Bool) {
        let beat = BeatSettings(isEnabled: enabled, intensity: 0.8)
        #expect(beat.isEffective(audioMuted: muted, sourceHasUsableAudio: hasAudio) == expected)
    }

    @Test func muteDoesNotMutateChoice() {
        let beat = BeatSettings(isEnabled: true, intensity: 0.8)
        #expect(beat.effectiveIntensity(audioMuted: true, sourceHasUsableAudio: true) == 0)
        // Unmute restores the previous enable/intensity because the value never changed.
        #expect(beat.effectiveIntensity(audioMuted: false, sourceHasUsableAudio: true) == 0.8)
        #expect(beat.isEnabled && beat.intensity == 0.8)
    }

    @Test func nonFiniteIntensityIsZero() {
        #expect(BeatSettings(isEnabled: true, intensity: .nan).intensity == 0)
    }
}

@Suite("Main navigation rules (01 P02, 03 M03)")
struct NavigationTests {
    @Test func tabOrder() {
        #expect(AppTab.allCases == [.home, .looks, .projects, .settings])
    }

    @Test func createButtonOnlyOnHome() {
        var state = MainNavigationState()
        #expect(state.isCreateButtonAvailable)
        for tab in [AppTab.looks, .projects, .settings] {
            state.select(tab)
            #expect(!state.isCreateButtonAvailable)
            let opened = state.openCreationMenu()
            #expect(!opened)
            #expect(!state.isCreationMenuOpen)
        }
    }

    @Test func actionIsCapturedOnce() {
        var state = MainNavigationState()
        state.openCreationMenu()
        do { let result = state.choose(.importVideo); #expect(result == CreationRequest(action: .importVideo, lookID: nil)) }
        do { let result = state.choose(.importVideo); #expect(result == nil) }
        #expect(!state.isCreationMenuOpen)
    }

    @Test func createWithLookCarriesIntentAndCancelClearsIt() {
        var state = MainNavigationState()
        state.select(.looks)
        state.startCreation(withLook: "dev.diagnostic")
        #expect(state.selectedTab == .home)
        #expect(state.isCreationMenuOpen)
        #expect(state.pendingLookID == "dev.diagnostic")
        state.dismissCreationMenu()
        #expect(state.pendingLookID == nil)

        state.startCreation(withLook: "dev.diagnostic")
        do { let result = state.choose(.recordVideo); #expect(result == CreationRequest(action: .recordVideo, lookID: "dev.diagnostic")) }
        #expect(state.pendingLookID == nil)
    }

    @Test func selectingTabClosesMenuWithoutCreating() {
        var state = MainNavigationState()
        state.startCreation(withLook: "x")
        state.select(.projects)
        #expect(!state.isCreationMenuOpen)
        #expect(state.pendingLookID == nil)
        do { let result = state.choose(.recordVideo); #expect(result == nil) }
    }
}

@Suite("Onboarding pager (01 P10)")
struct OnboardingPagerTests {
    @Test func fourPagesThenFinishOnce() {
        var pager = OnboardingPager()
        do { let result = pager.next(); #expect(result == .movedTo(1)) }
        do { let result = pager.next(); #expect(result == .movedTo(2)) }
        do { let result = pager.next(); #expect(result == .movedTo(3)) }
        #expect(pager.isLastPage)
        do { let result = pager.next(); #expect(result == .finished) }
        do { let result = pager.next(); #expect(result == .ignored) }
        do { let result = pager.skip(); #expect(result == .ignored) }
    }

    @Test func skipFinishesImmediatelyOnce() {
        var pager = OnboardingPager()
        do { let result = pager.skip(); #expect(result == .finished) }
        do { let result = pager.skip(); #expect(result == .ignored) }
    }
}

@Suite("Identity (P01 / C01)")
struct IdentityTests {
    @Test func exactIdentity() {
        #expect(AppIdentity.displayName == "RENN")
        #expect(AppIdentity.bundleIdentifier == "tzlapp.studio.renn")
        #expect(AppIdentity.watermarkPhrase == "shot by RENN")
        #expect(AppIdentity.proEntitlementID == "pro")
    }
}
