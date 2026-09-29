import Testing
@testable import RENNDomain

@Suite("Film overlays: dust, light leak, burnt edges")
struct FilmOverlaysTests {
    static func recipe(_ parameters: [String: Double], intensity: Double = 1, seed: UInt64 = 42) throws -> Recipe {
        let look = LookDefinition(
            id: "t", version: 1, family: "f", nameKey: "n", descriptionKey: "d",
            defaultIntensity: try #require(LookIntensity(intensity)), renderVersion: 1, isDevelopmentFixture: true,
            parameters: parameters)
        return Recipe.initial(look: look, creationStamp: try StampDate(year: 2026, month: 9, day: 30), seed: seed)
    }

    static func at(_ seconds: Double) throws -> RationalTime {
        try RationalTime(value: Int64((seconds * 600).rounded()), timescale: 600)
    }

    @Test func looksWithoutOverlaysAndIntensityZeroAreInactive() throws {
        #expect(!FilmOverlays(recipe: try Self.recipe([LookParameter.grain: 0.1]), time: .zero).isActive)
        let all = [LookParameter.dust: 1.0, LookParameter.lightLeak: 1, LookParameter.burnEdges: 1]
        #expect(!FilmOverlays(recipe: try Self.recipe(all, intensity: 0), time: try Self.at(1)).isActive)
        #expect(FilmOverlays(recipe: try Self.recipe(all), time: try Self.at(1)).isActive)
    }

    @Test func dustHoldsWithinAStepAndChangesBetweenSteps() throws {
        let recipe = try Self.recipe([LookParameter.dust: 0.8])
        let a = try #require(FilmOverlays(recipe: recipe, time: try Self.at(1.001)).dust)
        let b = try #require(FilmOverlays(recipe: recipe, time: try Self.at(1.04)).dust)
        #expect(a == b, "same 1/20 s step")
        let steps = try (0..<20).map { try #require(FilmOverlays(recipe: recipe, time: try Self.at(2 + Double($0) * 0.05)).dust) }
        #expect(Set(steps.map(\.variant)).count > 10, "dust changes step to step")
        for dust in steps {
            #expect(dust.strength == 0.8)
            #expect((1...1.3).contains(dust.zoom) && (0..<1).contains(dust.offsetX) && (0..<1).contains(dust.offsetY))
        }
    }

    @Test func overlaysAreReproducibleAndDependOnTheSeed() throws {
        let parameters = [LookParameter.dust: 1.0, LookParameter.lightLeak: 1, LookParameter.burnEdges: 1]
        let time = try Self.at(3.3)
        #expect(FilmOverlays(recipe: try Self.recipe(parameters), time: time) == FilmOverlays(recipe: try Self.recipe(parameters), time: time))
        #expect(FilmOverlays(recipe: try Self.recipe(parameters, seed: 1), time: time).dust
            != FilmOverlays(recipe: try Self.recipe(parameters, seed: 2), time: time).dust)
    }

    @Test func lightLeakRisesFadesAndRestsEachCycle() throws {
        let recipe = try Self.recipe([LookParameter.lightLeak: 0.5], seed: 0)
        let samples = try stride(from: 0.0, to: FilmOverlays.leakPeriod, by: 0.05).map {
            try #require(FilmOverlays(recipe: recipe, time: try Self.at($0)).leak)
        }
        let opacities = samples.map(\.opacity)
        #expect(opacities.allSatisfy { (0...0.5).contains($0) })
        #expect(opacities.max()! > 0.49, "peaks at the Look strength")
        #expect(opacities.filter { $0 == 0 }.count > samples.count / 3, "dark for part of the cycle")
        #expect(samples.allSatisfy { abs($0.drift) <= 0.1 + 1e-12 })
        #expect(samples.allSatisfy { !$0.cool })
        let cool = try Self.recipe([LookParameter.lightLeak: 0.5, LookParameter.lightLeakCool: 1], intensity: 0.4)
        #expect(FilmOverlays(recipe: cool, time: .zero).leak?.cool == true, "tone ignores intensity")
    }

    @Test func burnBreathesWithinFivePercent() throws {
        let recipe = try Self.recipe([LookParameter.burnEdges: 0.6])
        for second in stride(from: 0.0, to: 8, by: 0.25) {
            let burn = FilmOverlays(recipe: recipe, time: try Self.at(second)).burn
            #expect(burn >= 0.6 * 0.9 - 1e-12 && burn <= 0.6 + 1e-12)
        }
    }
}
