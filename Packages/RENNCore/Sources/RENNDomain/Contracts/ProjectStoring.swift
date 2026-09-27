/// Project metadata authority (04 A03/A04). The live adapter is SwiftData (M01); tests and
/// previews use `InMemoryProjectStore`. Only immutable snapshots cross this boundary.
public protocol ProjectStoring: Sendable {
    /// Current projects, newest first.
    func projects() async throws -> [ProjectSummary]
    /// Emits the current list immediately, then after every change. Ends when the
    /// consumer's task is cancelled.
    func projectUpdates() async -> AsyncStream<[ProjectSummary]>
    /// Rename never re-renders (05 V07).
    func rename(_ id: ProjectID, to name: ProjectName) async throws(ProjectStoreError)
    /// Removes only app-owned project data; never touches Photos (05 V08).
    func delete(_ id: ProjectID) async throws(ProjectStoreError)
}

public enum ProjectStoreError: Error, Equatable, Sendable {
    case notFound(ProjectID)
    /// Active capture/export/share lease; deletion must wait or be explained.
    case leased(ProjectID)
    case storageFailure
}
