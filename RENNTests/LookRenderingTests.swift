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
        let prepared = try #require(
            LookLUTStore(manifestName: BundledLookCatalogProvider.developmentManifestName).lut(for: "dev.diagnostic"))
        #expect(prepared.dimension == 17)
        #expect(prepared.data.count == 17 * 17 * 17 * 4 * MemoryLayout<Float>.size)
        #expect(LookLUTStore(manifestName: BundledLookCatalogProvider.developmentManifestName).lut(for: "unknown.look") == nil)
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

    /// RGBA8 pixels of a `window`×`window` crop at the centre of a flat grey frame rendered at
    /// `side`×`side`. Core Image renders only the crop, so large outputs stay cheap.
    static func greyWindow(_ engine: RenderEngine, recipe: Recipe, side: Int, window: Int = 96) -> [UInt8] {
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        let image = engine.image(for: RenderEngine.FrameRequest(
            source: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: frame), orientation: .up,
            recipe: recipe, time: .zero, outputSize: frame.size, watermark: nil, watermarkFrame: nil))
        var bytes = [UInt8](repeating: 0, count: window * window * 4)
        let origin = (side - window) / 2
        engine.context.render(
            image, toBitmap: &bytes, rowBytes: window * 4,
            bounds: CGRect(x: origin, y: origin, width: window, height: window), format: .RGBA8,
            colorSpace: engine.outputColorSpace)
        return bytes
    }

    /// Correlation between horizontally adjacent red values: near 0 for per-pixel noise, higher for
    /// grain cells spanning several pixels.
    static func neighbourCorrelation(_ bytes: [UInt8], window: Int = 96) -> Double {
        var a: [Double] = [], b: [Double] = []
        for y in 0..<window {
            for x in 0..<(window - 1) {
                a.append(Double(bytes[(y * window + x) * 4]))
                b.append(Double(bytes[(y * window + x + 1) * 4]))
            }
        }
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var cov = 0.0, va = 0.0, vb = 0.0
        for (x, y) in zip(a, b) {
            cov += (x - ma) * (y - mb)
            va += (x - ma) * (x - ma)
            vb += (y - mb) * (y - mb)
        }
        return cov / max(1e-9, (va * vb).squareRoot())
    }

    @Test func grainCellsScaleWithTheFrameNotOutputPixels() throws {
        let engine = RenderEngine(luts: LookLUTStore(preloaded: [:]))
        let recipe = try Self.recipe(parameters: [LookParameter.grain: 0.3, LookParameter.grainSize: 1.4], intensity: 1)
        let small = Self.neighbourCorrelation(Self.greyWindow(engine, recipe: recipe, side: 540))
        let large = Self.neighbourCorrelation(Self.greyWindow(engine, recipe: recipe, side: 2160))
        // 2160 px frames get 4× larger cells than 540 px frames, so neighbours agree much more.
        #expect(large > small + 0.2, "neighbour correlation 540 px: \(small), 2160 px: \(large)")
    }

    @Test func grainChromaControlsColourGrain() throws {
        let engine = RenderEngine(luts: LookLUTStore(preloaded: [:]))
        func channelSpread(_ chroma: Double) throws -> Double {
            let recipe = try Self.recipe(
                parameters: [LookParameter.grain: 0.3, LookParameter.grainChroma: chroma], intensity: 1)
            let bytes = Self.greyWindow(engine, recipe: recipe, side: 1080)
            var total = 0
            for pixel in stride(from: 0, to: bytes.count, by: 4) {
                total += abs(Int(bytes[pixel]) - Int(bytes[pixel + 1])) + abs(Int(bytes[pixel + 1]) - Int(bytes[pixel + 2]))
            }
            return Double(total) / Double(bytes.count / 4)
        }
        let mono = try channelSpread(0)
        let colour = try channelSpread(1)
        #expect(mono <= 1, "monochrome grain keeps grey neutral (\(mono))")
        #expect(colour > 2, "colour grain separates the channels (\(colour))")
    }

    @Test func warmLUTShiftsBlueDownAndIntensityScalesIt() throws {
        let engine = RenderEngine(luts: LookLUTStore(manifestName: BundledLookCatalogProvider.developmentManifestName))
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
