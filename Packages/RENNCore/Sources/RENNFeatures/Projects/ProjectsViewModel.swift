import Foundation
import Observation
import RENNDomain

/// Projects tab: the VHS shelf collection (01 P03, 02 D08) with rename and confirmed delete.
/// The insertion motion arrives with M05/M07.
@MainActor
@Observable
public final class ProjectsViewModel {
    public enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        /// The metadata store could not be opened (e.g. created by a newer app version).
        case unavailable
    }

    public enum RenameError: Error, Equatable, Sendable {
        case empty
        case tooLong(maximum: Int)
        case multiline
        case failed
    }

    public enum ActionError: Equatable, Sendable {
        /// Capture/export/share is using the project; deletion must wait (05 V08).
        case projectInUse
        case deleteFailed
    }

    public private(set) var projects: [ProjectSummary] = []
    public private(set) var loadState: LoadState = .loading
    /// Project awaiting explicit deletion confirmation (01 P03).
    public private(set) var pendingDeletion: ProjectSummary?
    public private(set) var isDeleting = false
    public private(set) var actionError: ActionError?

    private let projectStore: any ProjectStoring
    private let posters: (any PosterProviding)?
    private let onOpenProject: @MainActor (ProjectID) -> Void
    private let onCreateFirst: @MainActor () -> Void

    public init(
        projectStore: any ProjectStoring,
        posters: (any PosterProviding)? = nil,
        onOpenProject: @escaping @MainActor (ProjectID) -> Void,
        onCreateFirst: @escaping @MainActor () -> Void
    ) {
        self.posters = posters
        self.projectStore = projectStore
        self.onOpenProject = onOpenProject
        self.onCreateFirst = onCreateFirst
    }

    public var hasLoaded: Bool { loadState == .loaded }
    public var isEmpty: Bool { hasLoaded && projects.isEmpty }

    public func observe() async {
        do {
            _ = try await projectStore.projects()
        } catch .metadataUnavailable {
            loadState = .unavailable
            return
        } catch {
            // Other errors: the update stream below still reflects what is readable.
        }
        for await updated in await projectStore.projectUpdates() {
            projects = updated
            loadState = .loaded
        }
    }

    public func open(_ id: ProjectID) { onOpenProject(id) }

    /// The project's own processed frame for its case print, or nil (empty shell).
    public func poster(for id: ProjectID) async -> Data? {
        await posters?.posterJPEG(for: id)
    }
    public func createFirstTape() { onCreateFirst() }

    /// Validates and renames. Names are labels only; nothing is re-rendered (05 V07).
    public func rename(_ id: ProjectID, to text: String) async throws(RenameError) {
        let name: ProjectName
        do {
            name = try ProjectName(text)
        } catch {
            switch error {
            case .empty: throw .empty
            case .multiline: throw .multiline
            case .tooLong(let maximum): throw .tooLong(maximum: maximum)
            }
        }
        do {
            try await projectStore.rename(id, to: name)
        } catch {
            throw .failed
        }
    }

    /// Non-throwing variant for views: returns the validation/storage error, or nil on success.
    public func renameResult(_ id: ProjectID, to text: String) async -> RenameError? {
        do {
            try await rename(id, to: text)
            return nil
        } catch {
            return error
        }
    }

    public func requestDelete(_ id: ProjectID) {
        guard !isDeleting else { return }
        actionError = nil
        pendingDeletion = projects.first { $0.id == id }
    }

    public func cancelDelete() {
        guard !isDeleting else { return }
        pendingDeletion = nil
    }

    /// Deletes the confirmed project once, even if confirmation is tapped repeatedly.
    public func confirmDelete() async {
        guard let project = pendingDeletion, !isDeleting else { return }
        isDeleting = true
        defer {
            isDeleting = false
            pendingDeletion = nil
        }
        do {
            try await projectStore.delete(project.id)
        } catch .leased {
            actionError = .projectInUse
        } catch {
            actionError = .deleteFailed
        }
    }

    public func dismissError() {
        actionError = nil
    }

    /// Deterministic case-print color index by project ID, never random per redraw or tier.
    public static func caseVariant(for id: ProjectID, variantCount: Int = 4) -> Int {
        // FNV-1a over the UUID bytes: stable across launches, unlike Hashable.hashValue.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: id.rawValue.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        return Int(hash % UInt64(variantCount))
    }
}
