import Observation
import RENNDomain

/// Catalog tab: All, Favorites and real nonempty families; no paid badges or locks (01 P04).
@MainActor
@Observable
public final class LooksViewModel {
    public enum Filter: Hashable, Sendable {
        case all
        case favorites
        case family(String)
    }

    public enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        case failed
    }

    public private(set) var loadState: LoadState = .loading
    public private(set) var catalog: LookCatalog?
    public private(set) var preferences = LookPreferences()
    public var filter: Filter = .all

    private let lookCatalog: any LookCatalogProviding
    private let lookPreferencesStore: any LookPreferencesStoring
    private let onInspect: @MainActor (LookID) -> Void

    public init(
        lookCatalog: any LookCatalogProviding,
        lookPreferencesStore: any LookPreferencesStoring,
        onInspect: @escaping @MainActor (LookID) -> Void
    ) {
        self.lookCatalog = lookCatalog
        self.lookPreferencesStore = lookPreferencesStore
        self.onInspect = onInspect
    }

    public var filters: [Filter] {
        [.all, .favorites] + (catalog?.families ?? []).map(Filter.family)
    }

    public var visibleLooks: [LookDefinition] {
        let looks = catalog?.looks ?? []
        switch filter {
        case .all: return looks
        case .favorites: return looks.filter { preferences.isFavorite($0.id) }
        case .family(let family): return looks.filter { $0.family == family }
        }
    }

    public var isDevelopmentCatalog: Bool { catalog.map { !$0.isLaunchReady } ?? false }
    public var lookCount: Int { catalog?.looks.count ?? 0 }

    public func isFavorite(_ id: LookID) -> Bool { preferences.isFavorite(id) }

    public func observe() async {
        await load()
        for await updated in await lookPreferencesStore.updates() {
            preferences = updated
        }
    }

    public func retry() async {
        await load()
    }

    public func inspect(_ id: LookID) { onInspect(id) }

    private func load() async {
        loadState = .loading
        do {
            catalog = try await lookCatalog.catalog()
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }
}

/// Compact inspection sheet: example, name/description, Favorite and Create with this Look.
/// Browsing never changes existing projects (02 D05).
@MainActor
@Observable
public final class LookInspectionViewModel {
    public private(set) var look: LookDefinition?
    public private(set) var isFavorite = false
    public private(set) var loadFailed = false

    public let lookID: LookID
    private let lookCatalog: any LookCatalogProviding
    private let lookPreferencesStore: any LookPreferencesStoring
    private let onCreate: @MainActor (LookID) -> Void
    private let onClose: @MainActor () -> Void

    public init(
        lookID: LookID,
        lookCatalog: any LookCatalogProviding,
        lookPreferencesStore: any LookPreferencesStoring,
        onCreate: @escaping @MainActor (LookID) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.lookID = lookID
        self.lookCatalog = lookCatalog
        self.lookPreferencesStore = lookPreferencesStore
        self.onCreate = onCreate
        self.onClose = onClose
    }

    public func load() async {
        do {
            look = try await lookCatalog.catalog().look(lookID)
            loadFailed = look == nil
        } catch {
            loadFailed = true
        }
        isFavorite = await lookPreferencesStore.load().isFavorite(lookID)
    }

    public func toggleFavorite() async {
        let newValue = !isFavorite
        isFavorite = newValue
        await lookPreferencesStore.setFavorite(lookID, newValue)
    }

    public func createWithThisLook() {
        guard look != nil else { return }
        onCreate(lookID)
    }

    public func close() { onClose() }
}
