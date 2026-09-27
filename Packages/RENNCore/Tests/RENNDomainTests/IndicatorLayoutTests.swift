import Testing
@testable import RENNDomain

@Suite("Indicator layout and collisions (02 D06/D07)")
struct IndicatorLayoutTests {
    private let stamp = try! StampDate(year: 1998, month: 10, day: 19)

    private func settings(_ rec: Bool, _ play: Bool, _ battery: Bool, _ date: Bool) -> IndicatorSettings {
        IndicatorSettings(showsRec: rec, showsPlay: play, showsBattery: battery, showsDate: date, stampDate: stamp)
    }

    @Test("All 16 combinations place exactly the selected indicators without overlap",
          arguments: 0..<16)
    func allCombinations(mask: Int) throws {
        let output = try PixelDimensions(width: 720, height: 1280)
        let watermark = WatermarkLayout(output: output, aspectRatio: 4).frame
        let chosen = settings(mask & 1 != 0, mask & 2 != 0, mask & 4 != 0, mask & 8 != 0)
        let result = IndicatorLayout.resolve(output: output, settings: chosen, reserved: [watermark])
        #expect(result.indicators.count == mask.nonzeroBitCount)
        let frames = result.indicators.map(\.frame)
        for (index, frame) in frames.enumerated() {
            #expect(!IndicatorLayout.intersects(frame, watermark), "Never covers the watermark")
            #expect(frame.x >= 0 && frame.y >= 0 && frame.x + frame.width <= 720 && frame.y + frame.height <= 1280)
            for other in frames[(index + 1)...] {
                #expect(!IndicatorLayout.intersects(frame, other))
            }
        }
    }

    @Test func baselineAnchors() throws {
        let output = try PixelDimensions(width: 1080, height: 1920)
        let result = IndicatorLayout.resolve(output: output, settings: settings(true, true, true, true))
        let byKind = Dictionary(uniqueKeysWithValues: result.indicators.map { ($0.kind, $0.frame) })
        let margin = (1080 * 0.05).rounded()
        #expect(byKind[.rec]!.x == margin && byKind[.rec]!.y == margin)
        #expect(byKind[.battery]!.x + byKind[.battery]!.width == 1080 - margin)
        #expect(byKind[.play]!.y + byKind[.play]!.height == 1920 - margin)
        #expect(byKind[.date]!.x + byKind[.date]!.width == 1080 - margin)
        #expect(!result.needsVisualReview)
    }

    @Test func dateMovesAboveTheFreeWatermark() throws {
        let output = try PixelDimensions(width: 720, height: 1280)
        let watermark = WatermarkLayout(output: output, aspectRatio: 4).frame
        let result = IndicatorLayout.resolve(output: output, settings: settings(false, false, false, true), reserved: [watermark])
        let date = try #require(result.indicators.first?.frame)
        #expect(date.y + date.height <= watermark.y, "Date sits above the watermark reservation")
    }

    @Test func proWithoutWatermarkKeepsDateInTheCorner() throws {
        let output = try PixelDimensions(width: 720, height: 1280)
        let result = IndicatorLayout.resolve(output: output, settings: settings(false, false, false, true))
        let date = try #require(result.indicators.first?.frame)
        #expect(date.y + date.height == 1280 - (720 * 0.05).rounded())
    }

    @Test func pipInEveryCornerIsNeverCovered() throws {
        let output = try PixelDimensions(width: 1080, height: 1920)
        let insetWidth = 1080 * 0.30
        let insetHeight = insetWidth * 16 / 9
        let margin = 1080 * 0.04
        let corners = [
            WatermarkLayout.Rect(x: margin, y: margin, width: insetWidth, height: insetHeight),
            WatermarkLayout.Rect(x: 1080 - margin - insetWidth, y: margin, width: insetWidth, height: insetHeight),
            WatermarkLayout.Rect(x: margin, y: 1920 - margin - insetHeight, width: insetWidth, height: insetHeight),
            WatermarkLayout.Rect(x: 1080 - margin - insetWidth, y: 1920 - margin - insetHeight, width: insetWidth, height: insetHeight),
        ]
        for pip in corners {
            let result = IndicatorLayout.resolve(output: output, settings: settings(true, true, true, true), reserved: [pip])
            #expect(result.indicators.count == 4)
            for indicator in result.indicators {
                #expect(!IndicatorLayout.intersects(indicator.frame, pip))
            }
        }
    }

    @Test func tinyOutputShrinksAndFlagsForReviewButKeepsEverything() throws {
        let output = try PixelDimensions(width: 160, height: 90)
        let blocker = WatermarkLayout.Rect(x: 0, y: 0, width: 160, height: 90)
        let result = IndicatorLayout.resolve(output: output, settings: settings(true, true, true, true), reserved: [blocker])
        #expect(result.indicators.count == 4, "Selected indicators are never silently omitted")
        #expect(result.needsVisualReview)
        #expect(result.indicators.allSatisfy { $0.scale >= IndicatorLayout.minimumScale })
    }
}
