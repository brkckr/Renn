import Testing
@testable import RENNDomain

@Suite("Film grain geometry and colour")
struct FilmGrainTests {
    @Test func cellScaleFollowsTheShortEdgeNotOutputPixels() {
        #expect(FilmGrain.cellScale(shortEdge: 1080, grainSize: 1.4) == 1.4)
        #expect(FilmGrain.cellScale(shortEdge: 2160, grainSize: 1.4) == 2.8)
        #expect(FilmGrain.cellScale(shortEdge: 720, grainSize: 1.5) == 1.0)
    }

    @Test func cellScaleIsBoundedForThumbnailsAndBadInput() {
        #expect(FilmGrain.cellScale(shortEdge: 100, grainSize: 1) == FilmGrain.minimumScale)
        #expect(FilmGrain.cellScale(shortEdge: 1080, grainSize: 99) == 4)
        #expect(FilmGrain.cellScale(shortEdge: 0, grainSize: 1.4) == 1)
        #expect(FilmGrain.cellScale(shortEdge: 1080, grainSize: .nan) == FilmGrain.defaultSize)
    }

    @Test func channelWeightsKeepGreyNeutralFromMonoToColour() {
        for chroma in [0.0, 0.3, 1.0] {
            let rows = FilmGrain.channelWeights(chroma: chroma)
            for row in rows {
                #expect(abs(row.reduce(0, +) - 1) < 1e-12)
            }
        }
        let mono = FilmGrain.channelWeights(chroma: 0)
        #expect(mono.allSatisfy { $0 == mono[0] })
        #expect(FilmGrain.channelWeights(chroma: 1) == [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
        #expect(FilmGrain.channelWeights(chroma: 7) == FilmGrain.channelWeights(chroma: 1))
    }

    @Test func shapeParametersIgnoreIntensity() throws {
        let look = LookDefinition(
            id: "t", version: 1, family: "f", nameKey: "n", descriptionKey: "d",
            defaultIntensity: try #require(LookIntensity(0.5)), renderVersion: 1, isDevelopmentFixture: true,
            parameters: [LookParameter.grain: 0.2, LookParameter.grainSize: 2])
        let recipe = Recipe.initial(look: look, creationStamp: try StampDate(year: 2026, month: 9, day: 30), seed: 1)
        #expect(recipe.effectiveParameter(LookParameter.grain) == 0.1)
        #expect(recipe.shapeParameter(LookParameter.grainSize, fallback: FilmGrain.defaultSize) == 2)
        #expect(recipe.shapeParameter(LookParameter.grainChroma, fallback: FilmGrain.defaultChroma) == 0)
        #expect(LookParameter.unscaled.isSubset(of: LookParameter.all))
        #expect(LookParameter.all == Set(LookParameter.limits.keys))
    }
}
