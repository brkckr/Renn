import CoreImage
import Foundation
import Testing
import RENNDomain
@testable import RENN

/// Render version 1 Look graph on the Simulator GPU path: bundled LUT resolution, the LUT
/// stage's color handling, and intensity scaling. Pixel values are compared with a small
/// tolerance for 8-bit output rounding.
@Suite("Look rendering")
struct LookRenderingTests {
    static let size = 16

    static func recipe(parameters: [String: Double], intensity: Double) throws -> Recipe {
        Recipe.initial(
            look: LookDefinition(
                id: "dev.diagnostic", version: 1, family: "diagnostic", nameKey: "n", descriptionKey: "d",
                defaultIntensity: try #require(LookIntensity(intensity)), renderVersion: 1,
                isDevelopmentFixture: true, lut: "dev_warm", parameters: parameters),
            creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 7)
    }

    /// Centre pixel (RGBA8) of a flat colour rendered through `engine`.
    static func centre(_ engine: RenderEngine, recipe: Recipe, color: CIColor) -> [Int] {
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let image = engine.image(for: RenderEngine.FrameRequest(
            source: CIImage(color: color).cropped(to: bounds), orientation: .up, recipe: recipe, time: .zero,
            outputSize: bounds.size, watermark: nil, watermarkFrame: nil))
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        engine.context.render(
            image, toBitmap: &bytes, rowBytes: size * 4, bounds: bounds, format: .RGBA8,
            colorSpace: engine.outputColorSpace)
        let offset = ((size / 2) * size + size / 2) * 4
        return bytes[offset..<offset + 3].map(Int.init)
    }

    @Test func bundledCatalogResolvesTheDevelopmentLUT() throws {
        let prepared = try #require(LookLUTStore().lut(for: "dev.diagnostic"))
        #expect(prepared.dimension == 17)
        #expect(prepared.data.count == 17 * 17 * 17 * 4 * MemoryLayout<Float>.size)
        #expect(LookLUTStore().lut(for: "unknown.look") == nil)
    }

    @Test func identityLUTLeavesColoursUnchanged() throws {
        let identity = try #require(LookLUTStore.prepare(.identity(size: 17)))
        let engine = RenderEngine(luts: LookLUTStore(preloaded: ["dev.diagnostic": identity]))
        let color = CIColor(red: 0.6, green: 0.4, blue: 0.25)
        let plain = Self.centre(engine, recipe: try Self.recipe(parameters: [:], intensity: 1), color: color)
        let graded = Self.centre(engine, recipe: try Self.recipe(parameters: [LookParameter.lutMix: 1], intensity: 1), color: color)
        for (a, b) in zip(plain, graded) {
            #expect(abs(a - b) <= 2, "Identity LUT round-trips through the sRGB cube space: \(plain) vs \(graded)")
        }
    }

    @Test func warmLUTShiftsBlueDownAndIntensityScalesIt() throws {
        let engine = RenderEngine()
        let grey = CIColor(red: 0.5, green: 0.5, blue: 0.5)
        let lutOnly = [LookParameter.lutMix: 1.0]
        let off = Self.centre(engine, recipe: try Self.recipe(parameters: lutOnly, intensity: 0), color: grey)
        let half = Self.centre(engine, recipe: try Self.recipe(parameters: lutOnly, intensity: 0.5), color: grey)
        let full = Self.centre(engine, recipe: try Self.recipe(parameters: lutOnly, intensity: 1), color: grey)
        #expect(full[0] > full[2] + 10, "DEV warm LUT: red above blue on neutral grey (\(full))")
        #expect(abs(off[0] - off[2]) <= 2, "Intensity 0 is a passthrough (\(off))")
        #expect(half[2] < off[2] && half[2] > full[2], "Half intensity lies between (\(off) → \(half) → \(full))")
    }
}
