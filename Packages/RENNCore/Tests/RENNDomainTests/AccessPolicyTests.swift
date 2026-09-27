import Testing
@testable import RENNDomain

@Suite("Access policy (01 P08, 05 V01)")
struct AccessPolicyTests {
    private func profile(
        _ width: Int, _ height: Int,
        fps: FrameRate = .fps(30),
        seconds: Int64 = 10,
        audio: Bool = true
    ) -> SourceMediaProfile {
        SourceMediaProfile(
            displayDimensions: try! PixelDimensions(width: width, height: height),
            frameRate: fps,
            duration: .seconds(seconds),
            hasUsableAudio: audio)
    }

    private func allowedPolicy(_ resolution: OutputPolicyResolution) throws -> OutputPolicy {
        guard case .allowed(let policy) = resolution else {
            Issue.record("Expected allowed policy, got \(resolution)")
            throw CancellationError()
        }
        return policy
    }

    @Test("Free dimension examples from the contract", arguments: [
        (3840, 2160, 1280, 720),
        (2160, 3840, 720, 1280),
        (1080, 1080, 720, 720),
        (1920, 1080, 1280, 720),
        (1080, 1920, 720, 1280),
        (1280, 720, 1280, 720),
        (640, 480, 640, 480),
        (320, 240, 320, 240),
    ])
    func freeDimensions(width: Int, height: Int, expectedWidth: Int, expectedHeight: Int) throws {
        let result = AccessPolicy.freeDimensions(for: try PixelDimensions(width: width, height: height))
        #expect(result.width == expectedWidth)
        #expect(result.height == expectedHeight)
    }

    @Test("Free never upscales and always returns even dimensions")
    func freeEvenAndNoUpscale() throws {
        for (width, height) in [(1441, 2561), (719, 1279), (3001, 1999), (7, 5), (2, 2), (4096, 2160)] {
            let source = try PixelDimensions(width: width, height: height)
            let result = AccessPolicy.freeDimensions(for: source)
            #expect(result.width % 2 == 0 && result.height % 2 == 0)
            #expect(result.width <= Swift.max(width, 2) && result.height <= Swift.max(height, 2))
            #expect(result.shortEdge <= 720 && result.longEdge <= 1280)
        }
    }

    @Test("Free preserves aspect within rounding error")
    func freeAspectPreserved() throws {
        let source = try PixelDimensions(width: 4096, height: 2160)
        let result = AccessPolicy.freeDimensions(for: source)
        let sourceAspect = Double(source.width) / Double(source.height)
        let resultAspect = Double(result.width) / Double(result.height)
        // At most one even step of rounding on either edge.
        #expect(abs(sourceAspect - resultAspect) < 2.0 / Double(result.height) * sourceAspect)
    }

    @Test("Free cadence examples", arguments: [
        (FrameRate.fps(24), FrameRate.fps(24)),
        (FrameRate.fps(25), FrameRate.fps(25)),
        (FrameRate.ntsc29_97, FrameRate.ntsc29_97),
        (FrameRate.ntsc59_94, FrameRate.ntsc29_97),
        (FrameRate.fps(60), FrameRate.fps(30)),
        (FrameRate.fps(50), FrameRate.fps(25)),
        (FrameRate.fps(120), FrameRate.fps(30)),
        (FrameRate.ntsc23_976, FrameRate.ntsc23_976),
    ])
    func freeCadence(source: FrameRate, expected: FrameRate) throws {
        let policy = try allowedPolicy(AccessPolicy.resolve(source: profile(1080, 1920, fps: source), tier: .free))
        #expect(policy.frameRate == expected)
    }

    @Test("VFR noise just above the ceiling resolves to the ceiling, not half")
    func vfrNoise() throws {
        let noisy = try FrameRate(frames: 3002, perSeconds: 100) // 30.02
        #expect(noisy.limited(toMaximumFPS: 30) == .fps(30))
    }

    @Test("Pro keeps supported cadence and never invents 60 FPS")
    func proCadence() throws {
        let sixty = try allowedPolicy(AccessPolicy.resolve(source: profile(2160, 3840, fps: .fps(60)), tier: .pro))
        #expect(sixty.frameRate == .fps(60))
        let thirty = try allowedPolicy(AccessPolicy.resolve(source: profile(2160, 3840, fps: .fps(30)), tier: .pro))
        #expect(thirty.frameRate == .fps(30))
        let twentyFour = try allowedPolicy(AccessPolicy.resolve(source: profile(1080, 1920, fps: .fps(24)), tier: .pro))
        #expect(twentyFour.frameRate == .fps(24))
        let oneTwenty = try allowedPolicy(AccessPolicy.resolve(source: profile(1080, 1920, fps: .fps(120)), tier: .pro))
        #expect(oneTwenty.frameRate == .fps(60))
    }

    @Test("Pro preserves 4K dimensions, removes watermark and has no duration cap")
    func proPolicy() throws {
        let policy = try allowedPolicy(AccessPolicy.resolve(
            source: profile(2160, 3840, fps: .fps(60), seconds: 3600), tier: .pro))
        #expect(policy.dimensions == (try PixelDimensions(width: 2160, height: 3840)))
        #expect(policy.requiresWatermark == false)
        #expect(policy.tier == .pro)
    }

    @Test("Free requires the watermark")
    func freeWatermark() throws {
        let policy = try allowedPolicy(AccessPolicy.resolve(source: profile(1080, 1920), tier: .free))
        #expect(policy.requiresWatermark)
    }

    @Test("Free 30-second boundary: exactly 30 s allowed, just above is gated")
    func freeDurationBoundary() throws {
        let exactly = SourceMediaProfile(
            displayDimensions: try PixelDimensions(width: 1080, height: 1920), frameRate: .fps(30),
            duration: try RationalTime(value: 18000, timescale: 600), hasUsableAudio: true)
        #expect(throws: Never.self) { try allowedPolicy(AccessPolicy.resolve(source: exactly, tier: .free)) }

        var justAbove = exactly
        justAbove.duration = try RationalTime(value: 18001, timescale: 600)
        #expect(AccessPolicy.resolve(source: justAbove, tier: .free)
            == .exceedsFreeDuration(limit: .seconds(30), sourceDuration: justAbove.duration))

        var justBelow = exactly
        justBelow.duration = try RationalTime(value: 29_999, timescale: 1000)
        #expect(throws: Never.self) { try allowedPolicy(AccessPolicy.resolve(source: justBelow, tier: .free)) }
    }

    @Test("Unknown access runs the Free policy")
    func unknownIsFree() {
        #expect(AccessState.notConfigured.effectiveTier == .free)
        #expect(AccessState.notLoaded.effectiveTier == .free)
        #expect(AccessState(level: .pro, provenance: .providerVerified).effectiveTier == .pro)
    }
}
