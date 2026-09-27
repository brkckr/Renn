import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("Export coordinator (01 P09, 05 V09)")
struct ExportCoordinatorTests {
    private struct Harness {
        let coordinator: ExportCoordinator
        let store: InMemoryProjectStore
        let renderer: FakeExportRenderer
        let photos: FakePhotosSaver
        let preferences: InMemoryLookPreferencesStore
        let projectID: ProjectID
    }

    private func harness(
        seconds: Int64 = 12,
        access: AccessState = .notConfigured,
        renderer: FakeExportRenderer = FakeExportRenderer(),
        photos: FakePhotosSaver = FakePhotosSaver()
    ) async throws -> Harness {
        let store = InMemoryProjectStore()
        let record = try await store.createProject(NewProjectDraft(
            createdAt: Date(timeIntervalSince1970: 1_790_000_000), name: try ProjectName("Tape"), sourceMode: .imported,
            sources: [StagedSource(
                role: .primary, stagedFile: URL(fileURLWithPath: "/staged.mov"), fileName: "source.mov",
                metadata: SourceMetadata(
                    duration: .seconds(seconds), displayDimensions: try PixelDimensions(width: 1080, height: 1920),
                    frameRate: .fps(60), hasUsableAudio: true, ownsSharedAudio: true))],
            recipe: Recipe.initial(
                look: StaticLookCatalogProvider.developmentCatalog.looks.first,
                creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 1)))
        let preferences = InMemoryLookPreferencesStore()
        let coordinator = ExportCoordinator(
            projects: store, access: FakePurchaseService(access: access), renderer: renderer, photos: photos,
            lookPreferences: preferences, telemetry: RecordingTelemetry())
        return Harness(
            coordinator: coordinator, store: store, renderer: renderer, photos: photos,
            preferences: preferences, projectID: record.id)
    }

    private func waitForTerminal(_ coordinator: ExportCoordinator) async -> Bool {
        await eventually(timeout: .seconds(3)) { !coordinator.isBusy && coordinator.state != .idle }
    }

    @Test func summaryReflectsFreePolicy() async throws {
        let h = try await harness()
        guard case .ready(let summary) = await h.coordinator.summary(for: h.projectID) else {
            Issue.record("Expected summary"); return
        }
        #expect(summary.policy.dimensions == (try PixelDimensions(width: 720, height: 1280)))
        #expect(summary.policy.frameRate == .fps(30))
        #expect(summary.policy.requiresWatermark)
        #expect(summary.includesAudio)
        #expect(!summary.isLongOrHighQuality)
    }

    @Test func freeOverThirtySecondsRequiresProBeforeAnyJob() async throws {
        let h = try await harness(seconds: 45)
        #expect(await h.coordinator.summary(for: h.projectID) == .requiresPro)
        let proHarness = try await harness(seconds: 45, access: AccessState(level: .pro, provenance: .developmentFake))
        guard case .ready(let summary) = await proHarness.coordinator.summary(for: proHarness.projectID) else {
            Issue.record("Pro has no duration cap"); return
        }
        #expect(summary.policy.frameRate == .fps(60))
        #expect(!summary.policy.requiresWatermark)
        #expect(summary.policy.dimensions == (try PixelDimensions(width: 1080, height: 1920)))
    }

    @Test func successfulExportCommitsThenSavesToPhotos() async throws {
        let h = try await harness()
        #expect(h.coordinator.start(h.projectID))
        #expect(!h.coordinator.start(h.projectID), "Double start creates one job")
        #expect(await waitForTerminal(h.coordinator))
        guard case .completed(_, let output) = h.coordinator.state else {
            Issue.record("Expected completed, got \(h.coordinator.state)"); return
        }
        #expect(output.photosSave == .saved)
        #expect(output.photosLocalIdentifier == "FAKE/L0/001")
        let record = try await h.store.project(h.projectID)
        #expect(record.latestOutput?.photosSave == .saved)
        #expect(await h.renderer.renderCount == 1)
        #expect(await h.photos.savedURLs.count == 1)
        #expect(await h.preferences.load().recentIDs == ["dev.diagnostic"], "Successful export records the exported Look")
    }

    @Test func photosFailureKeepsLocalResultAndRetriesSaveOnly() async throws {
        let photos = FakePhotosSaver(outcomes: [.permissionDenied, .saved(localIdentifier: "L2")])
        let h = try await harness(photos: photos)
        h.coordinator.start(h.projectID)
        #expect(await waitForTerminal(h.coordinator))
        guard case .saveFailed(_, let output) = h.coordinator.state else {
            Issue.record("Expected saveFailed, got \(h.coordinator.state)"); return
        }
        #expect(output.photosSave == .permissionDenied)
        #expect(try await h.store.project(h.projectID).latestOutput != nil, "Save failure is not a render failure")

        await h.coordinator.retrySave()
        guard case .completed(_, let saved) = h.coordinator.state else {
            Issue.record("Expected completed after retry"); return
        }
        #expect(saved.id == output.id, "Same output, no re-render")
        #expect(await h.renderer.renderCount == 1)
        #expect(await photos.savedURLs.count == 2)
    }

    @Test func renderFailureKeepsPreviousOutputAndRecordsNoHistory() async throws {
        let h = try await harness(renderer: FakeExportRenderer(outcome: .failure(.validationFailed)))
        h.coordinator.start(h.projectID)
        #expect(await waitForTerminal(h.coordinator))
        #expect(h.coordinator.state == .failed(h.projectID, .validationFailed))
        #expect(try await h.store.project(h.projectID).latestOutput == nil)
        #expect(await h.photos.savedURLs.isEmpty)
        #expect(await h.preferences.load().recentIDs.isEmpty, "Failed exports never create history")
    }

    @Test func cancelBeforeCommitLeavesNoOutput() async throws {
        let h = try await harness(renderer: FakeExportRenderer(holdUntilCancelled: true))
        h.coordinator.start(h.projectID)
        #expect(await eventually { if case .rendering = h.coordinator.state { true } else { false } })
        h.coordinator.cancel()
        #expect(await waitForTerminal(h.coordinator))
        #expect(h.coordinator.state == .cancelled(h.projectID))
        #expect(try await h.store.project(h.projectID).latestOutput == nil)
        h.coordinator.acknowledge()
        #expect(h.coordinator.state == .idle)
    }

    @Test func projectIsLeasedWhileExporting() async throws {
        let h = try await harness(renderer: FakeExportRenderer(holdUntilCancelled: true))
        h.coordinator.start(h.projectID)
        #expect(await eventually { if case .rendering = h.coordinator.state { true } else { false } })
        await #expect(throws: ProjectStoreError.leased(h.projectID)) { try await h.store.delete(h.projectID) }
        h.coordinator.cancel()
        #expect(await waitForTerminal(h.coordinator))
        #expect(await eventually(timeout: .seconds(2)) { true })
    }
}
