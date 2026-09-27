import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("Preview Look selector (01 P04/P07, 02 D05)")
struct LookSelectorTests {
    static let cool = LookDefinition(
        id: "test.cool", version: 2, family: "test", nameKey: "n", descriptionKey: "d",
        defaultIntensity: LookIntensity(0.4)!, renderVersion: 1, isDevelopmentFixture: true,
        parameters: [LookParameter.saturation: -0.1, LookParameter.warmth: -800])

    static let catalog = try! LookCatalog(
        catalogVersion: "test", isDevelopmentFixture: true, recommendedLookID: "dev.diagnostic",
        looks: StaticLookCatalogProvider.developmentCatalog.looks + [cool])

    private func setup() async throws -> (ProjectPreviewViewModel, InMemoryProjectStore, ProjectID) {
        let store = InMemoryProjectStore()
        var recipe = Recipe.initial(
            look: StaticLookCatalogProvider.developmentCatalog.looks.first,
            creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 3)
        recipe.beat = BeatSettings(isEnabled: true, intensity: 0.6)
        recipe.intensity = LookIntensity(0.9)!
        let record = try await store.createProject(NewProjectDraft(
            createdAt: Date(), name: try ProjectName("Tape"), sourceMode: .imported,
            sources: [StagedSource(
                role: .primary, stagedFile: URL(fileURLWithPath: "/s.mov"), fileName: "source.mov",
                metadata: SourceMetadata(
                    duration: .seconds(10), displayDimensions: try PixelDimensions(width: 1080, height: 1920),
                    frameRate: .fps(30), hasUsableAudio: true, ownsSharedAudio: true))],
            recipe: recipe))
        let purchases = FakePurchaseService()
        let viewModel = ProjectPreviewViewModel(
            projectID: record.id, projects: store, access: purchases,
            exporter: ExportCoordinator(
                projects: store, access: purchases, renderer: FakeExportRenderer(), photos: FakePhotosSaver(),
                lookPreferences: InMemoryLookPreferencesStore(), telemetry: RecordingTelemetry()),
            telemetry: RecordingTelemetry(), lookCatalog: StaticLookCatalogProvider(Self.catalog),
            onClose: {}, onShowPaywall: {})
        await viewModel.load()
        return (viewModel, store, record.id)
    }

    @Test func applyingAnotherLookIsOneRevisionWithItsDefaultsAndKeepsBeat() async throws {
        let (viewModel, store, id) = try await setup()
        let before = try await store.project(id)
        await viewModel.openLookSelector()
        #expect(viewModel.lookSelection == .init(lookID: "dev.diagnostic", intensity: 0.9))

        viewModel.stageLook("test.cool")
        #expect(viewModel.lookSelection?.intensity == 0.4, "Switching loads the Look's default")
        #expect(viewModel.displayRecipe?.lookID == "test.cool", "Preview shows the staged Look")
        #expect(viewModel.recipe?.lookID == "dev.diagnostic", "Nothing is applied while staged")

        viewModel.stageIntensity(0.5)
        viewModel.applyLookSelection()
        await viewModel.flush()
        let after = try await store.project(id)
        #expect(after.recipeRevision == before.recipeRevision + 1, "Apply creates one revision")
        #expect(after.recipe.lookID == "test.cool")
        #expect(after.recipe.lookVersion == 2)
        #expect(after.recipe.lookParameters == Self.cool.parameters, "Parameter snapshot of the new Look")
        #expect(after.recipe.intensity.value == 0.5)
        #expect(after.recipe.beat == BeatSettings(isEnabled: true, intensity: 0.6), "Beat is independent")
        #expect(after.recipe.seed == before.recipe.seed)
        #expect(viewModel.lookSelection == nil)
    }

    @Test func cancelDiscardsTheStagedChange() async throws {
        let (viewModel, store, id) = try await setup()
        let before = try await store.project(id)
        await viewModel.openLookSelector()
        viewModel.stageLook("test.cool")
        viewModel.cancelLookSelection()
        await viewModel.flush()
        #expect(try await store.project(id) == before)
        #expect(viewModel.displayRecipe == before.recipe)
    }

    @Test func reselectingTheProjectsLookRestoresItsSavedIntensity() async throws {
        let (viewModel, _, _) = try await setup()
        await viewModel.openLookSelector()
        viewModel.stageLook("test.cool")
        viewModel.stageLook("dev.diagnostic")
        #expect(viewModel.lookSelection?.intensity == 0.9)
        viewModel.stageLook("unknown.look")
        #expect(viewModel.lookSelection?.lookID == "dev.diagnostic", "Unknown IDs are ignored")
    }

    @Test func applyingTheUnchangedSelectionWritesNothing() async throws {
        let (viewModel, store, id) = try await setup()
        let before = try await store.project(id)
        await viewModel.openLookSelector()
        viewModel.applyLookSelection()
        await viewModel.flush()
        #expect(try await store.project(id).recipeRevision == before.recipeRevision)
    }

    @Test func completionPresentationHappensOncePerOutput() async throws {
        let (viewModel, _, _) = try await setup()
        let output = OutputID()
        #expect(viewModel.beginCompletionPresentation(of: output))
        #expect(!viewModel.beginCompletionPresentation(of: output), "Reopening never replays the settle/haptic")
        #expect(viewModel.beginCompletionPresentation(of: OutputID()))
    }
}
