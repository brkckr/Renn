/// Chooses the front/rear capture format pair for Dual-Cam (05 V02/V03).
///
/// The M04 prototype targets 1080p30 on both cameras for both tiers ("start the prototype
/// with 1080p30; not a commercial Pro ceiling"). Higher Dual-Cam ceilings are added only after
/// device validation and are disclosed before recording. The session's hardware cost is
/// checked at runtime by the capture adapter; this rule only picks candidates.
public enum DualFormatSelection {
    /// Sensor-orientation (landscape) format facts as reported by the device.
    public struct Candidate: Sendable, Equatable {
        public let index: Int
        public let dimensions: PixelDimensions
        public let maximumFrameRate: Double
        public let isMultiCamSupported: Bool

        public init(index: Int, dimensions: PixelDimensions, maximumFrameRate: Double, isMultiCamSupported: Bool) {
            self.index = index
            self.dimensions = dimensions
            self.maximumFrameRate = maximumFrameRate
            self.isMultiCamSupported = isMultiCamSupported
        }
    }

    public struct Pair: Sendable, Equatable {
        // Built only by `select`.
        public let rear: Candidate
        public let front: Candidate
        public let frameRate: FrameRate
    }

    public static let targetLongEdge = 1920
    public static let targetFrameRate = FrameRate.fps(30)

    public static func select(rear: [Candidate], front: [Candidate]) -> Pair? {
        guard let rearPick = best(rear), let frontPick = best(front) else { return nil }
        return Pair(rear: rearPick, front: frontPick, frameRate: targetFrameRate)
    }

    /// Largest multi-cam format not above the target that sustains the target rate; among equals,
    /// the lowest maximum rate (typically the less power-hungry, non-high-speed format).
    static func best(_ candidates: [Candidate]) -> Candidate? {
        let target = targetFrameRate.approximateFPS
        return candidates
            .filter { $0.isMultiCamSupported && $0.maximumFrameRate + 0.001 >= target && $0.dimensions.longEdge <= targetLongEdge }
            .min { lhs, rhs in
                if lhs.dimensions.longEdge != rhs.dimensions.longEdge { return lhs.dimensions.longEdge > rhs.dimensions.longEdge }
                if lhs.maximumFrameRate != rhs.maximumFrameRate { return lhs.maximumFrameRate < rhs.maximumFrameRate }
                return lhs.index < rhs.index
            }
    }
}
