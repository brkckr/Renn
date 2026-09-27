import Testing
@testable import RENNDomain

@Suite("Cadence limiter (01 P08, 05 V01)")
struct CadenceLimiterTests {
    /// Presentation times k * frameDuration for a CFR source.
    private func cfr(_ count: Int, value: Int64, timescale: Int32, start: Int64 = 0) -> [RationalTime] {
        (0..<count).map { try! RationalTime(value: start + Int64($0) * value, timescale: timescale) }
    }

    private func kept(_ times: [RationalTime], rate: FrameRate) -> [Int] {
        var limiter = CadenceLimiter(outputRate: rate)
        return times.indices.filter { limiter.shouldKeep(presentationTime: times[$0]) }
    }

    @Test func sameRateKeepsEveryFrame() {
        #expect(kept(cfr(90, value: 1, timescale: 30), rate: .fps(30)).count == 90)
        #expect(kept(cfr(90, value: 1001, timescale: 30000), rate: .ntsc29_97).count == 90)
        #expect(kept(cfr(48, value: 1, timescale: 24), rate: .fps(24)).count == 48)
    }

    @Test func sixtyToThirtyKeepsEveryOtherFrame() {
        #expect(kept(cfr(120, value: 1, timescale: 60), rate: .fps(30)) == Array(stride(from: 0, to: 120, by: 2)))
        #expect(kept(cfr(120, value: 1001, timescale: 60000), rate: .ntsc29_97) == Array(stride(from: 0, to: 120, by: 2)))
        #expect(kept(cfr(100, value: 1, timescale: 50), rate: .fps(25)) == Array(stride(from: 0, to: 100, by: 2)))
    }

    @Test func oneTwentyToThirtyKeepsEveryFourthFrame() {
        #expect(kept(cfr(240, value: 1, timescale: 120), rate: .fps(30)) == Array(stride(from: 0, to: 240, by: 4)))
    }

    @Test func nonZeroStartTimeIsTheAnchor() {
        let times = cfr(60, value: 1, timescale: 60, start: 3600)
        #expect(kept(times, rate: .fps(30)) == Array(stride(from: 0, to: 60, by: 2)))
    }

    @Test func jitteredVariableFrameRateKeepsOneFramePerSlot() throws {
        // ~60 FPS with ±1 ms jitter at a 600 timescale-free microsecond clock.
        let jitter: [Int64] = [0, 900, -700, 400, -1000, 600, 0, -300]
        let times = (0..<240).map { index -> RationalTime in
            let micro = Int64(index) * 16_667 + jitter[index % jitter.count]
            return try! RationalTime(value: max(0, micro), timescale: 1_000_000)
        }
        let keptIndices = kept(times, rate: .fps(30))
        #expect(abs(keptIndices.count - 120) <= 1)
        // Kept frames never exceed the output rate: consecutive gaps >= 7/8 of an interval.
        for (a, b) in zip(keptIndices, keptIndices.dropFirst()) {
            let gap = times[b].approximateSeconds - times[a].approximateSeconds
            #expect(gap >= (1.0 / 30) * 7 / 8)
        }
    }

    @Test func missingFramesDoNotCauseBursts() {
        // 60 FPS with a 10-frame dropout in the middle.
        let times = cfr(120, value: 1, timescale: 60).enumerated().filter { !(50..<60).contains($0.offset) }.map(\.element)
        var limiter = CadenceLimiter(outputRate: .fps(30))
        var lastKept: RationalTime?
        for time in times where limiter.shouldKeep(presentationTime: time) {
            if let lastKept {
                #expect(time.approximateSeconds - lastKept.approximateSeconds >= (1.0 / 30) * 7 / 8)
            }
            lastKept = time
        }
    }
}

@Suite("Watermark layout (02 D07)")
struct WatermarkLayoutTests {
    @Test func bottomRightInsetAndWidthAt720p() throws {
        let layout = WatermarkLayout(output: try PixelDimensions(width: 720, height: 1280), aspectRatio: 4)
        // inset 4% of 720 = 28.8 -> 29; width 28% of 720 = 201.6 -> 202; height 202/4 = 50.5 -> 51 (rounded).
        #expect(layout.frame.width == 202)
        #expect(layout.frame.x == 720 - 29 - 202)
        #expect(layout.frame.y + layout.frame.height == 1280 - 29)
    }

    @Test func movesAboveAReservedCorner() throws {
        let plain = WatermarkLayout(output: try PixelDimensions(width: 1280, height: 720), aspectRatio: 4)
        let reserved = WatermarkLayout(output: try PixelDimensions(width: 1280, height: 720), aspectRatio: 4, reservedBottomRight: 200)
        #expect(reserved.frame.y == plain.frame.y - 200)
        #expect(reserved.frame.x == plain.frame.x)
    }
}

