import Foundation
import Observation
import RENNDomain

/// What the export summary shows before the user commits (01 P09, 02 D09).
public struct ExportSummary: Sendable, Equatable {
    public let projectID: ProjectID
    public let policy: OutputPolicy
    public let duration: RationalTime
    public let includesAudio: Bool
    public let isHDRSource: Bool
    /// Long or high-quality jobs explain that processing may take time.
    public var isLongOrHighQuality: Bool {
        duration.approximateSeconds > 60
            || policy.dimensions.width * policy.dimensions.height > 1920 * 1080
            || policy.frameRate.approximateFPS > 31
    }
}

/// App-lifetime export owner (04 A03): one job at a time, survives sheet dismissal, explicit
/// cancel, render success separate from Photos save, save-only retry (05 V09).
@MainActor
@Observable
public final class ExportCoordinator {
    public enum SummaryResult: Equatable, Sendable {
        case ready(ExportSummary)
        /// Free project over 30 s: offer Pro before any job exists (06 C04).
        case requiresPro
        case unavailable
    }

    public enum JobState: Equatable, Sendable {
        case idle
        case preparing(ProjectID)
        case rendering(ProjectID, progress: Double)
        case finalizing(ProjectID)
        case savingToPhotos(ProjectID, OutputRecord)
        case completed(ProjectID, OutputRecord)
        case saveFailed(ProjectID, OutputRecord)
        case failed(ProjectID, ExportFailure)
        case cancelled(ProjectID)
    }

    public private(set) var state: JobState = .idle

    private var progress = ExportProgress()
    private var task: Task<Void, Never>?
    private var jobToken = UUID()
    private var isSaving = false

    private let projects: any ProjectStoring
    private let access: any AccessStateProviding
    private let renderer: any ExportRendering
    private let photos: any PhotosSaving
    private let lookPreferences: any LookPreferencesStoring
    private let telemetry: any TelemetryRecording

    public init(
        projects: any ProjectStoring,
        access: any AccessStateProviding,
        renderer: any ExportRendering,
        photos: any PhotosSaving,
        lookPreferences: any LookPreferencesStoring,
        telemetry: any TelemetryRecording
    ) {
        self.projects = projects
        self.access = access
        self.renderer = renderer
        self.photos = photos
        self.lookPreferences = lookPreferences
        self.telemetry = telemetry
    }

    public var isBusy: Bool {
        switch state {
        case .preparing, .rendering, .finalizing, .savingToPhotos: true
        default: false
        }
    }

    /// Resolves the actual output from current access; nothing is created yet.
    public func summary(for projectID: ProjectID) async -> SummaryResult {
        guard let record = try? await projects.project(projectID) else { return .unavailable }
        do {
            let plan = try ExportPlan.make(record: record, access: await access.currentAccess())
            return .ready(ExportSummary(
                projectID: projectID, policy: plan.policy, duration: plan.source.metadata.duration,
                includesAudio: plan.includesAudio, isHDRSource: plan.source.metadata.isHDR ?? false))
        } catch .requiresPro {
            return .requiresPro
        } catch {
            return .unavailable
        }
    }

    /// Starts one export after explicit intent. Returns false if a job is already running.
    @discardableResult
    public func start(_ projectID: ProjectID) -> Bool {
        guard !isBusy else { return false }
        let token = UUID()
        jobToken = token
        progress = ExportProgress()
        state = .preparing(projectID)
        task = Task { await self.run(projectID, token: token) }
        return true
    }

    /// Cancel before the local result is committed. Once saving to Photos started, the
    /// external save cannot be undone, so cancel is not offered then.
    public func cancel() {
        switch state {
        case .preparing, .rendering:
            task?.cancel()
        default:
            break
        }
    }

    /// Retries only the Photos save of the committed output; never re-renders.
    public func retrySave() async {
        guard case .saveFailed(let projectID, let output) = state, !isSaving else { return }
        await save(output, of: projectID, token: jobToken)
    }

    /// Clears a terminal state after the result/failure UI is dismissed.
    public func acknowledge() {
        guard !isBusy else { return }
        state = .idle
    }

    // MARK: Job

