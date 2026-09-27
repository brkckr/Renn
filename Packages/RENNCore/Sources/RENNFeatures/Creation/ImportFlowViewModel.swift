import Foundation
import Observation
import RENNDomain

/// Import flow (01 P02/P08, 05 V06): picked video → staged + inspected → Free 30 s gate →
/// project committed → preview. No automatic trim, no trim editor, no full-library access.
@MainActor
@Observable
public final class ImportFlowViewModel {
    public enum State: Equatable, Sendable {
        /// Waiting for the system picker.
        case picking
        case preparing
        /// Free source over 30 seconds: offer Pro or another source.
        case requiresPro(sourceDuration: RationalTime)
        case creatingProject
        case failed(Failure)
        case finished(ProjectID)
    }

    public enum Failure: Equatable, Sendable {
        case unreadable
        case noVideo
        case unsupported
        case insufficientStorage
        case couldNotSave
    }

    public private(set) var state: State = .picking

    private var prepared: PreparedImport?
    private var isWorking = false
    private let lookID: LookID?
    private let importer: any VideoImporting
    private let projects: any ProjectStoring
    private let access: any AccessStateProviding
    private let lookCatalog: any LookCatalogProviding
    private let lookPreferences: any LookPreferencesStoring
    private let telemetry: any TelemetryRecording
    private let makeName: @MainActor (Date) -> ProjectName
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private let onShowPaywall: @MainActor () -> Void
    private let onFinished: @MainActor (ProjectID) -> Void
    private let onClose: @MainActor () -> Void

    public init(
        lookID: LookID?,
        importer: any VideoImporting,
        projects: any ProjectStoring,
        access: any AccessStateProviding,
        lookCatalog: any LookCatalogProviding,
        lookPreferences: any LookPreferencesStoring,
        telemetry: any TelemetryRecording,
        makeName: @escaping @MainActor (Date) -> ProjectName,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current,
        onShowPaywall: @escaping @MainActor () -> Void,
        onFinished: @escaping @MainActor (ProjectID) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.lookID = lookID
        self.importer = importer
        self.projects = projects
        self.access = access
        self.lookCatalog = lookCatalog
        self.lookPreferences = lookPreferences
        self.telemetry = telemetry
        self.makeName = makeName
        self.now = now
        self.timeZone = timeZone
        self.onShowPaywall = onShowPaywall
        self.onFinished = onFinished
        self.onClose = onClose
    }

    /// Called with the file the system picker handed over. Duplicate calls are ignored.
    public func didPick(_ pickedFile: URL) async {
        guard !isWorking, state == .picking || isRetryable else { return }
        isWorking = true
        defer { isWorking = false }
        state = .preparing
        await telemetry.record(.creationStarted(mode: .importVideo))
        do {
            let prepared = try await importer.prepare(pickedFile: pickedFile)
            self.prepared = prepared
            await evaluate(prepared)
        } catch {
            state = .failed(Self.failure(for: error))
        }
    }

    /// The picker could not hand over a file (e.g. iCloud transfer failed or was cancelled).
    public func didPickFailed() async {
        guard !isWorking else { return }
        state = .failed(.unreadable)
    }

    /// Follows access changes for the lifetime of the view (e.g. Pro granted in the paywall).
    public func observeAccess() async {
        for await _ in await access.accessUpdates() {
            await accessMayHaveChanged()
        }
    }

    /// Re-checks access after a paywall (e.g. Pro granted) and continues once.
    public func accessMayHaveChanged() async {
        guard case .requiresPro = state, let prepared, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await evaluate(prepared)
    }

    public func upgrade() {
        guard case .requiresPro = state else { return }
        onShowPaywall()
    }

    /// "Choose another video": discards the staged copy and returns to the picker.
    public func chooseAnother() async {
        await discardPrepared()
        state = .picking
    }

    public func cancel() async {
        await discardPrepared()
        onClose()
    }

    private var isRetryable: Bool {
        if case .failed = state { return true }
        return false
    }

    private func evaluate(_ prepared: PreparedImport) async {
        let currentAccess = await access.currentAccess()
        switch ImportGate.evaluate(prepared.profile, access: currentAccess) {
        case .requiresProForDuration(_, let duration):
            state = .requiresPro(sourceDuration: duration)
        case .accept:
            await createProject(from: prepared)
        }
    }

    private func createProject(from prepared: PreparedImport) async {
        state = .creatingProject
        let createdAt = now()
        let catalog = try? await lookCatalog.catalog()
        let look = lookID.flatMap { catalog?.look($0) } ?? catalog?.recommendedLook
        guard let stamp = try? StampDate(date: createdAt, timeZone: timeZone) else {
            state = .failed(.couldNotSave)
            return
        }
        let draft = NewProjectDraft(
            createdAt: createdAt,
            name: makeName(createdAt),
            sourceMode: .imported,
            sources: [StagedSource(
                role: .primary,
                stagedFile: prepared.stagedFile,
                fileName: "source.\(prepared.fileExtension)",
                metadata: SourceMetadata(
                    duration: prepared.profile.duration,
                    displayDimensions: prepared.profile.displayDimensions,
                    frameRate: prepared.profile.frameRate,
                    hasUsableAudio: prepared.profile.hasUsableAudio,
                    ownsSharedAudio: prepared.profile.hasUsableAudio,
                    isHDR: prepared.isHDR))],
            recipe: Recipe.initial(look: look, creationStamp: stamp, seed: UInt64.random(in: .min ... .max)))
        do {
            let record = try await projects.createProject(draft)
            self.prepared = nil
            // Successful creation is a valid Look history event (01 P04).
            if let lookID = record.recipe.lookID {
                await lookPreferences.recordUse(of: lookID)
            }
            await telemetry.record(.sourceReady(mode: .importVideo, duration: .bucket(prepared.profile.duration)))
            state = .finished(record.id)
            onFinished(record.id)
        } catch .insufficientStorage {
            state = .failed(.insufficientStorage)
        } catch {
            state = .failed(.couldNotSave)
        }
    }

    private func discardPrepared() async {
        if let prepared {
            await importer.discard(prepared)
            self.prepared = nil
        }
    }

    private static func failure(for error: MediaPreparationFailure) -> Failure {
        switch error {
        case .unreadable, .cancelled: .unreadable
        case .noVideoTrack: .noVideo
        case .unsupportedFormat: .unsupported
        case .insufficientStorage: .insufficientStorage
        }
    }
}

extension TelemetryEvent.DurationBucket {
    public static func bucket(_ duration: RationalTime) -> Self {
        switch duration.approximateSeconds {
        case ..<15.001: .upTo15s
        case ..<30.001: .upTo30s
        case ..<60.001: .upTo60s
        case ..<180.001: .upTo3m
        case ..<600.001: .upTo10m
        default: .over10m
        }
    }
}
