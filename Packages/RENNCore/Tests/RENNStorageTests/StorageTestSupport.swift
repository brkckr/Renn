import Foundation
import RENNDomain
import RENNFakes
@testable import RENNStorage

/// A throwaway directory tree: `root` (owned store), `tmp` (staging/jobs) and `external`
/// (stands in for user files outside app-owned storage, e.g. an original in Photos).
struct Sandbox {
    let base: URL
    let root: URL
    let tmp: URL
    let external: URL
    /// The current "launch". Use `relaunchedStore()` to simulate the next process.
    let store: FileSystemOwnedFileStore

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("renn-tests-\(UUID().uuidString)")
        root = base.appendingPathComponent("AppSupport/RENN")
        tmp = base.appendingPathComponent("tmp/RENN")
        external = base.appendingPathComponent("External")
        for url in [root, tmp, external] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        store = FileSystemOwnedFileStore(rootURL: root, temporaryURL: tmp)
    }

    func relaunchedStore() -> FileSystemOwnedFileStore {
        FileSystemOwnedFileStore(rootURL: root, temporaryURL: tmp)
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }

    /// Writes deterministic bytes of `size` into a new staged file.
    func stage(_ size: Int = 3000, seed: UInt8 = 7) async throws -> URL {
        let url = try await store.makeStagingURL(fileExtension: "mov")
        try Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31) ^ seed }).write(to: url)
        return url
    }

    func externalFile(_ name: String = "original.mov") throws -> URL {
        let url = external.appendingPathComponent(name)
        try Data("user original".utf8).write(to: url)
        return url
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func projectDirectory(_ id: ProjectID) -> URL {
        root.appendingPathComponent("Projects").appendingPathComponent(id.rawValue.uuidString)
    }
}

let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

func sampleMetadata(audio: Bool = true, ownsAudio: Bool = true) -> SourceMetadata {
    SourceMetadata(
        duration: .seconds(12),
        displayDimensions: try! PixelDimensions(width: 1080, height: 1920),
        frameRate: .fps(30),
        hasUsableAudio: audio,
        ownsSharedAudio: ownsAudio)
}

func sampleRecipe(dual: Bool = false) -> Recipe {
    Recipe.initial(
        look: StaticLookCatalogProvider.developmentCatalog.looks.first,
        creationStamp: try! StampDate(year: 2026, month: 9, day: 27),
        seed: 42,
        dualLayout: dual ? DualCameraLayout() : nil)
}

func draft(_ sources: [StagedSource], name: String = "Tape", mode: ProjectSummary.SourceMode = .imported) -> NewProjectDraft {
    NewProjectDraft(
        createdAt: fixedDate, name: try! ProjectName(name), sourceMode: mode,
        sources: sources, recipe: sampleRecipe(dual: mode == .dualCamera))
}

/// Wraps the real file store and injects failures at chosen steps.
actor FaultyFileStore: OwnedFileStoring {
    let base: FileSystemOwnedFileStore
    var failAdoptionAfter: Int?
    var failRemoval = false
    private var adoptions = 0

    init(_ base: FileSystemOwnedFileStore) { self.base = base }

    func setFailAdoptionAfter(_ count: Int?) { failAdoptionAfter = count }
    func setFailRemoval(_ value: Bool) { failRemoval = value }

    struct Injected: Error {}

    func fingerprint(ofStagedFile stagedFile: URL) async throws -> FileFingerprint {
        try await base.fingerprint(ofStagedFile: stagedFile)
    }

    func adoptStagedFile(_ stagedFile: URL, as path: OwnedRelativePath) async throws -> FileFingerprint {
        if let limit = failAdoptionAfter, adoptions >= limit { throw Injected() }
        adoptions += 1
        return try await base.adoptStagedFile(stagedFile, as: path)
    }

    func fileExists(_ path: OwnedRelativePath) async -> Bool { await base.fileExists(path) }
    func fingerprint(of path: OwnedRelativePath) async throws -> FileFingerprint { try await base.fingerprint(of: path) }

    func removeProjectDirectory(_ id: ProjectID) async throws {
        if failRemoval { throw Injected() }
        try await base.removeProjectDirectory(id)
    }

    func projectDirectoryIDs() async throws -> [ProjectID] { try await base.projectDirectoryIDs() }
    func cleanTemporaryArea() async throws { try await base.cleanTemporaryArea() }
    func makeStagingURL(fileExtension: String) async throws -> URL { try await base.makeStagingURL(fileExtension: fileExtension) }
    func makeJobURL(fileExtension: String) async throws -> URL { try await base.makeJobURL(fileExtension: fileExtension) }
    func removeFile(_ path: OwnedRelativePath) async throws { try await base.removeFile(path) }
    func url(for path: OwnedRelativePath) async -> URL { await base.url(for: path) }
}

/// Metadata wrapper that can fail updates, simulating a crash before a flag is persisted.
actor FlakyMetadata: ProjectMetadataStoring {
    let base: InMemoryProjectMetadataStore
    var failUpdates = false

    init(_ base: InMemoryProjectMetadataStore) { self.base = base }
    func setFailUpdates(_ value: Bool) { failUpdates = value }
    struct Injected: Error {}

    func allRecords() async throws -> [ProjectRecord] { try await base.allRecords() }
    func record(_ id: ProjectID) async throws -> ProjectRecord? { try await base.record(id) }
    func insert(_ record: ProjectRecord) async throws { try await base.insert(record) }
    func update(_ record: ProjectRecord) async throws {
        if failUpdates { throw Injected() }
        try await base.update(record)
    }
    func remove(_ id: ProjectID) async throws { try await base.remove(id) }
}
