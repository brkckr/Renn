import Foundation
import Testing
@testable import RENNDomain

@Suite("Rational time and frame rate")
struct TimeTests {
    @Test func rejectsZeroTimescale() {
        #expect(throws: RationalTime.ValidationError.nonPositiveTimescale) {
            try RationalTime(value: 1, timescale: 0)
        }
        #expect(throws: RationalTime.ValidationError.nonPositiveTimescale) {
            try RationalTime(value: 1, timescale: -600)
        }
    }

    @Test func equalityAcrossTimescales() throws {
        let a = try RationalTime(value: 18000, timescale: 600)
        let b = RationalTime.seconds(30)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
    }

    @Test func comparisonIsExactForLargeValues() throws {
        let a = try RationalTime(value: Int64.max - 1, timescale: Int32.max)
        let b = try RationalTime(value: Int64.max, timescale: Int32.max)
        #expect(a < b)
    }

    @Test func frameRateReduces() throws {
        #expect(try FrameRate(frames: 60, perSeconds: 2) == .fps(30))
        #expect(throws: FrameRate.ValidationError.nonPositiveComponent) { try FrameRate(frames: 0) }
    }

    @Test func decodingRejectsInvalidTimescale() {
        let json = Data(#"{"value": 10, "timescale": 0}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RationalTime.self, from: json) }
    }
}
