/// On-device space used by RENN (02 D09 storage controls). Projects are the user's media and are
/// only removed by deleting projects; the cache holds regenerable data (posters) and can be cleared
/// at any time without changing a project.
public struct StorageUsage: Sendable, Equatable {
    public let projectBytes: Int64
    public let cacheBytes: Int64

    public init(projectBytes: Int64, cacheBytes: Int64) {
        self.projectBytes = projectBytes
        self.cacheBytes = cacheBytes
    }
}

public protocol StorageUsageProviding: Sendable {
    func usage() async -> StorageUsage
    /// Removes regenerable cached data only; never project sources or outputs.
    func clearCache() async
}
