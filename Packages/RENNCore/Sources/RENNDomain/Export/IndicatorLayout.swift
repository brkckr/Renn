/// Output-space placement of the decorative on-screen indicators (02 D06).
///
/// Anchors: REC top-left, battery top-right, PLAY bottom-left, date bottom-right, margin 5% of
/// the short edge. Reserved rectangles (Free watermark, Dual-Cam inset) are never covered:
/// top indicators move down, bottom indicators move up, until they are clear. If that is not
/// possible within the frame, the indicator is drawn smaller (not below 70%) and the layout is
/// flagged for visual review. A selected indicator is never silently omitted.
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

    static func intersects(_ a: WatermarkLayout.Rect, _ b: WatermarkLayout.Rect) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }
}
