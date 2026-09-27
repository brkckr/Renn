/// Immutable snapshot for one export job (05 V09): recipe revision, access and resolved
/// output policy. Later entitlement or recipe changes affect only new jobs.
public struct ExportPlan: Sendable, Equatable {
    public let projectID: ProjectID
    public let recipeRevision: Int
    public let recipe: Recipe
    public let policy: OutputPolicy
    public let source: SourceReference
    public let includesAudio: Bool

    public enum PlanError: Error, Equatable, Sendable {
        case projectNotReady
        case noPrimarySource
        /// Free project longer than 30 s: offer Pro; never trim (01 P08).
        case requiresPro(limit: RationalTime)
    }

    /// Single-source plan (import or ordinary capture). Dual-Cam composition is M04.
    public static func make(record: ProjectRecord, access: AccessState) throws(PlanError) -> ExportPlan {
        guard record.readiness == .ready else { throw .projectNotReady }
        guard let source = record.sources.first(where: { $0.role == .primary }) else { throw .noPrimarySource }
        let profile = SourceMediaProfile(
            displayDimensions: source.metadata.displayDimensions,
            frameRate: source.metadata.frameRate,
            duration: source.metadata.duration,
            hasUsableAudio: source.metadata.hasUsableAudio)
        switch AccessPolicy.resolve(source: profile, tier: access.effectiveTier) {
        case .exceedsFreeDuration(let limit, _):
            throw .requiresPro(limit: limit)
        case .allowed(let policy):
            return ExportPlan(
                projectID: record.id,
                recipeRevision: record.recipeRevision,
                recipe: record.recipe,
                policy: policy,
                source: source,
                // Muted projects export without audio; source audio stays preserved (01 P06).
                includesAudio: source.metadata.hasUsableAudio && !record.recipe.audioMuted)
        }
    }
}

/// Stage-weighted, monotonic export progress from measured work (05 V09). Never reports
/// completion before validation.
public struct ExportProgress: Sendable, Equatable {
    public enum Stage: Int, Sendable, Comparable {
        case preparing, rendering, finalizing, validating
        public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public private(set) var stage: Stage = .preparing
    public private(set) var fraction: Double = 0

    public init() {}

    /// Rendering covers 0...0.95 by rendered media time; finalizing/validating the rest.
    public mutating func update(stage newStage: Stage, renderedSeconds: Double = 0, totalSeconds: Double = 0) {
        stage = max(stage, newStage)
        let value: Double
        switch stage {
        case .preparing: value = 0
        case .rendering:
            value = totalSeconds > 0 ? 0.95 * min(1, max(0, renderedSeconds / totalSeconds)) : 0
        case .finalizing: value = 0.96
        case .validating: value = 0.98
        }
        fraction = max(fraction, value)
    }
}
