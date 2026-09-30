import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("Coach marks (owner-approved 2026-09-30)")
struct CoachMarksTests {
    @Test func tourRunsStepByStepAndShowsOnce() {
        let store = InMemoryAppPreferencesStore()
        let coach = CoachMarks(preferencesStore: store)
        #expect(coach.isPending(.home))
        #expect(coach.start(.home, steps: 3))
        #expect(coach.activeTour == .home && coach.stepIndex == 0)
        #expect(!coach.start(.looks, steps: 2), "One tour at a time")
        coach.next()
        coach.next()
        #expect(coach.stepIndex == 2 && coach.isLastStep)
        #expect(store.stored.seenCoachTours.isEmpty, "Nothing is recorded before the tour ends")
        coach.next()
        #expect(coach.activeTour == nil)
        #expect(store.stored.seenCoachTours == [.home])
        #expect(!coach.isPending(.home))
        #expect(!coach.start(.home, steps: 3), "A finished tour never shows again")
        #expect(coach.isPending(.looks), "Other screens keep their tours")
    }

    @Test func skipTurnsEveryRemainingTourOff() {
        let store = InMemoryAppPreferencesStore()
        let coach = CoachMarks(preferencesStore: store)
        coach.start(.home, steps: 3)
        coach.next()
        coach.skip()
        #expect(coach.activeTour == nil)
        #expect(store.stored.coachMarksSkipped)
        for tour in CoachTour.allCases {
            #expect(!coach.isPending(tour))
        }
    }

    @Test func settingsCanBringToursBack() {
        let store = InMemoryAppPreferencesStore(AppPreferences(seenCoachTours: [.home], coachMarksSkipped: true))
        let coach = CoachMarks(preferencesStore: store)
        #expect(!coach.isPending(.projects))
        coach.resetAll()
        #expect(CoachTour.allCases.allSatisfy { coach.isPending($0) })
    }

    @Test func disabledCoachMarksNeverStart() {
        let coach = CoachMarks(preferencesStore: InMemoryAppPreferencesStore(), isEnabled: false)
        #expect(!coach.isPending(.home))
        #expect(!coach.start(.home, steps: 3))
        #expect(coach.activeTour == nil)
    }

    @Test func preferencesSavedBeforeCoachMarksStillDecode() throws {
        let old = #"{"hasCompletedOnboarding":true,"language":"turkish","diagnosticsConsent":"declined"}"#
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data(old.utf8))
        #expect(decoded == AppPreferences(hasCompletedOnboarding: true, language: .turkish, diagnosticsConsent: .declined))

        let newer = #"{"hasCompletedOnboarding":true,"language":"system","diagnosticsConsent":"notAsked","seenCoachTours":["home","camera"],"coachMarksSkipped":false}"#
        let fromNewer = try JSONDecoder().decode(AppPreferences.self, from: Data(newer.utf8))
        #expect(fromNewer.seenCoachTours == [.home], "Unknown tours from a newer version are ignored")

        let roundTrip = AppPreferences(seenCoachTours: [.looks, .preview], coachMarksSkipped: true)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(roundTrip)) == roundTrip)
    }
}
