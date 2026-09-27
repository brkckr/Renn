import Foundation
import RENNDomain

/// In-memory `ProjectStoring` for ViewModel tests and previews. Development fixture: it
/// persists nothing and moves no files. The real ordering/recovery logic is `ProjectLibrary`.
public actor InMemoryProjectStore: ProjectStoring {
    private var records: [ProjectID: ProjectRecord]
    private var leases: [ProjectID: Set<UUID>] = [:]
    private var broadcaster = StreamBroadcaster<[ProjectSummary]>()

    public init(projects: [ProjectSummary] = []) {
        records = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, InMemoryProjectStore.record(for: $0)) })
    }

    public func projects() async throws(ProjectStoreError) -> [ProjectSummary] {
        listed
    }

    public func projectUpdates() async -> AsyncStream<[ProjectSummary]> {
        broadcaster.makeStream(initial: listed) { [weak self] token in
            Task { await self?.removeSubscriber(token) }
        }
    }

    public func project(_ id: ProjectID) async throws(ProjectStoreError) -> ProjectRecord {
        guard let record = records[id] else { throw .notFound(id) }
        return record
    }

    public func createProject(_ draft: NewProjectDraft) async throws(ProjectStoreError) -> ProjectRecord {
        var references: [SourceReference] = []
        for source in draft.sources {
            guard let path = try? ProjectFileLayout.file(source.fileName, in: .sources, of: draft.id) else {
                throw .sourceAdoptionFailed
            }
            references.append(SourceReference(
                role: source.role, relativePath: path,
                fingerprint: FileFingerprint(byteCount: 0, sampleHash: 0), metadata: source.metadata))
        }
        let record = ProjectRecord(
            id: draft.id, createdAt: draft.createdAt, updatedAt: draft.createdAt, name: draft.name,
            sourceMode: draft.sourceMode, readiness: .ready, sources: references,
            recipeRevision: 1, recipe: draft.recipe)
        records[draft.id] = record
        publish()
        return record
    }

    public func updateRecipe(
        _ id: ProjectID, expectedRevision: Int, recipe: Recipe
    ) async throws(ProjectStoreError) -> ProjectRecord {
        guard var record = records[id] else { throw .notFound(id) }
        guard record.recipeRevision == expectedRevision else {
            throw .staleRevision(expected: expectedRevision, actual: record.recipeRevision)
        }
        record.recipe = recipe
        record.recipeRevision += 1
        records[id] = record
        publish()
        return record
    }

    public func rename(_ id: ProjectID, to name: ProjectName) async throws(ProjectStoreError) {
        guard var record = records[id] else { throw .notFound(id) }
        record.name = name
        record.updatedAt = Date()
        records[id] = record
        publish()
    }

    public func delete(_ id: ProjectID) async throws(ProjectStoreError) {
        guard records[id] != nil else { throw .notFound(id) }
        guard leases[id]?.isEmpty ?? true else { throw .leased(id) }
        records[id] = nil
        publish()
    }

    public func acquireLease(
        _ id: ProjectID, purpose: ProjectLease.Purpose
    ) async throws(ProjectStoreError) -> ProjectLease {
        guard records[id] != nil else { throw .notFound(id) }
        let lease = ProjectLease(projectID: id, purpose: purpose)
        leases[id, default: []].insert(lease.id)
        return lease
    }

    public func releaseLease(_ lease: ProjectLease) async {
        leases[lease.projectID]?.remove(lease.id)
    }

    // MARK: Test/development helpers

    public func insert(_ project: ProjectSummary) {
        records[project.id] = InMemoryProjectStore.record(for: project)
        publish()
    }

    public var subscriberCount: Int { broadcaster.subscriberCount }

    private var listed: [ProjectSummary] {
        records.values.filter(\.isListed).map(\.summary).sorted { $0.createdAt > $1.createdAt }
    }

    private func publish() {
        broadcaster.yield(listed)
    }

    private func removeSubscriber(_ token: UUID) {
        broadcaster.remove(token)
    }

    static func record(for summary: ProjectSummary) -> ProjectRecord {
        ProjectRecord(
            id: summary.id, createdAt: summary.createdAt, updatedAt: summary.updatedAt, name: summary.name,
            sourceMode: summary.sourceMode, readiness: summary.readiness, sources: [],
            recipeRevision: 1,
            recipe: Recipe(
                lookID: summary.lookID, lookVersion: nil, intensity: .off, seed: 0,
                indicators: IndicatorSettings(stampDate: try! StampDate(year: 2026, month: 1, day: 1))))
    }
}

/// In-memory metadata backend for `ProjectLibrary` tests. Survives "relaunches" by being
/// shared between library instances, like the on-disk store would.
public actor InMemoryProjectMetadataStore: ProjectMetadataStoring {
    public private(set) var records: [ProjectID: ProjectRecord] = [:]
    public var failAllReads = false

    public init(records: [ProjectRecord] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    public struct Failure: Error {}

    public func allRecords() async throws -> [ProjectRecord] {
        if failAllReads { throw Failure() }
        return Array(records.values)
    }

    public func record(_ id: ProjectID) async throws -> ProjectRecord? {
        if failAllReads { throw Failure() }
        return records[id]
    }

    public func insert(_ record: ProjectRecord) async throws {
        guard records[record.id] == nil else { throw Failure() }
        records[record.id] = record
    }

    public func update(_ record: ProjectRecord) async throws {
        guard records[record.id] != nil else { throw Failure() }
        records[record.id] = record
    }

    public func remove(_ id: ProjectID) async throws {
        records[id] = nil
    }

    public func setFailAllReads(_ value: Bool) {
        failAllReads = value
    }
}
