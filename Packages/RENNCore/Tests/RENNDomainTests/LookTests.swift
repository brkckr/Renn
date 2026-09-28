import Foundation
import Testing
@testable import RENNDomain

@Suite("Looks, intensity and history (01 P04)")
struct LookTests {
    @Test func recentsKeepLastFourDistinctMostRecentFirst() {
        var preferences = LookPreferences()
        for id in ["a", "b", "c", "d", "e"] { preferences.recordUse(of: LookID(id)) }
        #expect(preferences.recentIDs == ["e", "d", "c", "b"])
        preferences.recordUse(of: "c")
        #expect(preferences.recentIDs == ["c", "e", "d", "b"])
    }

    @Test func initializerNormalizesRecents() {
        let preferences = LookPreferences(recentIDs: ["a", "a", "b", "c", "d", "e"])
        #expect(preferences.recentIDs == ["a", "b", "c", "d"])
    }

    @Test func favoritesToggle() {
        var preferences = LookPreferences()
        preferences.setFavorite("a", true)
        #expect(preferences.isFavorite("a"))
        preferences.setFavorite("a", false)
        #expect(!preferences.isFavorite("a"))
    }

    @Test func intensityClampsAndRejectsNonFinite() {
        #expect(LookIntensity(1.5)?.value == 1)
        #expect(LookIntensity(-1)?.value == 0)
        #expect(LookIntensity(.nan) == nil)
        #expect(LookIntensity(.infinity) == nil)
        #expect(LookIntensity.off.isOff)
    }

    private func look(_ id: String, family: String = "vhs", dev: Bool = false) -> LookDefinition {
        LookDefinition(
            id: LookID(id), version: 1, family: family, nameKey: "n", descriptionKey: "d",
            defaultIntensity: LookIntensity(0.5)!, renderVersion: 1, isDevelopmentFixture: dev)
    }

    @Test func catalogValidation() {
        #expect(throws: LookCatalog.ValidationError.duplicateLookID("a")) {
            try LookCatalog(catalogVersion: "1", isDevelopmentFixture: false, recommendedLookID: nil,
                            looks: [look("a"), look("a")])
        }
        #expect(throws: LookCatalog.ValidationError.unknownRecommendedLook("z")) {
            try LookCatalog(catalogVersion: "1", isDevelopmentFixture: false, recommendedLookID: "z",
                            looks: [look("a")])
        }
        #expect(throws: LookCatalog.ValidationError.unsupportedSchemaVersion(2)) {
            try LookCatalog(schemaVersion: 2, catalogVersion: "1", isDevelopmentFixture: false,
                            recommendedLookID: nil, looks: [])
        }
    }

    @Test func familiesAreNonemptyAndOrdered() throws {
        let catalog = try LookCatalog(
            catalogVersion: "1", isDevelopmentFixture: false, recommendedLookID: nil,
            looks: [look("a", family: "vhs"), look("b", family: "hi8"), look("c", family: "vhs")])
        #expect(catalog.families == ["vhs", "hi8"])
        #expect(catalog.recommendedLook?.id == "a")
    }

    @Test func developmentCatalogIsNeverLaunchReady() throws {
        let twelveDev = try LookCatalog(
            catalogVersion: "1", isDevelopmentFixture: true, recommendedLookID: nil,
            looks: (1...12).map { look("l\($0)") })
        #expect(!twelveDev.isLaunchReady)
        let twelveWithFixture = try LookCatalog(
            catalogVersion: "1", isDevelopmentFixture: false, recommendedLookID: nil,
            looks: (1...11).map { look("l\($0)") } + [look("dev", dev: true)])
        #expect(!twelveWithFixture.isLaunchReady)
        let eleven = try LookCatalog(
            catalogVersion: "1", isDevelopmentFixture: false, recommendedLookID: nil,
            looks: (1...11).map { look("l\($0)") })
        #expect(!eleven.isLaunchReady)
        let twelve = try LookCatalog(
            catalogVersion: "1", isDevelopmentFixture: false, recommendedLookID: nil,
            looks: (1...12).map { look("l\($0)") })
        #expect(twelve.isLaunchReady)
    }

    @Test func manifestDecoding() throws {
        let json = """
        {
          "schemaVersion": 1,
          "catalogVersion": "dev-0",
          "isDevelopmentFixture": true,
          "recommendedLookID": "dev.diagnostic",
          "looks": [{
            "id": "dev.diagnostic", "version": 1, "family": "diagnostic",
            "nameKey": "look.dev.diagnostic.name", "descriptionKey": "look.dev.diagnostic.description",
            "defaultIntensity": 0.7, "renderVersion": 1, "isDevelopmentFixture": true
          }]
        }
        """
        let catalog = try JSONDecoder().decode(LookCatalog.self, from: Data(json.utf8))
        #expect(catalog.looks.count == 1)
        #expect(catalog.recommendedLook?.defaultIntensity.value == 0.7)
        #expect(catalog.isDevelopmentFixture)
    }

    @Test func manifestDecodingRejectsDuplicates() {
        let entry = """
        {"id": "x", "version": 1, "family": "f", "nameKey": "n", "descriptionKey": "d",
         "defaultIntensity": 0.5, "renderVersion": 1, "isDevelopmentFixture": false}
        """
        let json = """
        {"schemaVersion": 1, "catalogVersion": "1", "isDevelopmentFixture": false, "looks": [\(entry), \(entry)]}
        """
        #expect(throws: (any Error).self) { try JSONDecoder().decode(LookCatalog.self, from: Data(json.utf8)) }
    }
}

