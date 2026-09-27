/// Dual-Cam composition rules (01 P05, 05 V03): inset geometry, the common playable interval
/// of the two clean sources, and shared-audio ownership. Pure, so preview and export agree.

/// Output-space placement of the rounded PiP inset.
/// Baseline: ≈30% of canvas width, portrait 9:16, margin 4% of the short edge. The inset
/// corner is chosen before recording and never changes during a take.
public struct DualInsetLayout: Sendable, Equatable {
    public static let widthFraction = 0.30
    public static let marginFraction = 0.04
    public static let cornerRadiusFraction = 0.12
    /// Inset width / height (portrait 9:16 like the canvas).
    public static let aspectRatio = 9.0 / 16.0

    public let frame: WatermarkLayout.Rect
    public let cornerRadius: Double

    public init(canvas: PixelDimensions, corner: DualCameraLayout.Corner) {
        let width = (Double(canvas.width) * Self.widthFraction).rounded()
        let height = (width / Self.aspectRatio).rounded()
        let margin = (Double(canvas.shortEdge) * Self.marginFraction).rounded()
        let isLeft = corner == .topLeft || corner == .bottomLeft
        let isTop = corner == .topLeft || corner == .topRight
        frame = WatermarkLayout.Rect(
            x: isLeft ? margin : Double(canvas.width) - margin - width,
            y: isTop ? margin : Double(canvas.height) - margin - height,
            width: width,
            height: height)
        cornerRadius = (width * Self.cornerRadiusFraction).rounded()
    }

    /// Height to keep clear at the bottom-right for the Free watermark; 0 when the inset is elsewhere.
    public func reservedBottomRight(canvas: PixelDimensions) -> Double {
        guard frame.x + frame.width >= Double(canvas.width) / 2, frame.y >= Double(canvas.height) / 2 else { return 0 }
        return Double(canvas.height) - frame.y
    }
}

/// Timing of one Dual-Cam take on the shared capture clock.
public struct DualSourceTiming: Sendable, Equatable {
    /// Shortest usable common interval (half a second); shorter takes are not a valid
    /// project (05 V03). A development value pending product review.
    public static let minimumDuration = try! RationalTime(value: 1, timescale: 2)

    public enum TimingError: Error, Equatable, Sendable {
        case noCommonInterval
        case tooShort(RationalTime)
    }

    /// Composition time 0 on the shared clock.
    public let start: RationalTime
    public let duration: RationalTime
    /// Source-local time of composition time 0, per camera.
    public let rearOffset: RationalTime
    public let frontOffset: RationalTime

    /// - Parameters: each source's first-sample time on the shared capture clock and its duration.
    public init(
        rearStart: RationalTime, rearDuration: RationalTime,
        frontStart: RationalTime, frontDuration: RationalTime
    ) throws(TimingError) {
        let start = max(rearStart, frontStart)
        let end = min(rearStart + rearDuration, frontStart + frontDuration)
        guard end > start else { throw .noCommonInterval }
        let duration = end - start
        guard duration >= Self.minimumDuration else { throw .tooShort(duration) }
        self.start = start
        self.duration = duration
        rearOffset = start - rearStart
        frontOffset = start - frontStart
    }

    public func sourceTime(_ compositionTime: RationalTime, camera: DualCameraLayout.Camera) -> RationalTime {
        compositionTime + (camera == .rear ? rearOffset : frontOffset)
    }
}
