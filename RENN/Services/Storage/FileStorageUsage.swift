import Foundation
import RENNDomain

/// Measures RENN's on-disk footprint (02 D09): the owned project tree and the regenerable cache.
/// Clearing touches only the cache directory; projects are removed only by deleting projects.
struct FileStorageUsage: StorageUsageProviding {
    let projectsRoot: URL
    let cacheRoot: URL

    func usage() async -> StorageUsage {
        StorageUsage(projectBytes: Self.size(of: projectsRoot), cacheBytes: Self.size(of: cacheRoot))
    }

    func clearCache() async {
        try? FileManager.default.removeItem(at: cacheRoot)
    }

    private static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
