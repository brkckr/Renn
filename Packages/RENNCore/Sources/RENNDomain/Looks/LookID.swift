/// Stable Look identifier, independent of localized display names (08 I01).
public struct LookID: Sendable, Hashable, Codable, Identifiable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public var id: String { rawValue }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// Normalized Look intensity 0...1. Zero disables the Look's color/artifact contribution;
/// one is the catalog maximum (01 P04). Non-finite input is rejected, not clamped.
public struct LookIntensity: Sendable, Hashable, Codable {
    public let value: Double

    public init?(_ value: Double) {
        guard value.isFinite else { return nil }
        self.value = Swift.min(1, Swift.max(0, value))
    }

    public static let off = LookIntensity(0)!
    public static let maximum = LookIntensity(1)!

    public var isOff: Bool { value == 0 }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let intensity = LookIntensity(try container.decode(Double.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Non-finite intensity")
        }
        self = intensity
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