@Suite("Import gate and export plan (01 P08, 05 V06/V09)")
struct ExportPlanTests {
    private let stamp = try! StampDate(year: 2026, month: 9, day: 27)

    private func profile(seconds: Int64) -> SourceMediaProfile {
        SourceMediaProfile(
            displayDimensions: try! PixelDimensions(width: 2160, height: 3840), frameRate: .fps(60),
            duration: .seconds(seconds), hasUsableAudio: true)
    }

    private func record(seconds: Int64, audio: Bool = true, muted: Bool = false, readiness: ProjectSummary.Readiness = .ready) throws -> ProjectRecord {
        let id = ProjectID()
        var recipe = Recipe.initial(look: nil, creationStamp: stamp, seed: 1)
        recipe.audioMuted = muted
        return ProjectRecord(
            id: id, createdAt: .init(timeIntervalSince1970: 0), updatedAt: .init(timeIntervalSince1970: 0),
            name: try ProjectName("T"), sourceMode: .imported, readiness: readiness,
            sources: [SourceReference(
                role: .primary, relativePath: try ProjectFileLayout.file("a.mov", in: .sources, of: id),
                fingerprint: FileFingerprint(byteCount: 1, sampleHash: 1),
                metadata: SourceMetadata(
                    duration: .seconds(seconds), displayDimensions: try PixelDimensions(width: 2160, height: 3840),
                    frameRate: .fps(60), hasUsableAudio: audio, ownsSharedAudio: audio))],
            recipeRevision: 3, recipe: recipe)
    }

    @Test func freeImportOverThirtySecondsOffersPro() {
        let free = AccessState(level: .free, provenance: .providerVerified)
        #expect(ImportGate.evaluate(profile(seconds: 31), access: free)
            == .requiresProForDuration(limit: .seconds(30), sourceDuration: .seconds(31)))
        #expect(ImportGate.evaluate(profile(seconds: 31), access: .notConfigured)
            == .requiresProForDuration(limit: .seconds(30), sourceDuration: .seconds(31)))
        guard case .accept(let policy) = ImportGate.evaluate(profile(seconds: 30), access: free) else {
            Issue.record("30 s must be accepted"); return
        }
        #expect(policy.dimensions == (try! PixelDimensions(width: 720, height: 1280)))
        #expect(policy.frameRate == .fps(30))
    }

    @Test func proImportHasNoCommercialDurationCap() {
        let pro = AccessState(level: .pro, provenance: .providerVerified)
        guard case .accept(let policy) = ImportGate.evaluate(profile(seconds: 3 * 3600), access: pro) else {
            Issue.record("Pro must accept long sources"); return
        }
        #expect(policy.frameRate == .fps(60))
        #expect(!policy.requiresWatermark)
    }

    @Test func planSnapshotsRevisionAndPolicy() throws {
        let plan = try ExportPlan.make(record: try record(seconds: 20), access: .notConfigured)
        #expect(plan.recipeRevision == 3)
        #expect(plan.policy.tier == .free)
        #expect(plan.policy.requiresWatermark)
        #expect(plan.includesAudio)
    }

    @Test func mutedOrSilentProjectsExportWithoutAudio() throws {
        #expect(!(try ExportPlan.make(record: try record(seconds: 5, muted: true), access: .notConfigured)).includesAudio)
        #expect(!(try ExportPlan.make(record: try record(seconds: 5, audio: false), access: .notConfigured)).includesAudio)
    }

    @Test func planRejectsNotReadyAndOverLimitFree() throws {
        #expect(throws: ExportPlan.PlanError.projectNotReady) {
            try ExportPlan.make(record: try record(seconds: 5, readiness: .interrupted), access: .notConfigured)
        }
        #expect(throws: ExportPlan.PlanError.requiresPro(limit: .seconds(30))) {
            try ExportPlan.make(record: try record(seconds: 45), access: .notConfigured)
        }
    }

    @Test func progressIsMonotonicAndNeverCompleteBeforeValidation() {
        var progress = ExportProgress()
        progress.update(stage: .rendering, renderedSeconds: 5, totalSeconds: 10)
        #expect(progress.fraction == 0.475)
        progress.update(stage: .rendering, renderedSeconds: 2, totalSeconds: 10)
        #expect(progress.fraction == 0.475, "Never goes backwards")
        progress.update(stage: .preparing)
        #expect(progress.stage == .rendering)
        progress.update(stage: .validating)
        #expect(progress.fraction < 1)
    }
}
