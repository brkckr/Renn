import Foundation
import SwiftData
import Testing
import RENNDomain
import RENNStorage
@testable import RENN

/// SwiftData adapter checks (05 V07/V08). Run on the iOS Simulator; the ordering and
/// recovery logic itself is covered on any platform in Packages/RENNCore/Tests/RENNStorageTests.
@Suite("SwiftData persistence", .serialized)
struct PersistenceTests {
    private let stamp = try! StampDate(year: 2026, month: 9, day: 27)

    private func makeRecord(_ name: String = "Tape") throws -> ProjectRecord {
        let id = ProjectID()
        return ProjectRecord(
            id: id, createdAt: Date(timeIntervalSince1970: 1_790_000_000), updatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            name: try ProjectName(name), sourceMode: .imported, readiness: .ready,
            sources: [SourceReference(
                role: .primary, relativePath: try ProjectFileLayout.file("a.mov", in: .sources, of: id),
                fingerprint: FileFingerprint(byteCount: 3, sampleHash: 4),
                metadata: SourceMetadata(
                    duration: .seconds(5), displayDimensions: try PixelDimensions(width: 1080, height: 1920),
                    frameRate: .ntsc29_97, hasUsableAudio: true, ownsSharedAudio: true))],
            recipeRevision: 1,
            recipe: Recipe.initial(look: nil, creationStamp: stamp, seed: 99, dualLayout: DualCameraLayout()))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("renn-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func metadataRoundTrip() async throws {
        let store = SwiftDataProjectMetadataStore(modelContainer: try PersistenceController.makeInMemoryContainer())
        var record = try makeRecord()
        try await store.insert(record)
        #expect(try await store.record(record.id) == record)
        await #expect(throws: (any Error).self) { try await store.insert(record) }

        record.name = try ProjectName("Renamed · Şile")
        record.recipeRevision = 2
        record.readiness = .interrupted
        try await store.update(record)
        #expect(try await store.allRecords() == [record])

        try await store.remove(record.id)
        #expect(try await store.record(record.id) == nil)
        try await store.remove(record.id) // idempotent
    }

    @Test func projectsSurviveRelaunchOnDisk() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("RENN.store")
        let record = try makeRecord("Before relaunch")

        do {
            let store = SwiftDataProjectMetadataStore(modelContainer: try PersistenceController.makeContainer(storeURL: storeURL))
            try await store.insert(record)
        }
        let reopened = SwiftDataProjectMetadataStore(modelContainer: try PersistenceController.makeContainer(storeURL: storeURL))
        #expect(try await reopened.record(record.id) == record)
    }

    @Test func corruptRowMakesMetadataUnavailableAndDeletesNothing() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let store = SwiftDataProjectMetadataStore(modelContainer: container)
        let record = try makeRecord()
        try await store.insert(record)
        try await MainActor.run {
            let context = container.mainContext
            let entity = try #require(try context.fetch(FetchDescriptor<ProjectEntity>()).first)
            entity.recipeJSON = Data("not json".utf8)
            try context.save()
        }
        await #expect(throws: (any Error).self) { try await store.allRecords() }

        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let projectDirectory = root.appendingPathComponent("Projects/\(record.id.rawValue.uuidString)/sources")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let library = ProjectLibrary(
            metadata: store,
            files: FileSystemOwnedFileStore(rootURL: root, temporaryURL: root.appendingPathComponent("tmp")))
        #expect(await library.reconcile().metadataUnavailable)
        #expect(FileManager.default.fileExists(atPath: projectDirectory.path))
    }

    @Test func libraryOverSwiftDataCreatesRenamesAndDeletes() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = FileSystemOwnedFileStore(rootURL: root.appendingPathComponent("RENN"), temporaryURL: root.appendingPathComponent("tmp"))
        let library = ProjectLibrary(
            metadata: SwiftDataProjectMetadataStore(modelContainer: try PersistenceController.makeInMemoryContainer()),
            files: files)
        let staged = try await files.makeStagingURL(fileExtension: "mov")
        try Data(repeating: 1, count: 4096).write(to: staged)
        let created = try await library.createProject(NewProjectDraft(
            createdAt: Date(), name: try ProjectName("Tape"), sourceMode: .imported,
            sources: [StagedSource(
                role: .primary, stagedFile: staged, fileName: "source.mov",
                metadata: SourceMetadata(
                    duration: .seconds(2), displayDimensions: try PixelDimensions(width: 720, height: 1280),
                    frameRate: .fps(30), hasUsableAudio: false, ownsSharedAudio: false))],
            recipe: Recipe.initial(look: nil, creationStamp: stamp, seed: 1)))
        #expect(created.readiness == .ready)

        try await library.rename(created.id, to: ProjectName("Renamed"))
        #expect(try await library.projects().map(\.name.value) == ["Renamed"])
        try await library.delete(created.id)
        #expect(try await library.projects().isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("RENN/Projects/\(created.id.rawValue.uuidString)").path))
    }

    @Test func lookPreferencesPersistAcrossRelaunch() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("RENN.store")
        do {
            let store = SwiftDataLookPreferencesStore(modelContainer: try PersistenceController.makeContainer(storeURL: storeURL))
            await store.setFavorite("a", true)
            for id in ["a", "b", "c", "d", "e"] { await store.recordUse(of: LookID(id)) }
        }
        let reopened = SwiftDataLookPreferencesStore(modelContainer: try PersistenceController.makeContainer(storeURL: storeURL))
        let preferences = await reopened.load()
        #expect(preferences.isFavorite("a"))
        #expect(preferences.recentIDs == ["e", "d", "c", "b"])
    }
}
