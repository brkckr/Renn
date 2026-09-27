import Foundation
import Testing
@testable import RENNDomain

@Suite("Decorative date stamp (01 P07)")
struct StampDateTests {
    @Test func frozenFormat() throws {
        #expect(try StampDate(year: 1998, month: 10, day: 19).text == "1998.10.19")
        #expect(try StampDate(year: 1, month: 1, day: 1).text == "0001.01.01")
        #expect(try StampDate(year: 9999, month: 12, day: 31).text == "9999.12.31")
    }

    @Test func leapYears() throws {
        #expect(throws: Never.self) { try StampDate(year: 2024, month: 2, day: 29) }
        #expect(throws: Never.self) { try StampDate(year: 2000, month: 2, day: 29) }
        #expect(throws: StampDate.ValidationError.dayOutOfRange) { try StampDate(year: 1900, month: 2, day: 29) }
        #expect(throws: StampDate.ValidationError.dayOutOfRange) { try StampDate(year: 2023, month: 2, day: 29) }
    }

    @Test func rangeValidation() {
        #expect(throws: StampDate.ValidationError.yearOutOfRange) { try StampDate(year: 0, month: 1, day: 1) }
        #expect(throws: StampDate.ValidationError.yearOutOfRange) { try StampDate(year: 10000, month: 1, day: 1) }
        #expect(throws: StampDate.ValidationError.monthOutOfRange) { try StampDate(year: 2026, month: 13, day: 1) }
        #expect(throws: StampDate.ValidationError.dayOutOfRange) { try StampDate(year: 2026, month: 4, day: 31) }
    }

    @Test func codableRoundTripIsTimeZoneIndependent() throws {
        let stamp = try StampDate(year: 2026, month: 9, day: 27)
        let data = try JSONEncoder().encode(stamp)
        let decoded = try JSONDecoder().decode(StampDate.self, from: data)
        #expect(decoded.text == "2026.09.27")
    }
}
