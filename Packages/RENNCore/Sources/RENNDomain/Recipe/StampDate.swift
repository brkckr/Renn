/// Decorative on-screen date: Gregorian date-only components with frozen `YYYY.MM.DD`
/// text. Time zones never change an existing stamp (01 P07, 02 D06).
public struct StampDate: Sendable, Hashable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public enum ValidationError: Error, Equatable, Sendable {
        case yearOutOfRange
        case monthOutOfRange
        case dayOutOfRange
    }

    public init(year: Int, month: Int, day: Int) throws(ValidationError) {
        guard (1...9999).contains(year) else { throw .yearOutOfRange }
        guard (1...12).contains(month) else { throw .monthOutOfRange }
        guard (1...StampDate.daysIn(month: month, year: year)).contains(day) else { throw .dayOutOfRange }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Frozen stamp text, independent of locale and time zone.
    public var text: String {
        "\(StampDate.pad(year, 4)).\(StampDate.pad(month, 2)).\(StampDate.pad(day, 2))"
    }

    public var description: String { text }

    /// Proleptic Gregorian leap-year rule.
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: Swift.max(0, width - digits.count)) + digits
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                year: try container.decode(Int.self, forKey: .year),
                month: try container.decode(Int.self, forKey: .month),
                day: try container.decode(Int.self, forKey: .day))
        } catch is ValidationError {
            throw DecodingError.dataCorruptedError(forKey: .year, in: container, debugDescription: "Invalid stamp date")
        }
    }

    private enum CodingKeys: String, CodingKey { case year, month, day }
}
