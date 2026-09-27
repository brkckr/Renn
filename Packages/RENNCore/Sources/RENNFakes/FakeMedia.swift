import Foundation
import RENNDomain

/// Scripted renderer for coordinator tests. Can hold until released to test cancellation.
public actor FakeExportRenderer: ExportRendering {
    public var outcome: Result<RationalTime, ExportFailure>
    public var holdUntilCancelled = false
    public private(set) var renderCount = 0

    public init(outcome: Result<RationalTime, ExportFailure> = .success(.seconds(10)), holdUntilCancelled: Bool = false) {
        self.outcome = outcome
        self.holdUntilCancelled = holdUntilCancelled
    }

    public func render(
        plan: ExportPlan, sources: ExportSourceFiles, outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(ExportFailure) -> RationalTime {
        renderCount += 1
        progress(plan.duration.approximateSeconds / 2)
        if holdUntilCancelled {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            throw .cancelled
        }
        return try outcome.get()
    }
}

public actor FakePhotosSaver: PhotosSaving {
    public var outcomes: [PhotosSaveOutcome]
    public private(set) var savedURLs: [URL] = []

    public init(outcomes: [PhotosSaveOutcome] = [.saved(localIdentifier: "FAKE/L0/001")]) {
        self.outcomes = outcomes
    }

    public func saveVideo(at url: URL) async -> PhotosSaveOutcome {
        savedURLs.append(url)
        return outcomes.isEmpty ? .failed : outcomes.removeFirst()
    }
}
