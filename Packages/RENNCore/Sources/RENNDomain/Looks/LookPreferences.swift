/// User-managed favorites and the last four distinct Looks (01 P04, 05 V07).
public struct LookPreferences: Sendable, Equatable, Codable {
    public static let recentLimit = 4

    public private(set) var favoriteIDs: Set<LookID>
    /// Most recent first, distinct, at most four.
    public private(set) var recentIDs: [LookID]

    public init(favoriteIDs: Set<LookID> = [], recentIDs: [LookID] = []) {
        self.favoriteIDs = favoriteIDs
        var distinct: [LookID] = []
        for id in recentIDs where !distinct.contains(id) {
            distinct.append(id)
        }
        self.recentIDs = Array(distinct.prefix(LookPreferences.recentLimit))
    }

    public func isFavorite(_ id: LookID) -> Bool {
        favoriteIDs.contains(id)
    }

    public mutating func setFavorite(_ id: LookID, _ isFavorite: Bool) {
        if isFavorite {
            favoriteIDs.insert(id)
        } else {
            favoriteIDs.remove(id)
        }
    }

    /// Records a valid history event: successful source/project creation or successful export.
    /// Browsing, failed or cancelled operations must not call this (01 P04).
    public mutating func recordUse(of id: LookID) {
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        if recentIDs.count > LookPreferences.recentLimit {
            recentIDs.removeLast(recentIDs.count - LookPreferences.recentLimit)
        }
    }
}
