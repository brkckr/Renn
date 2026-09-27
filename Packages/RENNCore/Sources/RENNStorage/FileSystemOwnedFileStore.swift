import Foundation
import RENNDomain

/// FileManager-backed owned storage (05 V07/V08).
///
/// Layout under `rootURL` (Application Support/RENN in the app):
/// `Projects/<UUID>/sources/`, `Projects/<UUID>/outputs/`.
/// Under `temporaryURL` (same volume): `Staging/<launch>/` for adopted-soon files and
/// `Jobs/<launch>/` for partials. Each process uses its own launch directory, so cleanup of
/// earlier launches never depends on file timestamps.
///
/// Safety: every resolved path is checked to stay inside the root; staged files are only
/// accepted from this store's own staging directory, so nothing outside app-owned storage
/// can be moved or deleted through it.
public struct FileSystemOwnedFileStore: OwnedFileStoring {
    public let rootURL: URL
    public let temporaryURL: URL
    /// Identifies this process's staging/jobs directories. Create one store per launch.
    public let launchID: UUID

    public enum StoreError: Error, Equatable, Sendable {
        case outsideOwnedStorage
        case destinationExists
        case missingFile
        case invalidFileExtension
    }

    /// Bytes hashed at the start and at the end of a file for its fingerprint.
    static let sampleSize = 1 << 20

    public init(rootURL: URL, temporaryURL: URL, launchID: UUID = UUID()) {
        self.rootURL = rootURL.standardizedFileURL
        self.temporaryURL = temporaryURL.standardizedFileURL
        self.launchID = launchID
    }

    var stagingRootURL: URL { temporaryURL.appendingPathComponent("Staging", isDirectory: true) }
    var jobsRootURL: URL { temporaryURL.appendingPathComponent("Jobs", isDirectory: true) }
    public var stagingURL: URL { stagingRootURL.appendingPathComponent(launchID.uuidString, isDirectory: true) }
    public var jobsURL: URL { jobsRootURL.appendingPathComponent(launchID.uuidString, isDirectory: true) }
    var projectsURL: URL { rootURL.appendingPathComponent(ProjectFileLayout.projectsDirectory, isDirectory: true) }

    // MARK: OwnedFileStoring

    public func fingerprint(ofStagedFile stagedFile: URL) async throws -> FileFingerprint {
        let url = try requireInside(stagingURL, stagedFile)
        return try Self.fingerprint(url)
    }

    public func adoptStagedFile(_ stagedFile: URL, as path: OwnedRelativePath) async throws -> FileFingerprint {
        let source: URL
        if let staged = try? requireInside(stagingURL, stagedFile) {
            source = staged
        } else {
            source = try requireInside(jobsURL, stagedFile)
        }
        let destination = try resolve(path)
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path) else { throw StoreError.missingFile }
        guard !manager.fileExists(atPath: destination.path) else { throw StoreError.destinationExists }
        try ensureProjectsDirectory()
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Same-volume rename: atomic, no copy of large media.
        try manager.moveItem(at: source, to: destination)
        return try Self.fingerprint(destination)
    }

    public func fileExists(_ path: OwnedRelativePath) async -> Bool {
        guard let url = try? resolve(path) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func fingerprint(of path: OwnedRelativePath) async throws -> FileFingerprint {
        try Self.fingerprint(try resolve(path))
    }

    public func removeProjectDirectory(_ id: ProjectID) async throws {
        let directory = try resolve(ProjectFileLayout.projectDirectory(id))
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    public func projectDirectoryIDs() async throws -> [ProjectID] {
        guard FileManager.default.fileExists(atPath: projectsURL.path) else { return [] }
        // Unknown entries (non-UUID names) are ignored, never deleted.
        return try FileManager.default.contentsOfDirectory(atPath: projectsURL.path)
            .compactMap { UUID(uuidString: $0) }
            .map(ProjectID.init)
    }

    public func cleanTemporaryArea() async throws {
        let manager = FileManager.default
        for directory in [stagingRootURL, jobsRootURL] where manager.fileExists(atPath: directory.path) {
            for name in try manager.contentsOfDirectory(atPath: directory.path) where name != launchID.uuidString {
                try manager.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    public func makeStagingURL(fileExtension: String) async throws -> URL {
        guard !fileExtension.isEmpty, fileExtension.count <= 8,
              fileExtension.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) })
        else { throw StoreError.invalidFileExtension }
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        return stagingURL.appendingPathComponent("\(UUID().uuidString).\(fileExtension)", isDirectory: false)
    }

    public func makeJobURL(fileExtension: String) async throws -> URL {
        guard !fileExtension.isEmpty, fileExtension.count <= 8,
              fileExtension.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) })
        else { throw StoreError.invalidFileExtension }
        try FileManager.default.createDirectory(at: jobsURL, withIntermediateDirectories: true)
        return jobsURL.appendingPathComponent("\(UUID().uuidString).\(fileExtension)", isDirectory: false)
    }

    public func removeFile(_ path: OwnedRelativePath) async throws {
        let url = try resolve(path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func url(for path: OwnedRelativePath) async -> URL {
        // OwnedRelativePath already rejects traversal; resolving cannot escape the root.
        (try? resolve(path)) ?? rootURL
    }

    // MARK: Helpers

    func resolve(_ path: OwnedRelativePath) throws -> URL {
        var url = rootURL
        for component in path.components {
            url.appendPathComponent(component)
        }
        return try requireInside(rootURL, url)
    }

    private func requireInside(_ base: URL, _ candidate: URL) throws -> URL {
        let standardized = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let basePath = base.standardizedFileURL.resolvingSymlinksInPath().path
        guard standardized.path.hasPrefix(basePath + "/") else { throw StoreError.outsideOwnedStorage }
        return standardized
    }

    private func ensureProjectsDirectory() throws {
        guard !FileManager.default.fileExists(atPath: projectsURL.path) else { return }
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        #if os(iOS) || os(macOS)
        // Baseline: large app-owned media is excluded from device backup (05 V08).
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = projectsURL
        try? mutableURL.setResourceValues(values)
        #endif
    }

    /// Size plus FNV-1a over the first and last `sampleSize` bytes.
    static func fingerprint(_ url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ data: Data) {
            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        mix(try handle.read(upToCount: sampleSize) ?? Data())
        if size > Int64(sampleSize) {
            let tailStart = UInt64(max(Int64(sampleSize), size - Int64(sampleSize)))
            try handle.seek(toOffset: tailStart)
            mix(try handle.readToEnd() ?? Data())
        }
        return FileFingerprint(byteCount: size, sampleHash: hash)
    }
}
