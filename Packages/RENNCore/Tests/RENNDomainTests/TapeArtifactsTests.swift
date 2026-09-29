import Testing
@testable import RENNDomain

@Suite("Tape artefact strengths")
struct TapeArtifactsTests {
    static func recipe(_ parameters: [String: Double], intensity: Double) throws -> Recipe {
        let look = LookDefinition(
            id: "t", version: 1, family: "f", nameKey: "n", descriptionKey: "d",
            defaultIntensity: try #require(LookIntensity(intensity)), renderVersion: 1, isDevelopmentFixture: true,
            parameters: parameters)
        return Recipe.initial(look: look, creationStamp: try StampDate(year: 2026, month: 9, day: 30), seed: 5)
    }

    @Test func intensityScalesEveryStrength() throws {
        let parameters = [
            LookParameter.chromaBleed: 0.8, LookParameter.tapeSoftness: 0.4, LookParameter.scanlines: 0.2,
            LookParameter.lineJitter: 0.6, LookParameter.tracking: 1,
        ]
        let half = TapeArtifacts(recipe: try Self.recipe(parameters, intensity: 0.5))
        #expect(half == TapeArtifacts(chromaBleed: 0.4, softness: 0.2, scanlines: 0.1, lineJitter: 0.3, tracking: 0.5))
        #expect(half.isActive)
        #expect(!TapeArtifacts(recipe: try Self.recipe(parameters, intensity: 0)).isActive)
    }

    @Test func looksWithoutTapeParametersSkipTheStage() throws {
        #expect(!TapeArtifacts(recipe: try Self.recipe([LookParameter.grain: 0.1], intensity: 1)).isActive)
    }

    @Test func strengthsAreClampedAndFinite() {
        let clamped = TapeArtifacts(chromaBleed: 3, softness: -1, scanlines: .nan, lineJitter: .infinity, tracking: 0.5)
        #expect(clamped == TapeArtifacts(chromaBleed: 1, softness: 0, scanlines: 0, lineJitter: 0, tracking: 0.5))
    }

    @Test func sampleReachScalesWithTheFrame() {
        #expect(TapeArtifacts.sampleReach(shortEdge: 1080) == 30.5)
        #expect(TapeArtifacts.sampleReach(shortEdge: 2160) == 59)
        #expect(TapeArtifacts.sampleReach(shortEdge: 10) == 28.5 * 0.25 + 2)
    }

    @Test func seedPhaseIsStableAndInRange() {
        #expect(TapeArtifacts.seedPhase(0) == 0)
        #expect(TapeArtifacts.seedPhase(1024 + 512) == 0.5)
        #expect((0..<2000).allSatisfy { (0..<1).contains(TapeArtifacts.seedPhase(UInt64($0) &* 7919)) })
    }
}
