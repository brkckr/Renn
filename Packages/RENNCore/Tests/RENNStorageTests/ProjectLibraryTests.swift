import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNStorage

@Suite("Project library: commit, rename, delete, leases (01 P03, 05 V07/V08)")
struct ProjectLibraryTests {
    @Test func createMovesStagedSourceAndCommitsReady() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        let staged = try await sandbox.stage()
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: staged, fileName: "source.mov", metadata: sampleMetadata()),
        ]))
        #expect(record.readiness == .ready)
        #expect(record.recipeRevision == 1)
        #expect(record.sources.first?.relativePath.string == "Projects/\(record.id.rawValue.uuidString)/sources/source.mov")
        #expect(!sandbox.exists(staged), "Staged file is moved, not copied")
        #expect(sandbox.exists(sandbox.projectDirectory(record.id).appendingPathComponent("sources/source.mov")))
        #expect(try await library.projects().map(\.id) == [record.id])
    }

    @Test func externalFilesAreNeverAdopted() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        let original = try sandbox.externalFile()
        await #expect(throws: ProjectStoreError.sourceAdoptionFailed) {
            try await library.createProject(draft([
                StagedSource(role: .primary, stagedFile: original, fileName: "source.mov", metadata: sampleMetadata()),
            ]))
        }
        #expect(sandbox.exists(original), "The user's original is untouched")
        #expect(try await library.projects().isEmpty)
    }

    @Test func traversalFileNamesAreRejected() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        let staged = try await sandbox.stage()
        for name in ["../escape.mov", "..", "a/b.mov", "", "/abs.mov"] {
            await #expect(throws: ProjectStoreError.sourceAdoptionFailed) {
                try await library.createProject(draft([
                    StagedSource(role: .primary, stagedFile: staged, fileName: name, metadata: sampleMetadata()),
                ]))
            }
        }
        #expect(sandbox.exists(staged))
    }

    @Test func deleteRemovesOnlyOwnedDataOfThatProject() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        let original = try sandbox.externalFile()
        let first = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ], name: "First"))
        let second = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(seed: 9), fileName: "b.mov", metadata: sampleMetadata()),
        ], name: "Second"))

        try await library.delete(first.id)

        #expect(!sandbox.exists(sandbox.projectDirectory(first.id)))
        #expect(sandbox.exists(sandbox.projectDirectory(second.id).appendingPathComponent("sources/b.mov")))
        #expect(sandbox.exists(original), "Deletion never touches files outside app-owned storage")
        #expect(try await library.projects().map(\.id) == [second.id])
        await #expect(throws: ProjectStoreError.notFound(first.id)) { try await library.project(first.id) }
    }

    @Test func dualCameraDeletionRemovesBothSources() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        let record = try await library.createProject(draft([
            StagedSource(role: .rearCamera, stagedFile: try await sandbox.stage(), fileName: "rear.mov", metadata: sampleMetadata()),
            StagedSource(role: .frontCamera, stagedFile: try await sandbox.stage(seed: 3), fileName: "front.mov",
                         metadata: sampleMetadata(ownsAudio: false)),
        ], mode: .dualCamera))
        #expect(record.sources.count == 2)
        try await library.delete(record.id)
        #expect(!sandbox.exists(sandbox.projectDirectory(record.id)))
    }

    @Test func leasedProjectCannotBeDeletedUntilReleased() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))
        let lease = try await library.acquireLease(record.id, purpose: .export)
        await #expect(throws: ProjectStoreError.leased(record.id)) { try await library.delete(record.id) }
        #expect(sandbox.exists(sandbox.projectDirectory(record.id)))
        await library.releaseLease(lease)
        try await library.delete(record.id)
        #expect(try await library.projects().isEmpty)
    }

    @Test func renamePersistsAcrossRelaunchWithoutTouchingFiles() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let metadata = InMemoryProjectMetadataStore()
        let library = ProjectLibrary(metadata: metadata, files: sandbox.store)
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))
        let before = try await sandbox.store.fingerprint(of: record.sources[0].relativePath)
        try await library.rename(record.id, to: ProjectName("Summer · İzmir"))

        let relaunched = ProjectLibrary(metadata: metadata, files: sandbox.relaunchedStore())
        let reloaded = try await relaunched.project(record.id)
        #expect(reloaded.name.value == "Summer · İzmir")
        #expect(reloaded.recipe == record.recipe, "Rename never changes the recipe")
        #expect(try await sandbox.store.fingerprint(of: record.sources[0].relativePath) == before)
    }

    @Test func recipeRevisionsRejectStaleAndInvalidWrites() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))
        var recipe = record.recipe
        recipe.audioMuted = true
        let updated = try await library.updateRecipe(record.id, expectedRevision: 1, recipe: recipe)
        #expect(updated.recipeRevision == 2)
        #expect(updated.recipe.audioMuted)

        await #expect(throws: ProjectStoreError.staleRevision(expected: 1, actual: 2)) {
            try await library.updateRecipe(record.id, expectedRevision: 1, recipe: recipe)
        }
        var invalid = recipe
        invalid.lookParameters["grain"] = .nan
        await #expect(throws: ProjectStoreError.invalidRecipe) {
            try await library.updateRecipe(record.id, expectedRevision: 2, recipe: invalid)
        }
    }

    @Test func concurrentWritersAtTheSameRevisionCommitOnce() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))
        let successes = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<10 {
                group.addTask {
                    var recipe = record.recipe
                    recipe.beat = BeatSettings(isEnabled: true, intensity: Double(index) / 10)
                    return (try? await library.updateRecipe(record.id, expectedRevision: 1, recipe: recipe)) != nil
                }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(successes == 1)
        #expect(try await library.project(record.id).recipeRevision == 2)
    }

    @Test func updatesStreamReflectsCreateRenameDelete() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        var iterator = await library.projectUpdates().makeAsyncIterator()
        #expect(await iterator.next() == [])
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))
        #expect(await iterator.next()?.map(\.id) == [record.id])
        try await library.rename(record.id, to: ProjectName("Renamed"))
        #expect(await iterator.next()?.first?.name.value == "Renamed")
        try await library.delete(record.id)
        // Deletion publishes "hidden while deleting" and then the final list.
        var last = await iterator.next()
        if last?.isEmpty == false { last = await iterator.next() }
        #expect(last == [])
    }
}

