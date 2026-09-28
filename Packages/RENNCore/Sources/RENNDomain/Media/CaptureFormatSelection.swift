/// Single-camera capture format choice (05 V01/V02). Free captures a source suited to its
/// 720p/≤30 FPS output (up to 1080p30); Pro targets the highest device-reported configuration up
/// to 4K60. The format is chosen before recording and never switched or downgraded mid-take.
/// Candidates are sensor-orientation (landscape) facts reported by the device; "validated" in the
/// contract means device evidence per model, which the device test plan records.
public enum CaptureFormatSelection {
    public struct Candidate: Sendable, Equatable {
        public let index: Int
        public let dimensions: PixelDimensions
        public let maximumFrameRate: Double

        public init(index: Int, dimensions: PixelDimensions, maximumFrameRate: Double) {
            self.index = index
            self.dimensions = dimensions
            self.maximumFrameRate = maximumFrameRate
        }
    }

    public struct Choice: Sendable, Equatable {
        public let candidate: Candidate
        public let frameRate: FrameRate
    }

    public static func target(for tier: AccessTier) -> (longEdge: Int, framesPerSecond: Int32) {
        switch tier {
        case .free: (1920, 30)
        case .pro: (3840, 60)
        }
    }

    /// Largest format within the tier's target that sustains at least 30 FPS; its rate is the
    /// target rate when supported (60 for Pro), else 30. Among equal sizes, the higher usable rate
    /// wins, then the lower maximum rate (usually the less power-hungry format).
    public static func select(_ candidates: [Candidate], tier: AccessTier) -> Choice? {
        let target = target(for: tier)
        func usableRate(_ candidate: Candidate) -> Int32 {
            candidate.maximumFrameRate + 0.001 >= Double(target.framesPerSecond) ? target.framesPerSecond : 30
        }
        let eligible = candidates.filter { $0.maximumFrameRate + 0.001 >= 30 && $0.dimensions.longEdge <= target.longEdge }
        let best = eligible.min { lhs, rhs in
            if lhs.dimensions.longEdge != rhs.dimensions.longEdge { return lhs.dimensions.longEdge > rhs.dimensions.longEdge }
            if usableRate(lhs) != usableRate(rhs) { return usableRate(lhs) > usableRate(rhs) }
            if lhs.maximumFrameRate != rhs.maximumFrameRate { return lhs.maximumFrameRate < rhs.maximumFrameRate }
            return lhs.index < rhs.index
        }
        return best.map { Choice(candidate: $0, frameRate: .fps(usableRate($0))) }
    }
}
