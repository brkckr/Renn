import Foundation
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

    // MARK: Free placement (owner-approved, 2026-09-30)

    @Test func draggedIndicatorIsCentredOnItsPosition() throws {
        let output = try PixelDimensions(width: 1080, height: 1920)
        var chosen = settings(true, false, false, false)
        chosen.positions = ["rec": IndicatorPosition(x: 0.5, y: 0.5)]
        let frame = try #require(IndicatorLayout.resolve(output: output, settings: chosen).indicators.first?.frame)
        #expect(abs(frame.x + frame.width / 2 - 540) <= 1)
        #expect(abs(frame.y + frame.height / 2 - 960) <= 1)
    }

    @Test func draggedIndicatorStaysInsideTheMargins() throws {
        let output = try PixelDimensions(width: 1080, height: 1920)
        let margin = (1080 * 0.05).rounded()
        var chosen = settings(false, false, false, true)
        chosen.positions = ["date": IndicatorPosition(x: 1, y: 0)]
        let frame = try #require(IndicatorLayout.resolve(output: output, settings: chosen).indicators.first?.frame)
        #expect(frame.x + frame.width == 1080 - margin)
        #expect(frame.y == margin)
    }

    @Test func draggedIndicatorNeverCoversTheWatermarkOrAnotherIndicator() throws {
        let output = try PixelDimensions(width: 720, height: 1280)
        let watermark = WatermarkLayout(output: output, aspectRatio: 4).frame
        var chosen = settings(true, true, true, true)
        // Everything dragged onto the watermark's centre.
        let centre = IndicatorPosition(
            x: (watermark.x + watermark.width / 2) / 720, y: (watermark.y + watermark.height / 2) / 1280)
        chosen.positions = ["rec": centre, "play": centre, "battery": centre, "date": centre]
        let result = IndicatorLayout.resolve(output: output, settings: chosen, reserved: [watermark])
        #expect(result.indicators.count == 4, "No selected indicator is dropped")
        let frames = result.indicators.map(\.frame)
        for (index, frame) in frames.enumerated() {
            #expect(!IndicatorLayout.intersects(frame, watermark))
            #expect(frame.x >= 0 && frame.y >= 0 && frame.x + frame.width <= 720 && frame.y + frame.height <= 1280)
            for other in frames[(index + 1)...] {
                #expect(!IndicatorLayout.intersects(frame, other))
            }
        }
    }

    @Test func positionsAreResolutionIndependent() throws {
        var chosen = settings(false, true, false, false)
        chosen.positions = ["play": IndicatorPosition(x: 0.3, y: 0.7)]
        for (w, h) in [(720, 1280), (1080, 1920), (2160, 3840)] {
            let output = try PixelDimensions(width: w, height: h)
            let frame = try #require(IndicatorLayout.resolve(output: output, settings: chosen).indicators.first?.frame)
            #expect(abs((frame.x + frame.width / 2) / Double(w) - 0.3) < 0.01)
            #expect(abs((frame.y + frame.height / 2) / Double(h) - 0.7) < 0.01)
        }
    }

    @Test func settingsWithoutPositionsKeepTheBaselineAndTheirEncoding() throws {
        let plain = settings(true, true, true, true)
        let data = try JSONEncoder().encode(plain)
        #expect(!String(decoding: data, as: UTF8.self).contains("positions"), "Old recipes encode exactly as before")
        let decoded = try JSONDecoder().decode(IndicatorSettings.self, from: data)
        #expect(decoded == plain && decoded.positions.isEmpty)

        var dragged = plain
        dragged.positions = ["date": IndicatorPosition(x: 0.25, y: 0.4)]
        let roundTrip = try JSONDecoder().decode(IndicatorSettings.self, from: JSONEncoder().encode(dragged))
        #expect(roundTrip == dragged)
    }

    @Test func positionsAreClampedWhenCreatedOrDecoded() throws {
        #expect(IndicatorPosition(x: -2, y: 7) == IndicatorPosition(x: 0, y: 1))
        #expect(IndicatorPosition(x: .nan, y: .infinity) == IndicatorPosition(x: 0.5, y: 0.5))
        let decoded = try JSONDecoder().decode(IndicatorPosition.self, from: Data(#"{"x":1.5,"y":-0.2}"#.utf8))
        #expect(decoded == IndicatorPosition(x: 1, y: 0))
    }
}