@Suite("Project library: interrupted commits and reconciliation (05 V08)")
struct ReconciliationTests {
    @Test func crashBeforeSourcesMovedMarksInterrupted() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let metadata = InMemoryProjectMetadataStore()
        let path = try ProjectFileLayout.file("a.mov", in: .sources, of: ProjectID())
        let id = ProjectFileLayout.projectID(of: path)!
        // The process died after inserting `.preparing` metadata, before moving the source.
        try await metadata.insert(ProjectRecord(
            id: id, createdAt: fixedDate, updatedAt: fixedDate, name: try ProjectName("Tape"),
            sourceMode: .camera, readiness: .preparing,
            sources: [SourceReference(role: .primary, relativePath: path,
                                      fingerprint: FileFingerprint(byteCount: 10, sampleHash: 1),
                                      metadata: sampleMetadata())],
            recipeRevision: 1, recipe: sampleRecipe()))

        let library = ProjectLibrary(metadata: metadata, files: sandbox.store)
        let report = await library.reconcile()
        #expect(report.markedInterrupted == 1)
        #expect(try await library.project(id).readiness == .interrupted)
        #expect(try await library.projects().map(\.readiness) == [.interrupted], "Shown truthfully, not hidden")
    }

    @Test func crashAfterSourcesMovedCompletesCommitOnRelaunch() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let metadata = InMemoryProjectMetadataStore()
        let flaky = FlakyMetadata(metadata)
        await flaky.setFailUpdates(true) // the final ".ready" write never lands
        let library = ProjectLibrary(metadata: flaky, files: sandbox.store)
        let staged = try await sandbox.stage()
        await #expect(throws: ProjectStoreError.storageFailure) {
            try await library.createProject(draft([
                StagedSource(role: .primary, stagedFile: staged, fileName: "a.mov", metadata: sampleMetadata()),
            ]))
        }
        let stored = try #require(await metadata.records.values.first)
        #expect(stored.readiness == .preparing)

        let relaunched = ProjectLibrary(metadata: metadata, files: sandbox.relaunchedStore())
        let report = await relaunched.reconcile()
        #expect(report.completedCommits == 1)
        #expect(try await relaunched.project(stored.id).readiness == .ready)
    }

    @Test func tamperedSourceDuringCrashWindowIsNotMarkedReady() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let metadata = InMemoryProjectMetadataStore()
        let flaky = FlakyMetadata(metadata)
        await flaky.setFailUpdates(true)
        let library = ProjectLibrary(metadata: flaky, files: sandbox.store)
        _ = try? await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))
        let stored = try #require(await metadata.records.values.first)
        // Truncate the adopted file: existence alone must not count as success.
        let fileURL = await sandbox.store.url(for: stored.sources[0].relativePath)
        try Data([1, 2, 3]).write(to: fileURL)

        let relaunched = ProjectLibrary(metadata: metadata, files: sandbox.relaunchedStore())
        #expect(await relaunched.reconcile().markedInterrupted == 1)
        #expect(try await relaunched.project(stored.id).readiness == .interrupted)
    }

    @Test func partialDualAdoptionKeepsMediaAndMarksInterrupted() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let files = FaultyFileStore(sandbox.store)
        await files.setFailAdoptionAfter(1)
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: files)
        let rear = try await sandbox.stage()
        let front = try await sandbox.stage(seed: 5)
        await #expect(throws: ProjectStoreError.sourceAdoptionFailed) {
            try await library.createProject(draft([
                StagedSource(role: .rearCamera, stagedFile: rear, fileName: "rear.mov", metadata: sampleMetadata()),
                StagedSource(role: .frontCamera, stagedFile: front, fileName: "front.mov",
                             metadata: sampleMetadata(ownsAudio: false)),
            ], mode: .dualCamera))
        }
        let listed = try await library.projects()
        #expect(listed.map(\.readiness) == [.interrupted])
        let projectDirectory = sandbox.projectDirectory(listed[0].id)
        #expect(sandbox.exists(projectDirectory.appendingPathComponent("sources/rear.mov")), "Recorded media is preserved")
        #expect(sandbox.exists(front), "The unadopted source stays in staging")
    }

    @Test func interruptedDeletionFinishesOnRelaunch() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let metadata = InMemoryProjectMetadataStore()
        let files = FaultyFileStore(sandbox.store)
        let library = ProjectLibrary(metadata: metadata, files: files)
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))
        await files.setFailRemoval(true)
        await #expect(throws: ProjectStoreError.storageFailure) { try await library.delete(record.id) }
        #expect(try await library.projects().isEmpty, "A project being deleted is hidden")
        #expect(await metadata.records[record.id]?.readiness == .deleting)

        let relaunched = ProjectLibrary(metadata: metadata, files: sandbox.relaunchedStore())
        #expect(await relaunched.reconcile().completedDeletions == 1)
        #expect(await metadata.records.isEmpty)
        #expect(!sandbox.exists(sandbox.projectDirectory(record.id)))
    }

    @Test func orphanDirectoriesAreRemovedButUnknownEntriesAreKept() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let orphan = sandbox.projectDirectory(ProjectID())
        try FileManager.default.createDirectory(at: orphan.appendingPathComponent("sources"), withIntermediateDirectories: true)
        let unknown = sandbox.root.appendingPathComponent("Projects/not-a-project")
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)

        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: sandbox.store)
        #expect(await library.reconcile().removedOrphanDirectories == 1)
        #expect(!sandbox.exists(orphan))
        #expect(sandbox.exists(unknown))
    }

    @Test func unreadableMetadataDeletesNothing() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let metadata = InMemoryProjectMetadataStore()
        let library = ProjectLibrary(metadata: metadata, files: sandbox.store)
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))

        // Next launch: the database cannot be read (e.g. written by a newer app version).
        await metadata.setFailAllReads(true)
        let relaunched = ProjectLibrary(metadata: metadata, files: sandbox.relaunchedStore())
        let report = await relaunched.reconcile()
        #expect(report.metadataUnavailable)
        #expect(report.removedOrphanDirectories == 0)
        #expect(sandbox.exists(sandbox.projectDirectory(record.id)), "Never wipe data after a metadata failure")
        await #expect(throws: ProjectStoreError.metadataUnavailable) { try await relaunched.projects() }
    }

    @Test func externallyMissingSourceIsFlaggedAndRecovers() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let metadata = InMemoryProjectMetadataStore()
        let library = ProjectLibrary(metadata: metadata, files: sandbox.store)
        let record = try await library.createProject(draft([
            StagedSource(role: .primary, stagedFile: try await sandbox.stage(), fileName: "a.mov", metadata: sampleMetadata()),
        ]))
        let fileURL = await sandbox.store.url(for: record.sources[0].relativePath)
        let parked = sandbox.external.appendingPathComponent("parked.mov")
        try FileManager.default.moveItem(at: fileURL, to: parked)

        let second = ProjectLibrary(metadata: metadata, files: sandbox.relaunchedStore())
        #expect(await second.reconcile().markedSourceMissing == 1)
        #expect(try await second.project(record.id).readiness == .sourceMissing)

        try FileManager.default.moveItem(at: parked, to: fileURL)
        let third = ProjectLibrary(metadata: metadata, files: sandbox.relaunchedStore())
        #expect(await third.reconcile().recoveredSources == 1)
        #expect(try await third.project(record.id).readiness == .ready)
    }

    @Test func temporaryPartialsAreCleanedAtLaunch() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let partial = sandbox.store.jobsURL.appendingPathComponent("job.partial")
        try FileManager.default.createDirectory(at: sandbox.store.jobsURL, withIntermediateDirectories: true)
        try Data([0]).write(to: partial)
        let staged = try await sandbox.stage()
        let original = try sandbox.externalFile()

        let nextLaunch = sandbox.relaunchedStore()
        let library = ProjectLibrary(metadata: InMemoryProjectMetadataStore(), files: nextLaunch)
        let stagedThisLaunch = try await nextLaunch.makeStagingURL(fileExtension: "mov")
        try Data([1, 2, 3]).write(to: stagedThisLaunch)
        _ = await library.reconcile()
        #expect(!sandbox.exists(partial))
        #expect(!sandbox.exists(staged), "Earlier launch's staging is swept")
        #expect(sandbox.exists(stagedThisLaunch), "This launch's staging survives reconciliation")
        #expect(sandbox.exists(original))
    }
}

