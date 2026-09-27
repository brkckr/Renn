/// Resolved output rules for one export, snapshotted at job start (01 P08, 05 V01).
public struct OutputPolicy: Sendable, Equatable, Codable {
    public var tier: AccessTier
    public var dimensions: PixelDimensions
    public var frameRate: FrameRate
    public var requiresWatermark: Bool

    public init(tier: AccessTier, dimensions: PixelDimensions, frameRate: FrameRate, requiresWatermark: Bool) {
        self.tier = tier
        self.dimensions = dimensions
        self.frameRate = frameRate
        self.requiresWatermark = requiresWatermark
    }
}

public enum OutputPolicyResolution: Sendable, Equatable {
    case allowed(OutputPolicy)
    /// Free source longer than the Free limit: offer Pro or another source.
    /// No automatic trim and no trim editor (01 P08).
    case exceedsFreeDuration(limit: RationalTime, sourceDuration: RationalTime)
}

/// Pure effective-output rules from entitlement and source (04 A04 AccessPolicy).
public enum AccessPolicy {
    /// Free maximum duration: rational 30 seconds.
    public static let freeMaximumDuration = RationalTime.seconds(30)
    public static let freeMaximumShortEdge = 720
    public static let freeMaximumLongEdge = 1280
    public static let freeMaximumFPS: Int32 = 30
    /// Pro keeps supported source cadence up to the tested 60-class ceiling.
    /// This is an engineering capability ceiling (no 120 FPS output in V1), not a commercial cap.
    public static let proMaximumFPS: Int32 = 60

    public static func resolve(source: SourceMediaProfile, tier: AccessTier) -> OutputPolicyResolution {
        switch tier {
        case .free:
            if source.duration > freeMaximumDuration {
                return .exceedsFreeDuration(limit: freeMaximumDuration, sourceDuration: source.duration)
            }
            return .allowed(OutputPolicy(
                tier: .free,
                dimensions: freeDimensions(for: source.displayDimensions),
                frameRate: source.frameRate.limited(toMaximumFPS: freeMaximumFPS),
                requiresWatermark: true))
        case .pro:
            return .allowed(OutputPolicy(
                tier: .pro,
                dimensions: encoderAligned(source.displayDimensions),
                frameRate: source.frameRate.limited(toMaximumFPS: proMaximumFPS),
                requiresWatermark: false))
        }
    }

    /// Fits within short edge <= 720 and long edge <= 1280, preserving aspect with exact
    /// integer math, never upscaling, then rounding down to even dimensions.
    /// 3840x2160 -> 1280x720, 2160x3840 -> 720x1280, 1080x1080 -> 720x720.
    public static func freeDimensions(for source: PixelDimensions) -> PixelDimensions {
        let short = source.shortEdge
        let long = source.longEdge
        guard short > freeMaximumShortEdge || long > freeMaximumLongEdge else {
            return encoderAligned(source)
        }
        // Pick the tighter constraint: scale = 720/short or 1280/long, whichever is smaller.
        // 720/short <= 1280/long  <=>  720 * long <= 1280 * short
        let (numerator, denominator): (Int, Int) =
            freeMaximumShortEdge * long <= freeMaximumLongEdge * short
            ? (freeMaximumShortEdge, short)
            : (freeMaximumLongEdge, long)
        let width = source.width * numerator / denominator
        let height = source.height * numerator / denominator
        return evenRoundedDown(width: width, height: height)
    }

    /// Pro preserves display dimensions with only the even alignment encoders require.
    public static func encoderAligned(_ source: PixelDimensions) -> PixelDimensions {
        evenRoundedDown(width: source.width, height: source.height)
    }

    private static func evenRoundedDown(width: Int, height: Int) -> PixelDimensions {
        let evenWidth = Swift.max(2, width - width % 2)
        let evenHeight = Swift.max(2, height - height % 2)
        return try! PixelDimensions(width: evenWidth, height: evenHeight)
    }
}
