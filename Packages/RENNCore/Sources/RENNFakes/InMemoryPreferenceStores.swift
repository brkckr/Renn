import Foundation
import RENNDomain

@MainActor
public final class InMemoryAppPreferencesStore: AppPreferencesStoring {
    public private(set) var stored: AppPreferences
    public private(set) var saveCount = 0

    public init(_ initial: AppPreferences = AppPreferences()) {
        stored = initial
    }

    public func load() -> AppPreferences { stored }

    public func save(_ preferences: AppPreferences) {
        stored = preferences
        saveCount += 1
    }
}

public actor InMemoryLookPreferencesStore: LookPreferencesStoring {
    private var preferences: LookPreferences
    private var broadcaster = StreamBroadcaster<LookPreferences>()

    public init(_ initial: LookPreferences = LookPreferences()) {
        preferences = initial
    }

    public func load() async -> LookPreferences { preferences }

    public func setFavorite(_ lookID: LookID, _ isFavorite: Bool) async {
        preferences.setFavorite(lookID, isFavorite)
        broadcaster.yield(preferences)
    }

    public func recordUse(of lookID: LookID) async {
        preferences.recordUse(of: lookID)
        broadcaster.yield(preferences)
    }

    public func updates() async -> AsyncStream<LookPreferences> {
        broadcaster.makeStream(initial: preferences) { [weak self] token in
            Task { await self?.removeSubscriber(token) }
        }
    }

    private func removeSubscriber(_ token: UUID) {
        broadcaster.remove(token)
    }
}
