/// Rational frame cadence, e.g. 30000/1001 for 29.97 FPS (05 V01).
public struct FrameRate: Sendable, Hashable, Codable, CustomStringConvertible {
    /// Frames per `seconds` seconds.
    public let frames: Int32
    public let seconds: Int32

    public enum ValidationError: Error, Equatable, Sendable {
        case nonPositiveComponent
    }

    public init(frames: Int32, perSeconds seconds: Int32 = 1) throws(ValidationError) {
        guard frames > 0, seconds > 0 else { throw .nonPositiveComponent }
        let divisor = FrameRate.gcd(frames, seconds)
        self.frames = frames / divisor
        self.seconds = seconds / divisor
    }

    public static func fps(_ value: Int32) -> FrameRate { try! FrameRate(frames: value) }
    public static let ntsc23_976 = try! FrameRate(frames: 24000, perSeconds: 1001)
    public static let ntsc29_97 = try! FrameRate(frames: 30000, perSeconds: 1001)
    public static let ntsc59_94 = try! FrameRate(frames: 60000, perSeconds: 1001)

    public var approximateFPS: Double { Double(frames) / Double(seconds) }

    public var description: String {
        seconds == 1 ? "\(frames)" : "\(frames)/\(seconds)"
    }

    /// Limits the cadence to `maximumFPS` by keeping every n-th source frame, so
    /// 59.94 -> 29.97, 60 -> 30, 50 -> 25 and 120 -> 30 (for a 30 ceiling). Rates at or
    /// below the ceiling are preserved. Rates within `tolerance` above the ceiling (VFR
    /// averaging noise such as 30.02) resolve to the ceiling itself rather than halving.
    /// Motion is never interpolated (01 P08, 05 V01).
    public func limited(toMaximumFPS maximumFPS: Int32, tolerance: Double = 0.005) -> FrameRate {
        precondition(maximumFPS > 0)
        let maximum = Int64(maximumFPS)
        // frames/seconds <= maximum  <=>  frames <= maximum * seconds
        if Int64(frames) <= maximum * Int64(seconds) { return self }
        if approximateFPS <= Double(maximumFPS) * (1 + tolerance) { return .fps(maximumFPS) }
        // Smallest integer divisor n with frames / (seconds * n) <= maximum.
        let denominator = maximum * Int64(seconds)
        let divisor = (Int64(frames) + denominator - 1) / denominator
        return try! FrameRate(frames: frames, perSeconds: Int32(Int64(seconds) * divisor))
    }

    private static func gcd(_ a: Int32, _ b: Int32) -> Int32 {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                frames: try container.decode(Int32.self, forKey: .frames),
                perSeconds: try container.decode(Int32.self, forKey: .seconds))
        } catch is ValidationError {
            throw DecodingError.dataCorruptedError(
                forKey: .frames, in: container, debugDescription: "Frame rate components must be positive")
        }
    }

    private enum CodingKeys: String, CodingKey { case frames, seconds }
}
