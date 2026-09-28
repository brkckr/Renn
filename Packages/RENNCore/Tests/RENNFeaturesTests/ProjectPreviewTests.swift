import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("Project preview (01 P06/P07, 05 V08)")
struct ProjectPreviewTests {
    private func setup(seconds: Int64 = 12, access: AccessState = .notConfigured) async throws
        -> (ProjectPreviewViewModel, InMemoryProjectStore, ProjectID, CallLog) {
        let store = InMemoryProjectStore()
        var recipe = Recipe.initial(
            look: StaticLookCatalogProvider.developmentCatalog.looks.first,
            creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 3)
        recipe.beat = BeatSettings(isEnabled: true, intensity: 0.6)
        let record = try await store.createProject(NewProjectDraft(
            createdAt: Date(), name: try ProjectName("Tape"), sourceMode: .imported,
            sources: [StagedSource(
                role: .primary, stagedFile: URL(fileURLWithPath: "/s.mov"), fileName: "source.mov",
                metadata: SourceMetadata(
                    duration: .seconds(seconds), displayDimensions: try PixelDimensions(width: 1920, height: 1080),
                    frameRate: .fps(30), hasUsableAudio: true, ownsSharedAudio: true))],
            recipe: recipe))
        let purchases = FakePurchaseService(access: access)
        let exporter = ExportCoordinator(
            projects: store, access: purchases, renderer: FakeExportRenderer(), photos: FakePhotosSaver(),
            lookPreferences: InMemoryLookPreferencesStore(), telemetry: RecordingTelemetry())
        let log = CallLog()
        let viewModel = ProjectPreviewViewModel(
            projectID: record.id, projects: store, access: purchases, exporter: exporter,
            telemetry: RecordingTelemetry(), onClose: { log.record("close") }, onShowPaywall: { log.record("paywall") })
        return (viewModel, store, record.id, log)
    }

    @Test func loadsReadyProjectAndWatermarkForFree() async throws {
        let (viewModel, _, _, _) = try await setup()
        await viewModel.load()
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.showsWatermark)
        #expect(viewModel.displayDimensions == (try PixelDimensions(width: 1920, height: 1080)))
        #expect(viewModel.intensity == 0.7)
    }

    @Test func intensityAutosavesAfterDebounceAsOneRevision() async throws {
        let (viewModel, store, id, _) = try await setup()
        await viewModel.load()
        for value in stride(from: 0.1, through: 0.5, by: 0.1) { viewModel.setIntensity(value) }
        #expect(try await store.project(id).recipeRevision == 1, "Nothing written while dragging")
        #expect(await eventually { viewModel.record?.recipeRevision == 2 })
        let stored = try await store.project(id)
        #expect(stored.recipeRevision == 2)
        #expect(abs(stored.recipe.intensity.value - 0.5) < 0.0001)
    }

    @Test func muteKeepsBeatChoiceAndSavesImmediately() async throws {
        let (viewModel, store, id, _) = try await setup()
        await viewModel.load()
        viewModel.toggleMute()
        await viewModel.flush()
        let stored = try await store.project(id).recipe
        #expect(stored.audioMuted)
        #expect(stored.beat == BeatSettings(isEnabled: true, intensity: 0.6))
        #expect(!stored.beat.isEffective(audioMuted: stored.audioMuted, sourceHasUsableAudio: true))
        viewModel.toggleMute()
        await viewModel.flush()
        let unmuted = try await store.project(id).recipe
        #expect(unmuted.beat.isEffective(audioMuted: unmuted.audioMuted, sourceHasUsableAudio: true),
                "Unmute restores the previous Beat choice")
    }

    @Test func beforeAfterAndLoopNeverTouchTheRecipe() async throws {
        let (viewModel, store, id, _) = try await setup()
        await viewModel.load()
        viewModel.showsOriginal = true
        viewModel.isLooping = false
        await viewModel.flush()
        #expect(try await store.project(id).recipeRevision == 1)
    }

    @Test func exportShowsSummaryThenStartsOneJob() async throws {
        let (viewModel, _, _, _) = try await setup()
        await viewModel.load()
        await viewModel.requestExport()
        guard case .summary(let summary) = viewModel.exportEntry else { Issue.record("Expected summary"); return }
        #expect(summary.policy.dimensions == (try PixelDimensions(width: 1280, height: 720)))
        viewModel.confirmExport()
        viewModel.confirmExport()
        #expect(viewModel.exportEntry == .none)
        #expect(await eventually {
            if case .completed = viewModel.exportState { true } else { false }
        })
    }

    @Test func freeOverLimitOffersProOnlyOnExplicitIntent() async throws {
        let (viewModel, _, _, log) = try await setup(seconds: 40)
        await viewModel.load()
        #expect(log.entries.isEmpty, "No forced paywall on open")
        await viewModel.requestExport()
        #expect(viewModel.exportEntry == .requiresPro)
        viewModel.upgradeForExport()
        #expect(log.entries == ["paywall"])
    }

    @Test func proHasNoWatermarkInPreview() async throws {
        let (viewModel, _, _, _) = try await setup(access: AccessState(level: .pro, provenance: .developmentFake))
        await viewModel.load()
        #expect(!viewModel.showsWatermark)
    }

    @Test func closeFlushesPendingChanges() async throws {
        let (viewModel, store, id, log) = try await setup()
        await viewModel.load()
        viewModel.setIntensity(0.2)
        await viewModel.close()
        #expect(abs(try await store.project(id).recipe.intensity.value - 0.2) < 0.0001)
        #expect(log.entries == ["close"])
    }
}

