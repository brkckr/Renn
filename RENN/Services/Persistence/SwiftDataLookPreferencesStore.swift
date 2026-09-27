import Foundation
import SwiftData
import RENNDomain

/// Favorites and last-four-distinct Looks persisted in SwiftData (05 V07).
@ModelActor
actor SwiftDataLookPreferencesStore: LookPreferencesStoring {
    private static let rowKey = "default"
    private var broadcaster = StreamBroadcaster<LookPreferences>()

    func load() -> LookPreferences {
        guard let row = try? row() else { return LookPreferences() }
        return LookPreferences(favoriteIDs: Set(row.favoriteIDs.map { LookID($0) }), recentIDs: row.recentIDs.map { LookID($0) })
    }

    func setFavorite(_ lookID: LookID, _ isFavorite: Bool) {
        var preferences = load()
        preferences.setFavorite(lookID, isFavorite)
        persist(preferences)
    }

    func recordUse(of lookID: LookID) {
        var preferences = load()
        preferences.recordUse(of: lookID)
        persist(preferences)
    }

    func updates() -> AsyncStream<LookPreferences> {
        broadcaster.makeStream(initial: load()) { [weak self] token in
            Task { await self?.removeSubscriber(token) }
        }
    }

    private func persist(_ preferences: LookPreferences) {
        let favorites = preferences.favoriteIDs.map(\.rawValue).sorted()
        let recents = preferences.recentIDs.map(\.rawValue)
        if let existing = try? row() {
            existing.favoriteIDs = favorites
            existing.recentIDs = recents
        } else {
            modelContext.insert(LookPreferencesEntity(key: Self.rowKey, favoriteIDs: favorites, recentIDs: recents))
        }
        // Favorites/recents are not critical: a failed save keeps the in-session state.
        try? modelContext.save()
        broadcaster.yield(preferences)
    }

    private func row() throws -> LookPreferencesEntity? {
        let key = Self.rowKey
        var descriptor = FetchDescriptor<LookPreferencesEntity>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func removeSubscriber(_ token: UUID) {
        broadcaster.remove(token)
    }
}
