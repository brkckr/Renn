import Observation
import RENNDomain

/// Four onboarding pages: no name, account, permission or paywall (01 P10).
@MainActor
@Observable
public final class OnboardingViewModel {
    public private(set) var pager = OnboardingPager()

    private let preferencesStore: any AppPreferencesStoring
    private let onFinished: @MainActor () -> Void

    public init(preferencesStore: any AppPreferencesStoring, onFinished: @escaping @MainActor () -> Void) {
        self.preferencesStore = preferencesStore
        self.onFinished = onFinished
    }

    public var pageIndex: Int { pager.pageIndex }
    public var pageCount: Int { OnboardingPager.pageCount }
    public var isLastPage: Bool { pager.isLastPage }

    public func next() {
        handle(pager.next())
    }

    public func skip() {
        handle(pager.skip())
    }

    private func handle(_ outcome: OnboardingPager.Outcome) {
        guard outcome == .finished else { return }
        var preferences = preferencesStore.load()
        preferences.hasCompletedOnboarding = true
        preferencesStore.save(preferences)
        onFinished()
    }
}
