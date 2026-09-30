import Foundation
import Observation
import RENNDomain

/// Projects tab: the VHS shelf collection (01 P03, 02 D08) with rename and confirmed delete.
/// Select mode (owner-approved 2026-09-30): tapping a case toggles it, Delete removes every
/// selected tape after one confirmation and Rename works on exactly one.
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
    /// Projects awaiting explicit deletion confirmation (01 P03); one confirmation covers them all.
    public private(set) var pendingDeletion: [ProjectSummary] = []
    /// Project whose rename sheet is open.
    public private(set) var renaming: ProjectSummary?
    public private(set) var isSelecting = false
    public private(set) var selection: Set<ProjectID> = []
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
            // Tapes removed elsewhere leave the selection and close their rename sheet.
            let ids = Set(updated.map(\.id))
            selection.formIntersection(ids)
            if let renaming, !ids.contains(renaming.id) { self.renaming = nil }
            if updated.isEmpty { isSelecting = false }
        }
    }

    public func open(_ id: ProjectID) { onOpenProject(id) }

    /// The project's own processed frame for its case print, or nil (empty shell).
    public func poster(for id: ProjectID) async -> Data? {
        await posters?.posterJPEG(for: id)
    }
    public func createFirstTape() { onCreateFirst() }

    // MARK: Select mode

    /// Selected tapes in shelf order.
    public var selectedProjects: [ProjectSummary] { projects.filter { selection.contains($0.id) } }
    public var canRenameSelection: Bool { selection.count == 1 }

    public func beginSelection() {
        guard !projects.isEmpty else { return }
        isSelecting = true
    }

    public func endSelection() {
        isSelecting = false
        selection = []
    }

    public func toggleSelection(_ id: ProjectID) {
        guard isSelecting, projects.contains(where: { $0.id == id }) else { return }
        if selection.remove(id) == nil { selection.insert(id) }
    }

    public func renameSelection() {
        guard canRenameSelection, let id = selection.first else { return }
        requestRename(id)
    }

    public func requestDeleteSelection() {
        guard !isDeleting, !selection.isEmpty else { return }
        actionError = nil
        pendingDeletion = selectedProjects
    }

    // MARK: Rename

    public func requestRename(_ id: ProjectID) {
        renaming = projects.first { $0.id == id }
    }

    public func dismissRename() {
        renaming = nil
    }

    /// The trimmed name, or why it cannot be used (80 characters, single line, not empty).
    public static func validatedName(_ text: String) throws(RenameError) -> ProjectName {
        do {
            return try ProjectName(text)
        } catch {
            switch error {
            case .empty: throw .empty
            case .multiline: throw .multiline
            case .tooLong(let maximum): throw .tooLong(maximum: maximum)
            }
        }
    }

    /// Validates and renames. Names are labels only; nothing is re-rendered (05 V07).
    public func rename(_ id: ProjectID, to text: String) async throws(RenameError) {
        let name = try Self.validatedName(text)
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
            // A rename from select mode completes it.
            if isSelecting, selection == [id] { endSelection() }
            return nil
        } catch {
            return error
        }
    }

    public func requestDelete(_ id: ProjectID) {
        guard !isDeleting, let project = projects.first(where: { $0.id == id }) else { return }
        actionError = nil
        pendingDeletion = [project]
    }

    public func cancelDelete() {
        guard !isDeleting else { return }
        pendingDeletion = []
    }

    /// Deletes the confirmed projects once, even if confirmation is tapped repeatedly. A tape
    /// that cannot be deleted stays (and stays selected); the others are still removed.
    public func confirmDelete() async {
        guard !pendingDeletion.isEmpty, !isDeleting else { return }
        let targets = pendingDeletion
        isDeleting = true
        defer {
            isDeleting = false
            pendingDeletion = []
        }
        var failure: ActionError?
        for project in targets {
            do {
                try await projectStore.delete(project.id)
                selection.remove(project.id)
            } catch .leased {
                failure = .projectInUse
            } catch {
                failure = failure ?? .deleteFailed
            }
        }
        actionError = failure
        if isSelecting, failure == nil { endSelection() }
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
