/// Four user-controlled onboarding pages (01 P10, 03 M02). Next/Skip never wait for
/// scene animation; completion is reported exactly once.
public struct OnboardingPager: Sendable, Equatable {
    public static let pageCount = 4

    public private(set) var pageIndex = 0
    public private(set) var isFinished = false

    public init() {}

    public var isLastPage: Bool { pageIndex == OnboardingPager.pageCount - 1 }

    public enum Outcome: Sendable, Equatable {
        case movedTo(Int)
        /// Onboarding just completed; persist completion and route Home once.
        case finished
        /// Already finished; ignore.
        case ignored
    }

    public mutating func next() -> Outcome {
        guard !isFinished else { return .ignored }
        if isLastPage { return finish() }
        pageIndex += 1
        return .movedTo(pageIndex)
    }

    public mutating func skip() -> Outcome {
        guard !isFinished else { return .ignored }
        return finish()
    }

    private mutating func finish() -> Outcome {
        isFinished = true
        return .finished
    }
}