private struct StubBeatTimelines: BeatTimelineProviding {
    let result: BeatTimeline?
    func timeline(for source: SourceReference, fileURL: URL) async throws -> BeatTimeline? { result }
}

@MainActor
@Suite("Preview Beat controls (01 P06, 02 D05)")
struct PreviewBeatTests {
    private func make(timeline: BeatTimeline?, audio: Bool = true) async throws -> (ProjectPreviewViewModel, InMemoryProjectStore, ProjectID) {
        let store = InMemoryProjectStore()
        let record = try await store.createProject(NewProjectDraft(
            createdAt: Date(), name: try ProjectName("Tape"), sourceMode: .imported,
            sources: [StagedSource(
                role: .primary, stagedFile: URL(fileURLWithPath: "/s.mov"), fileName: "source.mov",
                metadata: SourceMetadata(
                    duration: .seconds(5), displayDimensions: try PixelDimensions(width: 1080, height: 1920),
                    frameRate: .fps(30), hasUsableAudio: audio, ownsSharedAudio: audio))],
            recipe: Recipe.initial(look: nil, creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 1)))
        let purchases = FakePurchaseService()
        let viewModel = ProjectPreviewViewModel(
            projectID: record.id, projects: store, access: purchases,
            exporter: ExportCoordinator(
                projects: store, access: purchases, renderer: FakeExportRenderer(), photos: FakePhotosSaver(),
                lookPreferences: InMemoryLookPreferencesStore(), telemetry: RecordingTelemetry()),
            telemetry: RecordingTelemetry(), beatTimelines: StubBeatTimelines(result: timeline),
            onClose: {}, onShowPaywall: {})
        return (viewModel, store, record.id)
    }

    private var sampleTimeline: BeatTimeline {
        BeatAnalyzer.timeline(samples: [Float](repeating: 0.2, count: 48_000))
    }

    @Test func enableAndIntensityPersistAndMutePausesBeat() async throws {
        let (viewModel, store, id) = try await make(timeline: sampleTimeline)
        await viewModel.load()
        #expect(viewModel.beatAvailability == .available)
        viewModel.setBeatEnabled(true)
        viewModel.setBeatIntensity(0.8)
        await viewModel.flush()
        let stored = try await store.project(id).recipe
        #expect(stored.beat == BeatSettings(isEnabled: true, intensity: 0.8))
        #expect(viewModel.isBeatEffective)
        viewModel.toggleMute()
        #expect(!viewModel.isBeatEffective, "Mute disables Beat modulation")
        #expect(viewModel.isBeatEnabled, "…without changing the Beat choice")
    }

    @Test func silentSourceReportsNoAudioAndStaysLookOnly() async throws {
        let (viewModel, _, _) = try await make(timeline: nil, audio: false)
        await viewModel.load()
        #expect(viewModel.beatAvailability == .noAudio)
        viewModel.setBeatEnabled(true)
        #expect(!viewModel.isBeatEffective, "No invented beats without audio")
    }
}
