import XCTest

/// Simulator smoke flows through the real app UI (07 test level 4). Each test launches with
/// `-RENNUITestFreshState` (DEBUG only): empty in-memory projects and fresh preferences, so
/// onboarding shows and no state leaks between tests. Elements are found by accessibility
/// identifiers, not by display text, so the checks hold in both languages. Coach marks are off
/// (`-RENNUITestNoCoachMarks`) except in the test that covers them.
final class SmokeFlowUITests: XCTestCase {
    @MainActor
    private func launch(coachMarks: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-RENNUITestFreshState"]
        if !coachMarks { app.launchArguments += ["-RENNUITestNoCoachMarks"] }
        app.launch()
        return app
    }

    @MainActor
    private func launchAtHome(coachMarks: Bool = false) -> XCUIApplication {
        let app = launch(coachMarks: coachMarks)
        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 20), "Onboarding follows the splash on a fresh install")
        skip.tap()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    /// P10: Skip completes onboarding and routes Home once, with the creation button.
    @MainActor
    func testSkipOnboardingReachesHome() {
        let app = launchAtHome()
        XCTAssertTrue(app.buttons["creation.toggle"].exists)
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
    }

    /// P10 / 03 M02: four pages via Next (serialized during the wipe), then Get started → Home.
    @MainActor
    func testNextWalksAllPagesToHome() {
        let app = launch()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        for _ in 0..<4 {
            let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: next)
            wait(for: [enabled], timeout: 5)
            next.tap()
        }
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
    }

    /// P02 / D04: four tabs; the creation button exists only on Home.
    @MainActor
    func testTabsSelectAndCreateButtonIsHomeOnly() {
        let app = launchAtHome()
        for tab in ["tab.looks", "tab.projects", "tab.settings"] {
            app.buttons[tab].tap()
            XCTAssertTrue(app.buttons[tab].isSelected, "\(tab) becomes the selected tab")
            XCTAssertTrue(waitUntilGone(app.buttons["creation.toggle"]), "+ is absent outside Home (\(tab))")
        }
        XCTAssertTrue(app.buttons["settings.storage.clearCache"].exists, "Settings shows storage controls")
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.buttons["creation.toggle"].waitForExistence(timeout: 5), "+ returns on Home")
    }

    /// P02 / D04: the creation menu offers exactly the three creation rows and closes again.
    @MainActor
    func testCreationMenuOpensWithThreeRowsAndCloses() {
        let app = launchAtHome()
        app.buttons["creation.toggle"].tap()
        XCTAssertTrue(app.buttons["creation.recordVideo"].waitForExistence(timeout: 5), "One tap on + opens the creation menu")
        XCTAssertTrue(app.buttons["creation.recordWithBothCameras"].exists)
        XCTAssertTrue(app.buttons["creation.importVideo"].exists)
        app.buttons["creation.toggle"].tap()
        XCTAssertTrue(waitUntilGone(app.buttons["creation.recordVideo"]))
    }

    /// P05 / C06: without multi-camera support (always true on the Simulator) Dual-Cam explains
    /// the reason and offers the one-camera route, never a paywall.
    @MainActor
    func testUnsupportedDualCamExplainsAndOffersOneCamera() {
        let app = launchAtHome()
        app.buttons["creation.toggle"].tap()
        let dual = app.buttons["creation.recordWithBothCameras"]
        XCTAssertTrue(dual.waitForExistence(timeout: 5), "One tap on + opens the creation menu")
        dual.tap()
        XCTAssertTrue(app.buttons["dual.unavailable.oneCamera"].waitForExistence(timeout: 10))
    }

    /// Coach marks (owner-approved): Home's tips appear once on the first visit, Next walks them,
    /// Skip closes them and turns the other screens' tips off, and Home works normally after.
    @MainActor
    func testHomeCoachMarksWalkAndSkip() {
        let app = launchAtHome(coachMarks: true)
        let next = app.buttons["coach.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Home tips appear on the first visit")
        next.tap()
        let skip = app.buttons["coach.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "The second tip still offers Skip")
        skip.tap()
        XCTAssertTrue(waitUntilGone(app.buttons["coach.next"]), "Skip closes the tips")
        app.buttons["tab.looks"].tap()
        XCTAssertFalse(app.buttons["coach.next"].waitForExistence(timeout: 3), "Skip turned the other tips off")
        app.buttons["tab.home"].tap()
        app.buttons["creation.toggle"].tap()
        XCTAssertTrue(app.buttons["creation.recordVideo"].waitForExistence(timeout: 5), "+ works after the tips")
    }
}
