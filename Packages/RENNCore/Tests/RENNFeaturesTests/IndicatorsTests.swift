import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@Suite("Indicators draft (01 P07)")
struct IndicatorsDraftTests {
    private let original = IndicatorSettings(stampDate: try! StampDate(year: 2026, month: 9, day: 27))

    @Test func stagedChangesDoNotTouchSettingsUntilApplied() {
        var draft = IndicatorsDraft(original)
        draft.showsRec = true
        draft.showsDate = true
        #expect(original.showsRec == false, "Settings are values; cancel simply drops the draft")
        let applied = draft.applied(to: original)
        #expect(applied.showsRec && applied.showsDate && !applied.showsPlay && !applied.showsBattery)
    }

    @Test func turnAllOffKeepsTheDateSelection() {
        var draft = IndicatorsDraft(original)
        draft.showsDate = true
        do { let changed = draft.setDate(year: 1998, month: 10, day: 19); #expect(changed) }
        draft.turnAllOff()
        #expect(!draft.anyOn)
        #expect(draft.stampDate.text == "1998.10.19")
    }

    @Test func leapDayAndRangeValidation() {
        var draft = IndicatorsDraft(original)
        do { let changed = draft.setDate(year: 2024, month: 2, day: 29); #expect(changed) }
        do { let changed = draft.setDate(year: 2023, month: 2, day: 29); #expect(!changed) }
        do { let changed = draft.setDate(year: 0, month: 1, day: 1); #expect(!changed) }
        #expect(draft.stampDate.text == "2024.02.29", "Invalid input keeps the previous date")
    }

    @Test func pickerDateIsFrozenInTheGivenTimeZone() throws {
        var draft = IndicatorsDraft(original)
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-12-31T22:30:00Z"))
        draft.setDate(instant, timeZone: TimeZone(identifier: "Europe/Istanbul")!)
        #expect(draft.stampDate.text == "2027.01.01")
    }
}

@MainActor
@Suite("Preview applies indicators as one revision")
struct PreviewIndicatorsTests {
    @Test func applyCreatesOneRevision() async throws {
        let store = InMemoryProjectStore()
        let record = try await store.createProject(NewProjectDraft(
            createdAt: Date(), name: try ProjectName("Tape"), sourceMode: .imported,
            sources: [StagedSource(
                role: .primary, stagedFile: URL(fileURLWithPath: "/s.mov"), fileName: "source.mov",
                metadata: SourceMetadata(
                    duration: .seconds(5), displayDimensions: try PixelDimensions(width: 1080, height: 1920),
                    frameRate: .fps(30), hasUsableAudio: false, ownsSharedAudio: false))],
            recipe: Recipe.initial(look: nil, creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 1)))
        let purchases = FakePurchaseService()
        let viewModel = ProjectPreviewViewModel(
            projectID: record.id, projects: store, access: purchases,
            exporter: ExportCoordinator(
                projects: store, access: purchases, renderer: FakeExportRenderer(), photos: FakePhotosSaver(),
                lookPreferences: InMemoryLookPreferencesStore(), telemetry: RecordingTelemetry()),
            telemetry: RecordingTelemetry(), onClose: {}, onShowPaywall: {})
        await viewModel.load()
        var draft = IndicatorsDraft(try #require(viewModel.recipe).indicators)
        draft.showsRec = true
        draft.showsPlay = true
        draft.showsBattery = true
        draft.showsDate = true
        viewModel.applyIndicators(draft)
        await viewModel.flush()
        let stored = try await store.project(record.id)
        #expect(stored.recipeRevision == 2)
        #expect(stored.recipe.indicators.showsRec && stored.recipe.indicators.showsDate)
        #expect(stored.name.value == "Tape", "The date stamp never renames the project")
    }
}
