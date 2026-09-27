import Foundation
import Testing
@testable import RENNDomain

/// Test shorthand; every timescale used here is positive.
private func t(_ value: Int64, _ timescale: Int32) -> RationalTime {
    try! RationalTime(value: value, timescale: timescale)
}

@Suite("RationalTime arithmetic")
struct RationalTimeArithmeticTests {
    @Test func sameTimescaleIsExact() throws {
        let a = t(90, 60)
        let b = t(30, 60)
        #expect(a + b == .seconds(2))
        #expect(a - b == .seconds(1))
    }

    @Test func mixedTimescalesUseTheLeastCommonMultiple() throws {
        let sum = t(1, 30) + t(1, 25)
        #expect(sum.timescale == 150)
        #expect(sum == t(11, 150))
    }

    @Test func oversizedCommonTimescaleRoundsToTheFinerClock() throws {
        // Host-clock nanoseconds mixed with a 600 timescale: lcm(1e9, 600) exceeds Int32.
        let host = t(1_500_000_001, 1_000_000_000)
        let movie = t(300, 600)
        let difference = host - movie
        #expect(difference.timescale == 1_000_000_000)
        #expect(difference == t(1_000_000_001, 1_000_000_000))
    }

    @Test func conversionRoundsToNearestIncludingNegatives() throws {
        #expect(t(1, 3).converted(to: 2) == t(1, 2))
        #expect(t(-1, 3).converted(to: 2) == t(-1, 2))
        #expect(t(1, 5).converted(to: 2) == .zero)
    }
}

@Suite("Dual-Cam composition (01 P05, 05 V03)")
struct DualCompositionTests {
    let canvas = try! PixelDimensions(width: 1080, height: 1920)

    @Test func baselineInsetIsTopRightThirtyPercentPortrait() {
        let layout = DualInsetLayout(canvas: canvas, corner: .topRight)
        #expect(layout.frame == WatermarkLayout.Rect(x: 1080 - 43 - 324, y: 43, width: 324, height: 576))
        #expect(layout.cornerRadius == 39)
        #expect(layout.reservedBottomRight(canvas: canvas) == 0)
    }

    @Test func everyCornerStaysInsideTheCanvas() {
        for corner in DualCameraLayout.Corner.allCases {
            let frame = DualInsetLayout(canvas: canvas, corner: corner).frame
            #expect(frame.x >= 0 && frame.y >= 0)
            #expect(frame.x + frame.width <= 1080 && frame.y + frame.height <= 1920)
        }
        let bottomRight = DualInsetLayout(canvas: canvas, corner: .bottomRight)
        #expect(bottomRight.reservedBottomRight(canvas: canvas) == 43 + 576)
    }

    @Test func commonIntervalIsTheOverlap() throws {
        let timing = try DualSourceTiming(
            rearStart: .zero, rearDuration: .seconds(10),
            frontStart: t(1, 10), frontDuration: .seconds(10))
        #expect(timing.start == t(1, 10))
        #expect(timing.duration == t(99, 10))
        #expect(timing.rearOffset == t(1, 10))
        #expect(timing.frontOffset == .zero)
        #expect(timing.sourceTime(.seconds(2), camera: .rear) == t(21, 10))
        #expect(timing.sourceTime(.seconds(2), camera: .front) == .seconds(2))
    }

    @Test func noOverlapOrTooShortIsRejected() throws {
        #expect(throws: DualSourceTiming.TimingError.noCommonInterval) {
            try DualSourceTiming(rearStart: .zero, rearDuration: .seconds(2), frontStart: .seconds(3), frontDuration: .seconds(2))
        }
        #expect(throws: DualSourceTiming.TimingError.tooShort(t(1, 2))) {
            try DualSourceTiming(
                rearStart: .zero, rearDuration: .seconds(2),
                frontStart: t(3, 2), frontDuration: .seconds(2))
        }
    }
}

@Suite("Dual-Cam export plan")
struct DualExportPlanTests {
    static let projectID = ProjectID()

    static func source(_ role: SourceRole, start: RationalTime = .zero, seconds: Int64 = 10, audio: Bool) throws -> SourceReference {
        SourceReference(
            role: role,
            relativePath: try ProjectFileLayout.file("\(role.rawValue).mov", in: .sources, of: projectID),
            fingerprint: FileFingerprint(byteCount: 1, sampleHash: 1),
            metadata: SourceMetadata(
                duration: .seconds(seconds), startOffset: start,
                displayDimensions: try PixelDimensions(width: 1080, height: 1920),
                frameRate: .fps(30),
                hasUsableAudio: audio, isMirrored: role == .frontCamera, ownsSharedAudio: audio))
    }

    static func record(_ sources: [SourceReference], layout: DualCameraLayout? = DualCameraLayout()) throws -> ProjectRecord {
        var recipe = Recipe.initial(look: nil, creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 1)
        recipe.dualLayout = layout
        return ProjectRecord(
            id: projectID, createdAt: .init(timeIntervalSince1970: 0), updatedAt: .init(timeIntervalSince1970: 0),
            name: try ProjectName("Dual"), sourceMode: .dualCamera, readiness: .ready,
            sources: sources, recipeRevision: 1, recipe: recipe)
    }

    let free = AccessState(level: .free, provenance: .developmentFake)

    @Test func dualPlanUsesCommonIntervalAndTheSingleAudioOwner() throws {
        let rear = try Self.source(.rearCamera, audio: true)
        let front = try Self.source(.frontCamera, start: .seconds(1), audio: false)
        let plan = try ExportPlan.make(record: try Self.record([rear, front]), access: free)
        let dual = try #require(plan.dual)
        #expect(dual.timing.duration == .seconds(9))
        #expect(plan.source == rear)
        #expect(plan.includesAudio)
        #expect(dual.source(for: .front) == front)
    }

    @Test func duplicateAudioOwnersOrMissingSourcesAreRejected() throws {
        let rear = try Self.source(.rearCamera, audio: true)
        let front = try Self.source(.frontCamera, audio: true)
        #expect(throws: ExportPlan.PlanError.invalidDualSources) {
            try ExportPlan.make(record: try Self.record([rear, front]), access: self.free)
        }
        #expect(throws: ExportPlan.PlanError.invalidDualSources) {
            try ExportPlan.make(record: try Self.record([rear]), access: self.free)
        }
        #expect(throws: ExportPlan.PlanError.invalidDualSources) {
            try ExportPlan.make(record: try Self.record([rear, try Self.source(.frontCamera, audio: false)], layout: nil), access: self.free)
        }
    }

    @Test func freeLimitAppliesToTheCommonInterval() throws {
        let rear = try Self.source(.rearCamera, seconds: 40, audio: true)
        let front = try Self.source(.frontCamera, start: .seconds(12), seconds: 40, audio: false)
        let plan = try ExportPlan.make(record: try Self.record([rear, front]), access: free)
        #expect(plan.dual?.timing.duration == .seconds(28), "28 s overlap fits Free even though each file is 40 s")
    }
}