    private func run(_ projectID: ProjectID, token: UUID) async {
        let lease: ProjectLease
        let plan: ExportPlan
        let sourceURL: URL
        let jobURL: URL
        do {
            lease = try await projects.acquireLease(projectID, purpose: .export)
        } catch {
            finish(token, .failed(projectID, .sourceUnavailable))
            return
        }
        defer { Task { await projects.releaseLease(lease) } }

        do {
            let record = try await projects.project(projectID)
            // Snapshot access and recipe at job start (05 V09).
            plan = try ExportPlan.make(record: record, access: await access.currentAccess())
            sourceURL = await projects.fileURL(plan.source.relativePath)
            jobURL = try await projects.makeJobFileURL(fileExtension: "mp4")
        } catch {
            finish(token, .failed(projectID, .sourceUnavailable))
            return
        }
        await telemetry.record(.exportStarted(
            tier: plan.policy.tier, quality: .init(plan.policy.dimensions), duration: .bucket(plan.source.metadata.duration)))

        let total = plan.source.metadata.duration.approximateSeconds
        update(token, stage: .rendering, seconds: 0, total: total, projectID: projectID)
        let rendered: RationalTime
        do {
            rendered = try await renderer.render(plan: plan, sourceURL: sourceURL, outputURL: jobURL) { seconds in
                Task { @MainActor [weak self] in
                    self?.update(token, stage: .rendering, seconds: seconds, total: total, projectID: projectID)
                }
            }
        } catch {
            let cancelled = error == .cancelled || Task.isCancelled
            await telemetry.record(cancelled ? .exportCancelled(stage: .rendering) : .exportFailed(stage: .rendering))
            finish(token, cancelled ? .cancelled(projectID) : .failed(projectID, error))
            return
        }
        if Task.isCancelled {
            finish(token, .cancelled(projectID))
            return
        }

        update(token, stage: .finalizing, seconds: total, total: total, projectID: projectID)
        let output: OutputRecord
        do {
            output = try await projects.commitOutput(FinishedOutput(
                file: jobURL, fileName: "RENN.mp4", recipeRevision: plan.recipeRevision, policy: plan.policy,
                duration: rendered, hasAudio: plan.includesAudio), to: projectID)
        } catch {
            await telemetry.record(.exportFailed(stage: .finalizing))
            finish(token, .failed(projectID, .writerFailed))
            return
        }
        await telemetry.record(.exportCompleted(
            tier: plan.policy.tier, quality: .init(plan.policy.dimensions), elapsedSecondsBucket: .bucket(rendered)))
        // Successful export records the Look actually exported (01 P04).
        if let lookID = plan.recipe.lookID {
            await lookPreferences.recordUse(of: lookID)
        }
        // Verified local result exists: attempt Photos automatically (01 P09).
        await save(output, of: projectID, token: token)
    }

    private func save(_ output: OutputRecord, of projectID: ProjectID, token: UUID) async {
        guard token == jobToken, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        state = .savingToPhotos(projectID, output)
        try? await projects.updatePhotosSave(.inFlight, localIdentifier: nil, output: output.id, project: projectID)
        let outcome = await photos.saveVideo(at: await projects.fileURL(output.relativePath))
        var saved = output
        switch outcome {
        case .saved(let identifier):
            saved.photosSave = .saved
            saved.photosLocalIdentifier = identifier
        case .permissionDenied:
            saved.photosSave = .permissionDenied
        case .failed:
            saved.photosSave = .failed
        }
        try? await projects.updatePhotosSave(
            saved.photosSave, localIdentifier: saved.photosLocalIdentifier, output: output.id, project: projectID)
        await telemetry.record(.photosSaveFinished(saved: saved.photosSave == .saved))
        guard token == jobToken else { return }
        state = saved.photosSave == .saved ? .completed(projectID, saved) : .saveFailed(projectID, saved)
    }

    private func update(_ token: UUID, stage: ExportProgress.Stage, seconds: Double, total: Double, projectID: ProjectID) {
        guard token == jobToken else { return }
        progress.update(stage: stage, renderedSeconds: seconds, totalSeconds: total)
        switch stage {
        case .preparing, .rendering:
            guard case .rendering = state, stage == .rendering else {
                if stage == .rendering { state = .rendering(projectID, progress: progress.fraction) }
                return
            }
            state = .rendering(projectID, progress: progress.fraction)
        case .finalizing, .validating:
            state = .finalizing(projectID)
        }
    }

    private func finish(_ token: UUID, _ newState: JobState) {
        guard token == jobToken else { return }
        state = newState
    }
}

extension TelemetryEvent.QualityBucket {
    init(_ dimensions: PixelDimensions) {
        switch dimensions.shortEdge {
        case ..<720: self = .sd
        case ..<1080: self = .hd720
        case ..<2160: self = .hd1080
        default: self = .uhd4k
        }
    }
}
