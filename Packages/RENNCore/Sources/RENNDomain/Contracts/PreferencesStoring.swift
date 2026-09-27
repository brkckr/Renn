/// Small synchronous app preferences, read at launch before the first frame to pick the
/// correct language and route. Main-actor isolated because only UI orchestration uses it.
@MainActor
public protocol AppPreferencesStoring: AnyObject, Sendable {
    func load() -> AppPreferences
    func save(_ preferences: AppPreferences)
}

/// Favorites and recent Looks. SwiftData-backed in M01 (05 V07 LookPreferences record).
public protocol LookPreferencesStoring: Sendable {
    func load() async -> LookPreferences
    func setFavorite(_ lookID: LookID, _ isFavorite: Bool) async
    /// Only for valid history events (01 P04).
    func recordUse(of lookID: LookID) async
    func updates() async -> AsyncStream<LookPreferences>
}

/// Loads and validates the bundled Look catalog manifest.
public protocol LookCatalogProviding: Sendable {
    func catalog() async throws -> LookCatalog
}
