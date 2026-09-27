import Observation
import RENNDomain

/// Projects tab: the VHS shelf collection (01 P03, 02 D08). Rename/delete with explicit
/// confirmation and the insertion motion arrive with M01/M05.
@MainActor
@Observable
public final class ProjectsViewModel {
    public private(set) var projects: [ProjectSummary] = []
    public private(set) var hasLoaded = false

    private let projectStore: any ProjectStoring
    private let onOpenProject: @MainActor (ProjectID) -> Void
    private let onCreateFirst: @MainActor () -> Void

    public init(
        projectStore: any ProjectStoring,
        onOpenProject: @escaping @MainActor (ProjectID) -> Void,
        onCreateFirst: @escaping @MainActor () -> Void
    ) {
        self.projectStore = projectStore
        self.onOpenProject = onOpenProject
        self.onCreateFirst = onCreateFirst
    }

    public var isEmpty: Bool { hasLoaded && projects.isEmpty }

    public func observe() async {
        for await updated in await projectStore.projectUpdates() {
            projects = updated
            hasLoaded = true
        }
    }

    public func open(_ id: ProjectID) { onOpenProject(id) }
    public func createFirstTape() { onCreateFirst() }

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
