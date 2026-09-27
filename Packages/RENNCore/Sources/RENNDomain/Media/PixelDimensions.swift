/// Display-oriented pixel size, measured after preferred transform and clean aperture (05 V01).
public struct PixelDimensions: Sendable, Hashable, Codable, CustomStringConvertible {
    public let width: Int
    public let height: Int

    public enum ValidationError: Error, Equatable, Sendable {
        case nonPositive
    }

    public init(width: Int, height: Int) throws(ValidationError) {
        guard width > 0, height > 0 else { throw .nonPositive }
        self.width = width
        self.height = height
    }

    public var shortEdge: Int { Swift.min(width, height) }
    public var longEdge: Int { Swift.max(width, height) }
    public var isPortrait: Bool { height > width }

    public var description: String { "\(width)×\(height)" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                width: try container.decode(Int.self, forKey: .width),
                height: try container.decode(Int.self, forKey: .height))
        } catch is ValidationError {
            throw DecodingError.dataCorruptedError(
                forKey: .width, in: container, debugDescription: "Dimensions must be positive")
        }
    }

    private enum CodingKeys: String, CodingKey { case width, height }
}
