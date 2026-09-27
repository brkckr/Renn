import Foundation
import RENNDomain

/// Summary of one launch-time reconciliation pass (05 V08).
public struct ReconciliationReport: Sendable, Equatable {
    public var completedDeletions = 0
    public var completedCommits = 0
    public var markedInterrupted = 0
    public var markedSourceMissing = 0
    public var recoveredSources = 0
    public var removedOrphanDirectories = 0
    public var metadataUnavailable = false

    public init() {}
}

/// Project authority: coordinates the metadata store and the owned file store.
///
/// Database and files are not one atomic transaction (05 V08), so every operation is ordered
/// so that a crash at any point leaves a state that `reconcile()` can finish or mark truthfully:
/// - create: insert `.preparing` record → move staged sources in → verify fingerprints → `.ready`.
///   A failure after files moved keeps the media and marks the project `.interrupted`.
/// - delete: refuse while leased → mark `.deleting` → remove owned files → remove metadata.
/// - reconcile (runs once, before the first operation): clean earlier launches' temporary files, finish
///   deletions, complete or interrupt `.preparing` projects, flag missing sources and remove
///   orphan project directories, but only when the metadata could actually be read.
///
/// All mutations are serialized, including across suspension points.
public actor ProjectLibrary: ProjectStoring {
    private let metadata: any ProjectMetadataStoring
    private let files: any OwnedFileStoring
    private let now: @Sendable () -> Date

    private var reconciliationReport: ReconciliationReport?
    private var summaries: [ProjectSummary] = []
    private var metadataAvailable = true
    private var leases: [ProjectID: Set<UUID>] = [:]
    private var broadcaster = StreamBroadcaster<[ProjectSummary]>()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        metadata: any ProjectMetadataStoring,
        files: any OwnedFileStoring,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.metadata = metadata
        self.files = files
        self.now = now
    }

    // MARK: Reconciliation

    /// Runs reconciliation if it has not run yet and returns its report.
    @discardableResult
    public func reconcile() async -> ReconciliationReport {
        await acquire()
        defer { release() }
        return await reconcileLocked()
    }

    private func reconcileLocked() async -> ReconciliationReport {
        if let reconciliationReport { return reconciliationReport }
        var report = ReconciliationReport()
        try? await files.cleanTemporaryArea()

        let records: [ProjectRecord]
        do {
            records = try await metadata.allRecords()
        } catch {
            // Never delete anything when metadata cannot be read (05 V08).
            report.metadataUnavailable = true
            metadataAvailable = false
            reconciliationReport = report
            return report
        }

        for var record in records {
            // A save that was in flight when the process died is uncertain, never re-sent (05 V09).
            if record.outputs.contains(where: { $0.photosSave == .inFlight }) {
                for index in record.outputs.indices where record.outputs[index].photosSave == .inFlight {
                    record.outputs[index].photosSave = .uncertain
                }
                try? await metadata.update(record)
            }
            switch record.readiness {
            case .deleting:
                if (try? await files.removeProjectDirectory(record.id)) != nil,
                   (try? await metadata.remove(record.id)) != nil {
                    report.completedDeletions += 1
                }
            case .preparing:
                let valid = await sourcesMatchFingerprints(record)
                record.readiness = valid ? .ready : .interrupted
                if (try? await metadata.update(record)) != nil {
                    if valid { report.completedCommits += 1 } else { report.markedInterrupted += 1 }
                }
            case .ready:
                if await !allSourcesExist(record) {
                    record.readiness = .sourceMissing
                    if (try? await metadata.update(record)) != nil { report.markedSourceMissing += 1 }
                }
            case .sourceMissing:
                if await sourcesMatchFingerprints(record) {
                    record.readiness = .ready
                    if (try? await metadata.update(record)) != nil { report.recoveredSources += 1 }
                }
            case .interrupted:
                break
            }
        }

        let knownIDs = Set(records.map(\.id))
        if let directoryIDs = try? await files.projectDirectoryIDs() {
            for orphan in directoryIDs where !knownIDs.contains(orphan) {
                if (try? await files.removeProjectDirectory(orphan)) != nil {
                    report.removedOrphanDirectories += 1
                }
            }
        }

        await refreshSummaries()
        reconciliationReport = report
        return report
    }

    // MARK: ProjectStoring

    public func projects() async throws(ProjectStoreError) -> [ProjectSummary] {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        guard metadataAvailable else { throw .metadataUnavailable }
        return summaries
    }

    public func projectUpdates() async -> AsyncStream<[ProjectSummary]> {
        await acquire()
        _ = await reconcileLocked()
        release()
        // No suspension between reading the cache and registering: no update can be missed.
        return broadcaster.makeStream(initial: summaries) { [weak self] token in
            Task { await self?.removeSubscriber(token) }
        }
    }

    public func project(_ id: ProjectID) async throws(ProjectStoreError) -> ProjectRecord {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        let record = try await loadRecord(id)
        guard record.readiness != .deleting else { throw .notFound(id) }
        return record
    }

    public func createProject(_ draft: NewProjectDraft) async throws(ProjectStoreError) -> ProjectRecord {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        guard metadataAvailable else { throw .metadataUnavailable }
        guard !draft.sources.isEmpty, (try? draft.recipe.validate()) != nil else { throw .invalidRecipe }

        // Resolve paths and fingerprint staged files before anything is committed.
        var references: [SourceReference] = []
        for source in draft.sources {
            guard let path = try? ProjectFileLayout.file(source.fileName, in: .sources, of: draft.id),
                  let fingerprint = try? await files.fingerprint(ofStagedFile: source.stagedFile)
            else { throw .sourceAdoptionFailed }
            references.append(SourceReference(
                role: source.role, relativePath: path, fingerprint: fingerprint, metadata: source.metadata))
        }
        guard Set(references.map(\.relativePath)).count == references.count else { throw .sourceAdoptionFailed }

        let existing = try? await metadata.record(draft.id)
        if existing != nil { throw .storageFailure }
        var record = ProjectRecord(
            id: draft.id, createdAt: draft.createdAt, updatedAt: draft.createdAt, name: draft.name,
            sourceMode: draft.sourceMode, readiness: .preparing, sources: references,
            recipeRevision: 1, recipe: draft.recipe)
        do {
            try await metadata.insert(record)
        } catch {
            throw .storageFailure
        }

        // Move sources in. From here on media is never deleted on failure (05 V02/V08).
        var adoptedAll = true
        for (source, reference) in zip(draft.sources, references) {
            let adopted = try? await files.adoptStagedFile(source.stagedFile, as: reference.relativePath)
            if adopted != reference.fingerprint {
                adoptedAll = false
                break
            }
        }

        record.readiness = adoptedAll ? .ready : .interrupted
        record.updatedAt = now()
        let committed = (try? await metadata.update(record)) != nil
        await refreshSummaries()
        guard adoptedAll else { throw .sourceAdoptionFailed }
        // If the final flag failed to persist, reconciliation completes it on next launch.
        guard committed else { throw .storageFailure }
        return record
    }

    public func updateRecipe(
        _ id: ProjectID, expectedRevision: Int, recipe: Recipe
    ) async throws(ProjectStoreError) -> ProjectRecord {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        var record = try await loadRecord(id)
        guard record.readiness == .ready else { throw .unavailable(id) }
        guard record.recipeRevision == expectedRevision else {
            throw .staleRevision(expected: expectedRevision, actual: record.recipeRevision)
        }
        guard (try? recipe.validate()) != nil else { throw .invalidRecipe }
        record.recipe = recipe
        record.recipeRevision += 1
        record.updatedAt = now()
        try await save(record)
        return record
    }

    public func rename(_ id: ProjectID, to name: ProjectName) async throws(ProjectStoreError) {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        var record = try await loadRecord(id)
        guard record.readiness != .deleting else { throw .notFound(id) }
        record.name = name
        record.updatedAt = now()
        try await save(record)
    }

    public func delete(_ id: ProjectID) async throws(ProjectStoreError) {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        var record = try await loadRecord(id)
        guard leases[id]?.isEmpty ?? true else { throw .leased(id) }
        if record.readiness != .deleting {
            record.readiness = .deleting
            record.updatedAt = now()
            try await save(record)
        }
        do {
            try await files.removeProjectDirectory(id)
            try await metadata.remove(id)
        } catch {
            // Stays `.deleting` (hidden); reconciliation resumes the removal on next launch.
            await refreshSummaries()
            throw .storageFailure
        }
        await refreshSummaries()
    }

    public func acquireLease(
        _ id: ProjectID, purpose: ProjectLease.Purpose
    ) async throws(ProjectStoreError) -> ProjectLease {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        let record = try await loadRecord(id)
        guard record.readiness != .deleting else { throw .notFound(id) }
        let lease = ProjectLease(projectID: id, purpose: purpose)
        leases[id, default: []].insert(lease.id)
        return lease
    }

    public func releaseLease(_ lease: ProjectLease) async {
        leases[lease.projectID]?.remove(lease.id)
        if leases[lease.projectID]?.isEmpty == true {
            leases[lease.projectID] = nil
        }
    }

    public func makeJobFileURL(fileExtension: String) async throws(ProjectStoreError) -> URL {
        do {
            return try await files.makeJobURL(fileExtension: fileExtension)
        } catch {
            throw .storageFailure
        }
    }

    public func commitOutput(_ output: FinishedOutput, to id: ProjectID) async throws(ProjectStoreError) -> OutputRecord {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        var record = try await loadRecord(id)
        guard record.readiness == .ready else { throw .unavailable(id) }
        let outputID = OutputID()
        guard let path = try? ProjectFileLayout.file(
            "\(outputID.rawValue.uuidString)-\(output.fileName)", in: .outputs, of: id)
        else { throw .storageFailure }
        let fingerprint: FileFingerprint
        do {
            fingerprint = try await files.adoptStagedFile(output.file, as: path)
        } catch {
            throw .storageFailure
        }
        let committed = OutputRecord(
            id: outputID, relativePath: path, fingerprint: fingerprint, recipeRevision: output.recipeRevision,
            policy: output.policy, duration: output.duration, hasAudio: output.hasAudio, completedAt: now())
        // Keep older outputs only while a share/playback lease may be using them (05 V08).
        let obsolete = leases[id]?.isEmpty ?? true ? record.outputs : []
        record.outputs = (leases[id]?.isEmpty ?? true ? [] : record.outputs) + [committed]
        record.lastOutputID = outputID
        record.updatedAt = now()
        try await save(record)
        for old in obsolete {
            try? await files.removeFile(old.relativePath)
        }
        return committed
    }

    public func updatePhotosSave(
        _ state: PhotosSaveState, localIdentifier: String?, output outputID: OutputID, project id: ProjectID
    ) async throws(ProjectStoreError) {
        await acquire()
        defer { release() }
        _ = await reconcileLocked()
        var record = try await loadRecord(id)
        guard let index = record.outputs.firstIndex(where: { $0.id == outputID }) else { throw .notFound(id) }
        record.outputs[index].photosSave = state
        if let localIdentifier { record.outputs[index].photosLocalIdentifier = localIdentifier }
        try await save(record)
    }

    public func fileURL(_ path: OwnedRelativePath) async -> URL {
        await files.url(for: path)
    }

    // MARK: Internals

    private func loadRecord(_ id: ProjectID) async throws(ProjectStoreError) -> ProjectRecord {
        guard metadataAvailable else { throw .metadataUnavailable }
        let loaded: ProjectRecord?
        do {
            loaded = try await metadata.record(id)
        } catch {
            throw .storageFailure
        }
        guard let loaded else { throw .notFound(id) }
        return loaded
    }

    private func save(_ record: ProjectRecord) async throws(ProjectStoreError) {
        do {
            try await metadata.update(record)
        } catch {
            throw .storageFailure
        }
        await refreshSummaries()
    }

    private func refreshSummaries() async {
        guard let records = try? await metadata.allRecords() else { return }
        summaries = records
            .filter(\.isListed)
            .map(\.summary)
            .sorted { $0.createdAt > $1.createdAt }
        broadcaster.yield(summaries)
    }

    private func allSourcesExist(_ record: ProjectRecord) async -> Bool {
        for source in record.sources where await !files.fileExists(source.relativePath) {
            return false
        }
        return !record.sources.isEmpty
    }

    private func sourcesMatchFingerprints(_ record: ProjectRecord) async -> Bool {
        guard !record.sources.isEmpty else { return false }
        for source in record.sources {
            guard let actual = try? await files.fingerprint(of: source.relativePath),
                  actual == source.fingerprint
            else { return false }
        }
        return true
    }

    private func removeSubscriber(_ token: UUID) {
        broadcaster.remove(token)
    }

    // Serializes operations across suspension points (actor reentrancy guard).
    private func acquire() async {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
