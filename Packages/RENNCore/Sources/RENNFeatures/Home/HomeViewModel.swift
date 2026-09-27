import Foundation
import Observation
import RENNDomain

/// Home: recommended Look, last four distinct Looks and up to three recent projects (01 P03).
@MainActor
@Observable
public final class HomeViewModel {
    public static let maximumRecentProjects = 3

    public enum CatalogState: Equatable, Sendable {
        case loading
        case loaded
        case failed
    }

    public private(set) var catalogState: CatalogState = .loading
    public private(set) var recommendedLook: LookDefinition?
    public private(set) var recentLooks: [LookDefinition] = []
    public private(set) var recentProjects: [ProjectSummary] = []
    public private(set) var hasLoadedProjects = false
    public private(set) var projectsFailed = false

    private var catalog: LookCatalog?
    private var lookPreferences = LookPreferences()

    private let projectStore: any ProjectStoring
    private let lookCatalog: any LookCatalogProviding
    private let lookPreferencesStore: any LookPreferencesStoring
    private let posters: (any PosterProviding)?
    private let onSeeAll: @MainActor () -> Void
    private let onInspectLook: @MainActor (LookID) -> Void
    private let onOpenProject: @MainActor (ProjectID) -> Void

    public init(
        projectStore: any ProjectStoring,
        lookCatalog: any LookCatalogProviding,
        lookPreferencesStore: any LookPreferencesStoring,
        posters: (any PosterProviding)? = nil,
        onSeeAll: @escaping @MainActor () -> Void,
        onInspectLook: @escaping @MainActor (LookID) -> Void,
        onOpenProject: @escaping @MainActor (ProjectID) -> Void
    ) {
        self.projectStore = projectStore
        self.lookCatalog = lookCatalog
        self.lookPreferencesStore = lookPreferencesStore
        self.posters = posters
        self.onSeeAll = onSeeAll
        self.onInspectLook = onInspectLook
        self.onOpenProject = onOpenProject
    }

    /// First use shows a create prompt without fake history (02 D04).
    public var showsFirstUsePrompt: Bool { hasLoadedProjects && recentProjects.isEmpty }
    public var isCatalogDevelopmentFixture: Bool { catalog?.isDevelopmentFixture ?? false }

    /// Runs for the lifetime of the view's task and stops when it is cancelled.
    public func observe() async {
        await loadCatalog()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeProjects() }
            group.addTask { await self.observeLookPreferences() }
        }
    }

    public func seeAll() { onSeeAll() }
    public func inspect(_ lookID: LookID) { onInspectLook(lookID) }
    public func open(_ projectID: ProjectID) { onOpenProject(projectID) }

    /// Same case/cover/name model as Projects (02 D08).
    public func poster(for id: ProjectID) async -> Data? {
        await posters?.posterJPEG(for: id)
    }

    private func loadCatalog() async {
        do {
            let loaded = try await lookCatalog.catalog()
            catalog = loaded
            recommendedLook = loaded.recommendedLook
            catalogState = .loaded
            resolveRecentLooks()
        } catch {
            catalogState = .failed
        }
    }

    private func observeProjects() async {
        for await projects in await projectStore.projectUpdates() {
            recentProjects = Array(projects.prefix(Self.maximumRecentProjects))
            hasLoadedProjects = true
        }
    }

    private func observeLookPreferences() async {
        for await preferences in await lookPreferencesStore.updates() {
            lookPreferences = preferences
            resolveRecentLooks()
        }
    }

    /// Unknown or retired IDs are skipped rather than shown as broken entries.
    private func resolveRecentLooks() {
        guard let catalog else { return }
        recentLooks = lookPreferences.recentIDs.compactMap(catalog.look)
    }
}
