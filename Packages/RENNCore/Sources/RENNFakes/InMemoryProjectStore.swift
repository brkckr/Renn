import Foundation
import RENNDomain

/// In-memory `ProjectStoring` for tests, previews and pre-M01 development builds.
/// Development fixture: it persists nothing.
public actor InMemoryProjectStore: ProjectStoring {
    private var items: [ProjectID: ProjectSummary]
    private var leasedIDs: Set<ProjectID> = []
    private var broadcaster = StreamBroadcaster<[ProjectSummary]>()

    public init(projects: [ProjectSummary] = []) {
        items = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    public func projects() async throws -> [ProjectSummary] {
        sorted
    }

    public func projectUpdates() async -> AsyncStream<[ProjectSummary]> {
        broadcaster.makeStream(initial: sorted) { [weak self] token in
            Task { await self?.removeSubscriber(token) }
        }
    }

    public func rename(_ id: ProjectID, to name: ProjectName) async throws(ProjectStoreError) {
        guard var project = items[id] else { throw .notFound(id) }
        project.name = name
        project.updatedAt = Date()
        items[id] = project
        publish()
    }

    public func delete(_ id: ProjectID) async throws(ProjectStoreError) {
        guard items[id] != nil else { throw .notFound(id) }
        guard !leasedIDs.contains(id) else { throw .leased(id) }
        items[id] = nil
        publish()
    }

    // MARK: Test/development helpers

    public func insert(_ project: ProjectSummary) {
        items[project.id] = project
        publish()
    }

    public func setLeased(_ id: ProjectID, _ isLeased: Bool) {
        if isLeased { leasedIDs.insert(id) } else { leasedIDs.remove(id) }
    }

    public var subscriberCount: Int { broadcaster.subscriberCount }

    private var sorted: [ProjectSummary] {
        items.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func publish() {
        broadcaster.yield(sorted)
    }

    private func removeSubscriber(_ token: UUID) {
        broadcaster.remove(token)
    }
}