@Suite("Look parameters and snapshots (05 V04)")
struct LookParameterTests {
    private func look(_ parameters: [String: Double]) -> LookDefinition {
        LookDefinition(
            id: "l", version: 2, family: "f", nameKey: "n", descriptionKey: "d",
            defaultIntensity: LookIntensity(0.5)!, renderVersion: 1, isDevelopmentFixture: false,
            lut: "l_color", parameters: parameters)
    }

    @Test func recipeSnapshotsParametersAndIntensityScalesThem() throws {
        let definition = look([LookParameter.grain: 0.2, LookParameter.saturation: -0.4])
        var recipe = Recipe.initial(look: definition, creationStamp: try StampDate(year: 2026, month: 1, day: 1), seed: 1)
        #expect(recipe.lookParameters == definition.parameters)
        #expect(abs(recipe.effectiveParameter(LookParameter.grain) - 0.1) < 1e-12)
        recipe.intensity = .off
        #expect(recipe.effectiveParameter(LookParameter.saturation) == 0, "Intensity 0 disables the Look")
        #expect(recipe.effectiveParameter(LookParameter.vignette) == 0, "Missing keys contribute nothing")
    }

    @Test func manifestParametersAreBoundedAndOptional() throws {
        #expect(throws: LookCatalog.ValidationError.invalidParameter("l", LookParameter.grain)) {
            try LookCatalog(catalogVersion: "1", isDevelopmentFixture: false, recommendedLookID: nil,
                            looks: [look([LookParameter.grain: 5])])
        }
        #expect(throws: LookCatalog.ValidationError.invalidParameter("l", "sparkle")) {
            try LookCatalog(catalogVersion: "1", isDevelopmentFixture: false, recommendedLookID: nil,
                            looks: [look(["sparkle": 1])])
        }
        let json = """
        {"schemaVersion": 1, "catalogVersion": "1", "isDevelopmentFixture": false, "looks": [
          {"id": "a", "version": 1, "family": "f", "nameKey": "n", "descriptionKey": "d",
           "defaultIntensity": 0.5, "renderVersion": 1, "isDevelopmentFixture": false}]}
        """
        let catalog = try JSONDecoder().decode(LookCatalog.self, from: Data(json.utf8))
        #expect(catalog.looks[0].lut == nil && catalog.looks[0].parameters.isEmpty)
    }
}

@Suite("Recipe Look switching (01 P04)")
struct RecipeLookSwitchTests {
    @Test func switchingLoadsDefaultsAndSnapshotButKeepsEverythingElse() throws {
        let first = LookDefinition(
            id: "a", version: 1, family: "f", nameKey: "n", descriptionKey: "d",
            defaultIntensity: LookIntensity(0.7)!, renderVersion: 1, isDevelopmentFixture: true,
            parameters: [LookParameter.grain: 0.1])
        let second = LookDefinition(
            id: "b", version: 3, family: "f", nameKey: "n", descriptionKey: "d",
            defaultIntensity: LookIntensity(0.2)!, renderVersion: 1, isDevelopmentFixture: true,
            parameters: [LookParameter.vignette: 1])
        var recipe = Recipe.initial(look: first, creationStamp: try StampDate(year: 2026, month: 1, day: 1), seed: 9)
        recipe.intensity = LookIntensity(1)!
        recipe.audioMuted = true
        recipe.indicators.showsDate = true
        recipe.dualLayout = DualCameraLayout(insetCorner: .bottomLeft)

        let switched = recipe.switchingLook(to: second)
        #expect(switched.lookID == "b" && switched.lookVersion == 3)
        #expect(switched.lookParameters == [LookParameter.vignette: 1])
        #expect(switched.intensity.value == 0.2)
        #expect(switched.seed == 9 && switched.audioMuted && switched.indicators.showsDate)
        #expect(switched.dualLayout == recipe.dualLayout)
        #expect(recipe.switchingLook(to: first) == recipe, "Same Look keeps the saved intensity")
        #expect(recipe.switchingLook(to: nil).lookID == nil)
    }
}
