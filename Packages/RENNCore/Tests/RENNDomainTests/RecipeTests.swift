import Foundation
import Testing
@testable import RENNDomain

@Suite("Recipe and Dual-Cam swap timeline (05 V03/V07)")
struct RecipeTests {
    private let stamp = try! StampDate(year: 2026, month: 9, day: 27)

    @Test func initialRecipeUsesLookDefaultsAndIndicatorsOff() {
        let look = LookDefinition(
            id: "l", version: 3, family: "f", nameKey: "n", descriptionKey: "d",
            defaultIntensity: LookIntensity(0.6)!, renderVersion: 1, isDevelopmentFixture: false)
        let recipe = Recipe.initial(look: look, creationStamp: stamp, seed: 9)
        #expect(recipe.lookID == "l")
        #expect(recipe.lookVersion == 3)
        #expect(recipe.intensity.value == 0.6)
        #expect(!recipe.beat.isEnabled)
        #expect(!recipe.indicators.showsRec && !recipe.indicators.showsPlay
            && !recipe.indicators.showsBattery && !recipe.indicators.showsDate)
        #expect(recipe.indicators.stampDate == stamp)
        #expect(recipe.dualLayout == nil)
        #expect(throws: Never.self) { try recipe.validate() }
    }

    @Test func swapsAreOrderedCoalescedAndReplayedByMediaTime() throws {
        var layout = DualCameraLayout()
        let first = layout.recordSwap(at: try RationalTime(value: 300, timescale: 600))
        #expect(first)
        let sameTime = layout.recordSwap(at: try RationalTime(value: 300, timescale: 600))
        #expect(!sameTime, "Same time is coalesced")
        let earlier = layout.recordSwap(at: try RationalTime(value: 100, timescale: 600))
        #expect(!earlier, "Going back in time is ignored")
        let negative = layout.recordSwap(at: try RationalTime(value: -1, timescale: 600))
        #expect(!negative)
        let second = layout.recordSwap(at: .seconds(2))
        #expect(second)
        #expect(layout.swaps.map(\.mainCamera) == [.front, .rear])

        #expect(layout.mainCamera(at: .zero) == .rear)
        #expect(layout.mainCamera(at: try RationalTime(value: 299, timescale: 600)) == .rear)
        #expect(layout.mainCamera(at: try RationalTime(value: 1, timescale: 2)) == .front, "Swap applies at its exact time")
        #expect(layout.mainCamera(at: .seconds(5)) == .rear)
    }

    @Test func validationRejectsCorruptTimelinesAndNonFiniteParameters() throws {
        var recipe = Recipe.initial(look: nil, creationStamp: stamp, seed: 1, dualLayout: DualCameraLayout())
        recipe.lookParameters["grain"] = .infinity
        #expect(throws: Recipe.ValidationError.nonFiniteParameter("grain")) { try recipe.validate() }

        let corrupt = DualCameraLayout(swaps: [
            .init(sourceTime: .seconds(2), mainCamera: .front),
            .init(sourceTime: .seconds(1), mainCamera: .rear),
        ])
        let invalid = Recipe.initial(look: nil, creationStamp: stamp, seed: 1, dualLayout: corrupt)
        #expect(throws: Recipe.ValidationError.invalidSwapTimeline) { try invalid.validate() }

        let redundant = DualCameraLayout(swaps: [.init(sourceTime: .seconds(1), mainCamera: .rear)])
        #expect(throws: Recipe.ValidationError.invalidSwapTimeline) {
            try Recipe.initial(look: nil, creationStamp: stamp, seed: 1, dualLayout: redundant).validate()
        }

        var future = Recipe.initial(look: nil, creationStamp: stamp, seed: 1)
        future.version = Recipe.currentVersion + 1
        #expect(throws: Recipe.ValidationError.unsupportedVersion(Recipe.currentVersion + 1)) { try future.validate() }
    }

    @Test func codableRoundTripPreservesEverything() throws {
        var layout = DualCameraLayout(insetCorner: .bottomLeft, initialMainCamera: .front)
        layout.recordSwap(at: try RationalTime(value: 1001, timescale: 30000))
        var recipe = Recipe.initial(look: nil, creationStamp: stamp, seed: .max, dualLayout: layout)
        recipe.lookParameters = ["a": 0.25]
        recipe.beat = BeatSettings(isEnabled: true, intensity: 0.4)
        recipe.audioMuted = true
        recipe.indicators.showsDate = true
        let decoded = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded == recipe)
    }

    @Test func stampDateFromDateUsesGivenTimeZone() throws {
        // 2026-09-27 23:30 UTC is already 2026-09-28 in Istanbul (UTC+3).
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-27T23:30:00Z"))
        #expect(try StampDate(date: date, timeZone: TimeZone(identifier: "UTC")!).text == "2026.09.27")
        #expect(try StampDate(date: date, timeZone: TimeZone(identifier: "Europe/Istanbul")!).text == "2026.09.28")
    }

    @Test func recordRoundTripAndSummary() throws {
        let id = ProjectID()
        let path = try ProjectFileLayout.file("a.mov", in: .sources, of: id)
        #expect(ProjectFileLayout.projectID(of: path) == id)
        let record = ProjectRecord(
            id: id, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2),
            name: try ProjectName("Tape"), sourceMode: .imported, readiness: .ready,
            sources: [SourceReference(
                role: .primary, relativePath: path, fingerprint: FileFingerprint(byteCount: 5, sampleHash: 6),
                metadata: SourceMetadata(
                    duration: .seconds(3), displayDimensions: try PixelDimensions(width: 4, height: 2),
                    frameRate: .ntsc29_97, hasUsableAudio: false, ownsSharedAudio: false))],
            recipeRevision: 4, recipe: Recipe.initial(look: nil, creationStamp: stamp, seed: 2))
        #expect(try JSONDecoder().decode(ProjectRecord.self, from: JSONEncoder().encode(record)) == record)
        #expect(record.summary.readiness == .ready)
        var deleting = record
        deleting.readiness = .deleting
        #expect(!deleting.isListed)
    }

    @Test func decodingRejectsTraversalPaths() {
        let json = Data(#""Projects/../../etc/passwd""#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(OwnedRelativePath.self, from: json) }
    }
}
