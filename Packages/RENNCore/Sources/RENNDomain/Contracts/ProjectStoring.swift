import Foundation

/// Project authority used by features (04 A03/A04). The live implementation is
/// `ProjectLibrary` over SwiftData metadata and an owned file store (M01); tests and
/// previews may use `InMemoryProjectStore`. Only immutable snapshots cross this boundary.
public protocol ProjectStoring: Sendable {
    /// Listed projects (not being deleted), newest first.
    func projects() async throws(ProjectStoreError) -> [ProjectSummary]
    /// Emits the current list immediately, then after every change. Ends when the
    /// consumer's task is cancelled.
    func projectUpdates() async -> AsyncStream<[ProjectSummary]>
    func project(_ id: ProjectID) async throws(ProjectStoreError) -> ProjectRecord
    /// Adopts staged sources and commits a ready project (05 V08).
    func createProject(_ draft: NewProjectDraft) async throws(ProjectStoreError) -> ProjectRecord
    /// Commits a new recipe revision. `expectedRevision` rejects stale writers.
    func updateRecipe(
        _ id: ProjectID, expectedRevision: Int, recipe: Recipe
    ) async throws(ProjectStoreError) -> ProjectRecord
    /// Rename never re-renders (05 V07).
    func rename(_ id: ProjectID, to name: ProjectName) async throws(ProjectStoreError)
    /// Removes only app-owned project data; never touches Photos (05 V08).
    func delete(_ id: ProjectID) async throws(ProjectStoreError)
    /// Capture/export/share hold a lease; leased projects cannot be deleted (05 V08).
    func acquireLease(_ id: ProjectID, purpose: ProjectLease.Purpose) async throws(ProjectStoreError) -> ProjectLease
    func releaseLease(_ lease: ProjectLease) async
    /// New unique URL for an export job's partial file, in the current launch's job area.
    func makeJobFileURL(fileExtension: String) async throws(ProjectStoreError) -> URL
    /// New unique URL in the current launch's staging area (import copies, capture takes).
    func makeStagingFileURL(fileExtension: String) async throws(ProjectStoreError) -> URL
    /// Moves a validated output into the project and makes it the latest output. A failed
    /// render never replaces the previous good result (05 V08).
    func commitOutput(_ output: FinishedOutput, to id: ProjectID) async throws(ProjectStoreError) -> OutputRecord
    func updatePhotosSave(
        _ state: PhotosSaveState, localIdentifier: String?, output: OutputID, project id: ProjectID
    ) async throws(ProjectStoreError)
    /// Absolute URL of an owned file, for playback/export/share.
    func fileURL(_ path: OwnedRelativePath) async -> URL
}

public struct ProjectLease: Sendable, Hashable {
    public enum Purpose: String, Sendable {
        case capture
        case export
        case share
        case playback
    }

    public let id: UUID
    public let projectID: ProjectID
    public let purpose: Purpose

    public init(id: UUID = UUID(), projectID: ProjectID, purpose: Purpose) {
        self.id = id
        self.projectID = projectID
        self.purpose = purpose
    }
}

public enum ProjectStoreError: Error, Equatable, Sendable {
    case notFound(ProjectID)
    /// Active capture/export/share lease; deletion must wait or be explained.
    case leased(ProjectID)
    /// Another writer committed a newer recipe revision first.
    case staleRevision(expected: Int, actual: Int)
    case invalidRecipe
    /// The project is not in a state that allows the operation (e.g. being deleted).
    case unavailable(ProjectID)
    /// A staged source could not be adopted or verified; nothing was committed.
    case sourceAdoptionFailed
    case insufficientStorage
    /// Metadata store unavailable, e.g. created by a newer app version (05 V08).
    case metadataUnavailable
    case storageFailure
}

/// Metadata authority backend (SwiftData in the app). Records are whole snapshots.
public protocol ProjectMetadataStoring: Sendable {
    func allRecords() async throws -> [ProjectRecord]
    func record(_ id: ProjectID) async throws -> ProjectRecord?
    func insert(_ record: ProjectRecord) async throws
    func update(_ record: ProjectRecord) async throws
    func remove(_ id: ProjectID) async throws
}

/// App-owned file storage (05 V07/V08). Implementations must never read, move or delete
/// anything outside their own root, except moving a staged file *into* it.
public protocol OwnedFileStoring: Sendable {
    /// Fingerprint of a file in the staging area, taken before adoption.
    func fingerprint(ofStagedFile stagedFile: URL) async throws -> FileFingerprint
    /// Atomically moves a staged file (same volume) into the store at `path`. Only files
    /// inside the store's own staging or job area are accepted. Returns the adopted fingerprint.
    func adoptStagedFile(_ stagedFile: URL, as path: OwnedRelativePath) async throws -> FileFingerprint
    func fileExists(_ path: OwnedRelativePath) async -> Bool
    func fingerprint(of path: OwnedRelativePath) async throws -> FileFingerprint
    /// Removes a project's directory with everything in it. Idempotent.
    func removeProjectDirectory(_ id: ProjectID) async throws
    /// Project directories that exist on disk, for orphan reconciliation.
    func projectDirectoryIDs() async throws -> [ProjectID]
    /// Removes staging/partial files left by earlier launches. Files of the current launch
    /// are never swept away.
    func cleanTemporaryArea() async throws
    /// New unique URL in the staging area, on the same volume as the store.
    func makeStagingURL(fileExtension: String) async throws -> URL
    /// New unique URL in the job area for partial export files.
    func makeJobURL(fileExtension: String) async throws -> URL
    /// Removes one owned file. Idempotent.
    func removeFile(_ path: OwnedRelativePath) async throws
    /// Absolute URL for playback/export of an owned file.
    func url(for path: OwnedRelativePath) async -> URL
}
