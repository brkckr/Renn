/// Exact media time as an integer value over a positive timescale (05 V07).
/// Domain code never stores media time as floating-point seconds.
public struct RationalTime: Sendable, Hashable, Codable, CustomStringConvertible {
    public let value: Int64
    public let timescale: Int32

    public enum ValidationError: Error, Equatable, Sendable {
        case nonPositiveTimescale
    }

    public init(value: Int64, timescale: Int32) throws(ValidationError) {
        guard timescale > 0 else { throw .nonPositiveTimescale }
        self.value = value
        self.timescale = timescale
    }

    public static func seconds(_ seconds: Int64) -> RationalTime {
        // A timescale of 1 is always valid.
        try! RationalTime(value: seconds, timescale: 1)
    }

    public static let zero = RationalTime.seconds(0)

    /// Approximate seconds for display and bucketing only; never for timing decisions.
    public var approximateSeconds: Double { Double(value) / Double(timescale) }

    public var description: String { "\(value)/\(timescale)" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(Int64.self, forKey: .value)
        let timescale = try container.decode(Int32.self, forKey: .timescale)
        do {
            try self.init(value: value, timescale: timescale)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .timescale, in: container, debugDescription: "Timescale must be positive")
        }
    }

    private enum CodingKeys: String, CodingKey { case value, timescale }
}

extension RationalTime: Comparable {
    public static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        compare(lhs, rhs) < 0
    }

    public static func == (lhs: RationalTime, rhs: RationalTime) -> Bool {
        compare(lhs, rhs) == 0
    }

    public func hash(into hasher: inout Hasher) {
        // Equal rational values must hash equally: hash the reduced fraction.
        let divisor = RationalTime.gcd(Swift.abs(value), Int64(timescale))
        hasher.combine(value / divisor)
        hasher.combine(Int64(timescale) / divisor)
    }

    /// Exact cross-multiplication comparison without overflow.
    private static func compare(_ lhs: RationalTime, _ rhs: RationalTime) -> Int {
        let left = lhs.value.multipliedFullWidth(by: Int64(rhs.timescale))
        let right = rhs.value.multipliedFullWidth(by: Int64(lhs.timescale))
        if left.high != right.high { return left.high < right.high ? -1 : 1 }
        if left.low != right.low { return left.low < right.low ? -1 : 1 }
        return 0
    }

    static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return Swift.max(a, 1)
    }
}
