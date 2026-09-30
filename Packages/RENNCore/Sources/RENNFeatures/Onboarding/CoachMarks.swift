import Observation
import RENNDomain

/// One-time coach-mark tours (owner-approved 2026-09-30): a few short tips the first time the
/// user reaches Home, Looks, Projects and the preview. One tour runs at a time. Finishing a
/// tour marks only that tour seen; Skip turns every remaining tour off. Settings can bring
/// them back. Persisted in the app preferences, never tied to purchases.
@MainActor
@Observable
public final class CoachMarks {
    /// The tour on screen, or nil.
    public private(set) var activeTour: CoachTour?
    public private(set) var stepIndex = 0
    public private(set) var stepCount = 0

    private let preferencesStore: any AppPreferencesStoring
    /// False in UI tests that exercise other flows, so no tour covers their taps.
    private let isEnabled: Bool

    public init(preferencesStore: any AppPreferencesStoring, isEnabled: Bool = true) {
        self.preferencesStore = preferencesStore
        self.isEnabled = isEnabled
    }

    public var isLastStep: Bool { stepIndex >= stepCount - 1 }

    /// Not yet seen, not skipped, and coach marks are on.
    public func isPending(_ tour: CoachTour) -> Bool {
        guard isEnabled else { return false }
        let preferences = preferencesStore.load()
        return !preferences.coachMarksSkipped && !preferences.seenCoachTours.contains(tour)
    }

    /// Starts a pending tour with its number of steps; ignored while another tour runs.
    @discardableResult
    public func start(_ tour: CoachTour, steps: Int) -> Bool {
        guard activeTour == nil, steps > 0, isPending(tour) else { return false }
        activeTour = tour
        stepIndex = 0
        stepCount = steps
        return true
    }

    /// Next tip; after the last one the tour is finished and marked seen.
    public func next() {
        guard let tour = activeTour else { return }
        if isLastStep {
            update { $0.seenCoachTours.insert(tour) }
            end()
        } else {
            stepIndex += 1
        }
    }

    /// Ends this tour and every tour not yet shown.
    public func skip() {
        guard activeTour != nil else { return }
        update { $0.coachMarksSkipped = true }
        end()
    }

    /// Settings: show every tour again on its screen's next visit.
    public func resetAll() {
        update {
            $0.seenCoachTours = []
            $0.coachMarksSkipped = false
        }
    }

    private func end() {
        activeTour = nil
        stepIndex = 0
        stepCount = 0
    }

    private func update(_ change: (inout AppPreferences) -> Void) {
        var preferences = preferencesStore.load()
        change(&preferences)
        preferencesStore.save(preferences)
    }
}
