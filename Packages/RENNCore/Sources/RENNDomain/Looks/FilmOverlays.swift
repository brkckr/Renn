import Foundation

/// Film overlays for render version 1, as pure functions of (recipe, media time) so they are
/// reproducible and testable on Linux. The textures are still images; motion comes from here:
///
/// - Dust and scratches change about 20 times a second, like dust on a projected film: each step
///   picks one of the dust textures and a random flip, zoom and offset. Within a step nothing moves.
/// - A light leak drifts in and fades out once per `leakPeriod`, sometimes mirrored, and stays dark
///   for part of each cycle.
/// - Burnt edges stay put and breathe slightly.
public struct FilmOverlays: Sendable, Equatable {
    public struct Dust: Sendable, Equatable {
        public let strength: Double
        /// Index into the available dust textures (taken modulo their count by the renderer).
        public let variant: Int
        public let flipX: Bool
        public let flipY: Bool
        /// Zoom above cover-fit, 1...1.3, and the crop position in the spare area, 0...1 each.
        public let zoom: Double
        public let offsetX: Double
        public let offsetY: Double
    }

    public struct Leak: Sendable, Equatable {
        public let opacity: Double
        public let cool: Bool
        public let mirrored: Bool
        /// Horizontal drift as a fraction of the frame width, -0.1...0.1.
        public let drift: Double
    }

    public let dust: Dust?
    public let leak: Leak?
    /// Burnt-edge strength after breathing, 0...1; 0 means no burn layer.
    public let burn: Double

    public static let none = FilmOverlays(dust: nil, leak: nil, burn: 0)
    /// Dust steps per second (film projection flicker).
    public static let dustStepsPerSecond = 20.0
    public static let leakPeriod = 6.0

    public var isActive: Bool { dust != nil || leak != nil || burn > 0 }

    public init(dust: Dust?, leak: Leak?, burn: Double) {
        self.dust = dust
        self.leak = leak
        self.burn = burn
    }

    public init(recipe: Recipe, time: RationalTime) {
        let seconds = max(0, time.approximateSeconds)
        let seed = recipe.seed

        let dustStrength = Self.unit(recipe.effectiveParameter(LookParameter.dust))
        if dustStrength > 0 {
            let step = UInt64(floor(seconds * Self.dustStepsPerSecond))
            let bits = Self.mix(seed, step)
            dust = Dust(
                strength: dustStrength,
                variant: Int(bits % 1024),
                flipX: (bits >> 10) & 1 == 1,
                flipY: (bits >> 11) & 1 == 1,
                zoom: 1 + 0.3 * Self.fraction(bits >> 12),
                offsetX: Self.fraction(bits >> 22),
                offsetY: Self.fraction(bits >> 32))
        } else {
            dust = nil
        }

        let leakStrength = Self.unit(recipe.effectiveParameter(LookParameter.lightLeak))
        if leakStrength > 0 {
            let seedPhase = Double(seed % 1000) / 1000
            let cycles = seconds / Self.leakPeriod + seedPhase
            let cycle = UInt64(floor(cycles))
            let phase = cycles - floor(cycles)
            // In for the first 60% of the cycle (sin² bump), dark for the rest.
            let envelope = phase < 0.6 ? pow(sin(Double.pi * phase / 0.6), 2) : 0
            let bits = Self.mix(seed &+ 0x5EED, cycle)
            leak = Leak(
                opacity: leakStrength * envelope,
                cool: recipe.shapeParameter(LookParameter.lightLeakCool, fallback: 0) >= 0.5,
                mirrored: bits & 1 == 1,
                drift: 0.2 * (min(phase / 0.6, 1) - 0.5))
        } else {
            leak = nil
        }

        let burnStrength = Self.unit(recipe.effectiveParameter(LookParameter.burnEdges))
        burn = burnStrength > 0 ? burnStrength * (0.95 + 0.05 * sin(2 * Double.pi * seconds / 4)) : 0
    }

    static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    /// SplitMix64 of (seed, step): stable across launches and platforms.
    static func mix(_ seed: UInt64, _ step: UInt64) -> UInt64 {
        var z = seed &+ step &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<1 from the low 10 bits.
    static func fraction(_ bits: UInt64) -> Double {
        Double(bits & 1023) / 1024
    }
}
