/// Timeline of the onboarding curved colour wipe (03 M02), as a pure function of elapsed time so
/// it is frame-rate independent (60/120 Hz) and testable. States: covering (0–380 ms, leading
/// edge sweeps right-to-left until the viewport is fully covered), the page swaps while covered at
/// 380 ms, revealing (380–760 ms, trailing edge follows and exposes the new page).
public enum OnboardingWipe {
    public static let coverDuration = 0.380
    public static let totalDuration = 0.760
    public static let oldCopyFadeEnd = 0.100
    public static let newCopyFadeStart = 0.520
    /// Middle deflection of the curved edge, as a fraction of the viewport width.
    public static let deflection = 0.22

    public struct Frame: Equatable, Sendable {
        /// 0 = leading edge off-screen right, 1 = viewport fully covered.
        public let cover: Double
        /// 0 = trailing edge off-screen right (nothing exposed), 1 = band gone to the left.
        public let reveal: Double
        /// The target page is shown underneath (the swap happened while covered).
        public let showsTarget: Bool
        public let oldCopyOpacity: Double
        public let newCopyOpacity: Double
        public let isFinished: Bool
    }

    public static func frame(at elapsed: Double) -> Frame {
        let t = max(0, elapsed)
        let cover = ease(min(1, t / coverDuration))
        let reveal = t <= coverDuration ? 0 : ease(min(1, (t - coverDuration) / (totalDuration - coverDuration)))
        let oldCopy = max(0, 1 - t / oldCopyFadeEnd)
        let newCopy = t <= newCopyFadeStart ? 0 : min(1, (t - newCopyFadeStart) / (totalDuration - newCopyFadeStart))
        return Frame(
            cover: cover, reveal: reveal, showsTarget: t >= coverDuration,
            oldCopyOpacity: t >= coverDuration ? 0 : oldCopy, newCopyOpacity: newCopy,
            isFinished: t >= totalDuration)
    }

    /// Horizontal position of an edge's top/bottom anchors in viewport widths, for progress 0...1.
    /// At 0 the whole curve (whose middle bulges `deflection` to the left) is right of the
    /// viewport; at 1 the whole curve is left of it, so full coverage includes every corner.
    public static func edgeX(progress: Double) -> Double {
        (1 + deflection) * (1 - progress)
    }

    /// Starting curve `cubic-bezier(0.22, 1, 0.36, 1)` (03 M02).
    public static func ease(_ x: Double) -> Double {
        cubicBezier(x, 0.22, 1, 0.36, 1)
    }

    /// y for x on a CSS-style cubic Bézier from (0,0) to (1,1); Newton iterations with a
    /// bisection fallback, accurate to about 1e-6.
    static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func sample(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a1 + 3 * u * t * t * a2 + t * t * t
        }
        func slope(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * a1 + 6 * u * t * (a2 - a1) + 3 * t * t * (1 - a2)
        }
        var t = x
        for _ in 0..<8 {
            let error = sample(t, x1, x2) - x
            if abs(error) < 1e-7 { return sample(t, y1, y2) }
            let d = slope(t, x1, x2)
            if abs(d) < 1e-6 { break }
            t -= error / d
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<40 {
            let value = sample(t, x1, x2)
            if abs(value - x) < 1e-7 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sample(t, y1, y2)
    }
}
