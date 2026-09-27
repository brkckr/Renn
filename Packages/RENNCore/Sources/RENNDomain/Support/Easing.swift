/// Shared motion easing (03): CSS-style cubic Bézier timing curves, evaluated from elapsed time.
public enum Easing {
    /// `cubic-bezier(0.22, 1, 0.36, 1)`: the contract's starting emphasized curve.
    public static func emphasized(_ x: Double) -> Double { cubicBezier(x, 0.22, 1, 0.36, 1) }
    /// `cubic-bezier(0.4, 0, 0.2, 1)`: standard ease-in-out.
    public static func standard(_ x: Double) -> Double { cubicBezier(x, 0.4, 0, 0.2, 1) }

    /// y for x on a CSS-style cubic Bézier from (0,0) to (1,1); Newton iterations with a
    /// bisection fallback, accurate to about 1e-6.
    public static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
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
