/// Strengths of the render-version-1 tape stage (the `rennVHS` Core Image kernel), resolved from a
/// recipe at its intensity. Pure so the mapping and bounds are testable on Linux.
public struct TapeArtifacts: Sendable, Equatable {
    public let chromaBleed: Double
    public let softness: Double
    public let scanlines: Double
    public let lineJitter: Double
    public let tracking: Double

    public static let none = TapeArtifacts(chromaBleed: 0, softness: 0, scanlines: 0, lineJitter: 0, tracking: 0)

    public init(chromaBleed: Double, softness: Double, scanlines: Double, lineJitter: Double, tracking: Double) {
        func unit(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0 }
        self.chromaBleed = unit(chromaBleed)
        self.softness = unit(softness)
        self.scanlines = unit(scanlines)
        self.lineJitter = unit(lineJitter)
        self.tracking = unit(tracking)
    }

    /// Strengths at the recipe's intensity; intensity 0 gives `.none` (an exact passthrough).
    public init(recipe: Recipe) {
        self.init(
            chromaBleed: recipe.effectiveParameter(LookParameter.chromaBleed),
            softness: recipe.effectiveParameter(LookParameter.tapeSoftness),
            scanlines: recipe.effectiveParameter(LookParameter.scanlines),
            lineJitter: recipe.effectiveParameter(LookParameter.lineJitter),
            tracking: recipe.effectiveParameter(LookParameter.tracking))
    }

    /// The stage is skipped entirely when every strength is 0.
    public var isActive: Bool { self != .none }

    /// Largest horizontal sampling distance of the kernel, in output pixels, for a frame with this
    /// short edge: jitter 1.5 + tracking 14 + softness 5 + bleed 8 px at 1080, plus a margin.
    public static func sampleReach(shortEdge: Double) -> Double {
        let scale = max(0.25, shortEdge / 1080)
        return (1.5 + 14 + 5 + 8) * scale + 2
    }

    /// Stable 0..<1 phase from the project seed, so different projects roll the tracking band
    /// at different moments.
    public static func seedPhase(_ seed: UInt64) -> Double {
        Double(seed % 1024) / 1024
    }
}
