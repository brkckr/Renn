import CoreImage
import Foundation
import Testing
import RENNDomain
@testable import RENN

/// Film overlay stage with synthetic textures (the licensed pack is not in the repository).
/// Built-in Core Image filters only, so these run on the software renderer too.
@Suite("Film overlay rendering")
struct FilmOverlayRenderingTests {
    static let side = 64

    static func recipe(_ parameters: [String: Double]) throws -> Recipe {
        Recipe.initial(
            look: LookDefinition(
                id: "t.overlay", version: 1, family: "f", nameKey: "n", descriptionKey: "d",
                defaultIntensity: try #require(LookIntensity(1)), renderVersion: 1, isDevelopmentFixture: true,
                parameters: parameters),
            creationStamp: try StampDate(year: 2026, month: 9, day: 30), seed: 11)
    }

    static func grey(_ value: Double, width: Int = 96, height: Int = 54) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Centre pixel (RGB8) of a flat `base` frame through `engine`.
    static func centre(_ engine: RenderEngine, base: Double, parameters: [String: Double]) throws -> [Int] {
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        let image = engine.image(for: RenderEngine.FrameRequest(
            source: CIImage(color: CIColor(red: base, green: base, blue: base)).cropped(to: frame), orientation: .up,
            recipe: try recipe(parameters), time: .zero, outputSize: frame.size, watermark: nil, watermarkFrame: nil))
        var bytes = [UInt8](repeating: 0, count: 4)
        engine.context.render(
            image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: side / 2, y: side / 2, width: 1, height: 1),
            format: .RGBA8, colorSpace: engine.outputColorSpace)
        return bytes[0..<3].map(Int.init)
    }

    static func engine(_ textures: [OverlayTextureStore.Kind: [CIImage]]) -> RenderEngine {
        RenderEngine(luts: LookLUTStore(preloaded: [:]), overlays: OverlayTextureStore(preloaded: textures))
    }

    @Test func dustScreensLightSpecksOntoTheImage() throws {
        let engine = Self.engine([.dust: [Self.grey(0.5)]])
        let clean = try Self.centre(engine, base: 0, parameters: [:])
        let dusty = try Self.centre(engine, base: 0, parameters: [LookParameter.dust: 1])
        #expect(clean.allSatisfy { $0 <= 1 })
        #expect(dusty.allSatisfy { $0 > 100 }, "screen of mid-grey dust lifts black: \(dusty)")
    }

    @Test func burnMultipliesAndFadesWithStrength() throws {
        let engine = Self.engine([.burn: [Self.grey(0.5)]])
        let white = try Self.centre(engine, base: 1, parameters: [:])
        let burnt = try Self.centre(engine, base: 1, parameters: [LookParameter.burnEdges: 1])
        let light = try Self.centre(engine, base: 1, parameters: [LookParameter.burnEdges: 0.2])
        #expect(white.allSatisfy { $0 >= 254 })
        #expect(burnt[0] < light[0] && light[0] < white[0], "stronger burn is darker: \(burnt) < \(light) < \(white)")
    }

    @Test func missingTexturesLeaveTheImageUnchanged() throws {
        let engine = Self.engine([:])
        let all = [LookParameter.dust: 1.0, LookParameter.lightLeak: 1, LookParameter.burnEdges: 1]
        #expect(try Self.centre(engine, base: 0.4, parameters: all) == Self.centre(engine, base: 0.4, parameters: [:]))
    }

    @Test func coverTurnsLandscapeTexturesForPortraitFramesAndFillsThem() {
        let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let landscape = Self.grey(0.5, width: 3840, height: 2160)
        #expect(RenderEngine.cover(landscape, extent: portrait, zoom: 1.3, offsetX: 0.9, offsetY: 0.1, flipX: true).extent == portrait)
        #expect(RenderEngine.cover(landscape, extent: portrait, stretch: true).extent == portrait)
        let wide = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(RenderEngine.cover(landscape, extent: wide, flipY: true).extent == wide)
    }
}
