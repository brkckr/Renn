/// Output-space placement of the decorative on-screen indicators (02 D06).
///
/// Anchors: REC top-left, battery top-right, PLAY bottom-left, date bottom-right, margin 5% of
/// the short edge. Reserved rectangles (Free watermark, Dual-Cam inset) are never covered:
/// top indicators move down, bottom indicators move up, until they are clear. If that is not
/// possible within the frame, the indicator is drawn smaller (not below 70%) and the layout is
/// flagged for visual review. A selected indicator is never silently omitted.
///
/// Owner-approved free placement (2026-09-30): an indicator with a dragged position is centred
/// there instead, kept inside the margins, and nudged to the nearest clear spot when it would
/// cover a reserved rectangle or an indicator placed before it.
public enum IndicatorLayout {
    public enum Kind: String, Sendable, CaseIterable {
        case rec, battery, play, date
    }

    public struct Placed: Sendable, Equatable {
        public let kind: Kind
        public let frame: WatermarkLayout.Rect
        /// 1 = baseline size; smaller when space was tight.
        public let scale: Double
    }

    public struct Result: Sendable, Equatable {
        public let indicators: [Placed]
        /// True when an indicator had to shrink; the fixture needs visual review (02 D06).
        public let needsVisualReview: Bool
    }

    public static let marginFraction = 0.05
    public static let heightFraction = 0.045
    public static let minimumScale = 0.7

    /// Width in multiples of the indicator height (text length of the frozen glyphs).
    static func aspect(_ kind: Kind) -> Double {
        switch kind {
        case .rec: 3.2
        case .play: 3.6
        case .battery: 2.2
        case .date: 7.4
        }
    }

    public static func resolve(
        output: PixelDimensions,
        settings: IndicatorSettings,
        reserved: [WatermarkLayout.Rect] = []
    ) -> Result {
        let width = Double(output.width)
        let height = Double(output.height)
        let short = Double(output.shortEdge)
        let margin = (short * marginFraction).rounded()
        var placed: [Placed] = []
        var needsReview = false

        let selected: [Kind] = [
            settings.showsRec ? .rec : nil,
            settings.showsBattery ? .battery : nil,
            settings.showsPlay ? .play : nil,
            settings.showsDate ? .date : nil,
        ].compactMap { $0 }

        for kind in selected {
            if let position = settings.positions[kind.rawValue],
               let frame = free(kind, at: position, width: width, height: height, short: short, margin: margin,
                                obstacles: reserved + placed.map(\.frame)) {
                placed.append(Placed(kind: kind, frame: frame, scale: 1))
                continue
            }
            var scale = 1.0
            var result: WatermarkLayout.Rect?
            while result == nil {
                let h = (short * heightFraction * scale).rounded()
                let w = (h * aspect(kind)).rounded()
                let isTop = kind == .rec || kind == .battery
                let isLeft = kind == .rec || kind == .play
                let x = isLeft ? margin : width - margin - w
                var y = isTop ? margin : height - margin - h
                let obstacles = reserved + placed.map(\.frame)
                // Step away from the edge past any obstacle, staying inside the frame's own half.
                var moved = true
                while moved {
                    moved = false
                    let candidate = WatermarkLayout.Rect(x: x, y: y, width: w, height: h)
                    if let hit = obstacles.first(where: { intersects($0, candidate) }) {
                        y = isTop ? hit.y + hit.height + margin / 2 : hit.y - h - margin / 2
                        moved = true
                    }
                }
                let fitsVertically = isTop ? y + h <= height / 2 : y >= height / 2
                if fitsVertically, y >= 0, y + h <= height {
                    result = WatermarkLayout.Rect(x: x, y: y, width: w, height: h)
                } else if scale > minimumScale + 1e-9 {
                    scale = max(minimumScale, scale - 0.1)
                    needsReview = true
                } else {
                    // Keep it visible at the minimum size in its corner; flag for review.
                    needsReview = true
                    result = WatermarkLayout.Rect(x: x, y: isTop ? margin : height - margin - h, width: w, height: h)
                }
            }
            placed.append(Placed(kind: kind, frame: result!, scale: scale))
        }
        return Result(indicators: placed, needsVisualReview: needsReview)
    }

    /// Size of an indicator at the baseline scale in this output.
    public static func size(_ kind: Kind, output: PixelDimensions) -> (width: Double, height: Double) {
        let h = (Double(output.shortEdge) * heightFraction).rounded()
        return (width: (h * aspect(kind)).rounded(), height: h)
    }

    /// A dragged indicator at baseline size: centred on its position, clamped inside the margins,
    /// then moved to the closest clear candidate (rings of half-margin steps around the target).
    /// Nil when nothing within the frame is clear; the caller then uses the baseline anchor.
    private static func free(
        _ kind: Kind, at position: IndicatorPosition, width: Double, height: Double, short: Double,
        margin: Double, obstacles: [WatermarkLayout.Rect]
    ) -> WatermarkLayout.Rect? {
        let h = (short * heightFraction).rounded()
        let w = (h * aspect(kind)).rounded()
        guard w + 2 * margin <= width, h + 2 * margin <= height else { return nil }
        func clamped(_ x: Double, _ y: Double) -> WatermarkLayout.Rect {
            WatermarkLayout.Rect(
                x: min(max(margin, x.rounded()), width - margin - w),
                y: min(max(margin, y.rounded()), height - margin - h),
                width: w, height: h)
        }
        let target = clamped(position.x * width - w / 2, position.y * height - h / 2)
        let clear: (WatermarkLayout.Rect) -> Bool = { candidate in !obstacles.contains { intersects($0, candidate) } }
        if clear(target) { return target }
        let step = max(1, (margin / 2).rounded())
        let rings = Int((max(width, height) / step).rounded(.up))
        for ring in 1...max(1, rings) {
            let d = Double(ring) * step
            // Vertical moves first (indicators read as rows), then horizontal, then diagonals.
            let offsets: [(Double, Double)] = [(0, -d), (0, d), (-d, 0), (d, 0), (-d, -d), (d, -d), (-d, d), (d, d)]
            let candidates = offsets.map { clamped(target.x + $0.0, target.y + $0.1) }
            if let hit = candidates.first(where: clear) { return hit }
        }
        return nil
    }

    static func intersects(_ a: WatermarkLayout.Rect, _ b: WatermarkLayout.Rect) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }
}
