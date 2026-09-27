import CoreImage
import Foundation
import RENNDomain

/// `ExportRendering` over `ExportWorker` + `OutputValidator` (05 V09). Task cancellation
/// cancels the worker; any failure removes the partial file.
struct AVExportRenderer: ExportRendering {
    let engine: RenderEngine
    var beatTimelines: (any BeatTimelineProviding)?

    func render(
        plan: ExportPlan,
        sourceURL: URL,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(ExportFailure) -> RationalTime {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw .sourceUnavailable }
        var watermark: CIImage?
        var aspect = 4.0
        if plan.policy.requiresWatermark {
            let width = Double(plan.policy.dimensions.shortEdge) * WatermarkLayout.maximumWidthFraction
            guard let rendered = WatermarkRenderer.render(width: width) else { throw .renderFailed }
            watermark = rendered.image
            aspect = rendered.aspectRatio
        }
        // Beat never blocks export: without a timeline the video exports Look-only (05 V05).
        var timeline: BeatTimeline?
        if plan.recipe.beat.isEffective(audioMuted: plan.recipe.audioMuted, sourceHasUsableAudio: plan.source.metadata.hasUsableAudio) {
            timeline = try? await beatTimelines?.timeline(for: plan.source, fileURL: sourceURL)
        }
        let worker = ExportWorker(job: ExportWorker.Job(
            plan: plan, sourceURL: sourceURL, outputURL: outputURL, engine: engine,
            watermark: watermark, watermarkAspect: aspect, isHDRSource: plan.source.metadata.isHDR ?? false,
            beatTimeline: timeline))
        do {
            _ = try await withTaskCancellationHandler {
                try await worker.run(progress: progress)
            } onCancel: {
                worker.cancel()
            }
            return try await OutputValidator.validate(outputURL, plan: plan)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            switch error as? ExportWorkerError {
            case .cancelled?: throw .cancelled
            case .cannotRead?: throw .unsupportedSource
            case .cannotWrite?: throw Self.isOutOfSpace() ? .insufficientStorage : .writerFailed
            case .renderFailed?: throw .renderFailed
            case .validationFailed?: throw .validationFailed
            case nil: throw Task.isCancelled ? .cancelled : .writerFailed
            }
        }
    }

    private static func isOutOfSpace() -> Bool {
        let values = try? URL.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? .max) < 50 * 1024 * 1024
    }
}
