/// Output-space placement of the Free `shot by RENN` watermark (02 D07).
/// Bottom-right anchor, inset 4% of the short edge, width up to 28% of the short edge.
/// Values are visual starting points that still need legibility review at 720p.
public struct WatermarkLayout: Sendable, Equatable {
    public static let insetFraction = 0.04
    public static let maximumWidthFraction = 0.28

    /// Rectangle in output pixels, origin top-left.
    public struct Rect: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public let frame: Rect

    /// - Parameters:
    ///   - output: output dimensions.
    ///   - aspectRatio: rendered watermark width / height.
    ///   - reservedBottomRight: height of a bottom-right region to keep clear (e.g. a PiP
    ///     inset); the watermark moves above it instead of covering it.
    public init(output: PixelDimensions, aspectRatio: Double, reservedBottomRight: Double = 0) {
        let shortEdge = Double(output.shortEdge)
        let inset = (shortEdge * Self.insetFraction).rounded()
        let width = (shortEdge * Self.maximumWidthFraction).rounded()
        let height = (width / max(aspectRatio, 0.1)).rounded()
        frame = Rect(
            x: Double(output.width) - inset - width,
            y: Double(output.height) - inset - height - max(0, reservedBottomRight),
            width: width,
            height: height)
    }
}