@Suite("Owned file store boundaries")
struct FileStoreTests {
    @Test func fingerprintDetectsChangesInSampledRegions() throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let url = sandbox.external.appendingPathComponent("big.bin")
        let size = FileSystemOwnedFileStore.sampleSize * 3
        var bytes = Data(repeating: 0xAB, count: size)
        try bytes.write(to: url)
        let original = try FileSystemOwnedFileStore.fingerprint(url)
        #expect(original.byteCount == Int64(size))

        bytes[size - 1] = 0x00 // last byte lies in the tail sample
        try bytes.write(to: url)
        #expect(try FileSystemOwnedFileStore.fingerprint(url) != original)
    }

    @Test func removalCannotEscapeTheRoot() async throws {
        let sandbox = try Sandbox(); defer { sandbox.remove() }
        let original = try sandbox.externalFile()
        #expect(throws: (any Error).self) { try OwnedRelativePath(["Projects", "..", "..", "External"]) }
        // A project ID always maps inside Projects/, whatever it is.
        try await sandbox.store.removeProjectDirectory(ProjectID())
        #expect(sandbox.exists(original))
    }

    @Test func relativePathValidation() throws {
        #expect(try OwnedRelativePath(string: "Projects/ABC/sources/a.mov").components.count == 4)
        for bad in ["", "/Projects", "Projects//a", "Projects/../x", "Projects/./x", "Projects/a b", "Projects/ş.mov"] {
            #expect(throws: OwnedRelativePath.ValidationError.self) { try OwnedRelativePath(string: bad) }
        }
    }
}
