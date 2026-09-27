/// Immutable snapshot for one export job (05 V09): recipe revision, access and resolved
/// output policy. Later entitlement or recipe changes affect only new jobs.
public struct ExportPlan: Sendable, Equatable {
    public let projectID: ProjectID
    public let recipeRevision: Int
    public let recipe: Recipe
    public let policy: OutputPolicy
    /// Single source, or the Dual-Cam source that owns the shared audio track.
    public let source: SourceReference
    public let includesAudio: Bool
    /// Present for Dual-Cam projects: both clean sources and their common interval.
    public let dual: DualSources?

    /// Output media duration: the source duration, or the Dual-Cam common interval.
    public var duration: RationalTime { dual?.timing.duration ?? source.metadata.duration }

    /// Every file the render reads.
    public var sources: [SourceReference] { dual.map { [$0.rear, $0.front] } ?? [source] }

    public struct DualSources: Sendable, Equatable {
        public let rear: SourceReference
        public let front: SourceReference
        public let timing: DualSourceTiming
        public let layout: DualCameraLayout

        public func source(for camera: DualCameraLayout.Camera) -> SourceReference {
            camera == .rear ? rear : front
        }
    }

    public enum PlanError: Error, Equatable, Sendable {
        case projectNotReady
        case noPrimarySource
        /// Dual-Cam project missing a source, its layout, a valid common interval or a single
        /// declared audio owner. Never substituted with a single-camera export (05 V03).
        case invalidDualSources
        /// Free project longer than 30 s: offer Pro; never trim (01 P08).
        case requiresPro(limit: RationalTime)
    }

    /// Single-source plan (import or ordinary capture), or a Dual-Cam composition plan when
    /// the project holds rear and front sources.
    public static func make(record: ProjectRecord, access: AccessState) throws(PlanError) -> ExportPlan {
        guard record.readiness == .ready else { throw .projectNotReady }
        if let primary = record.sources.first(where: { $0.role == .primary }) {
            return try make(record: record, access: access, canvasSource: primary, duration: primary.metadata.duration,
                            audioSource: primary, dual: nil)
        }
        let rear = record.sources.first { $0.role == .rearCamera }
        let front = record.sources.first { $0.role == .frontCamera }
        guard rear != nil || front != nil else { throw .noPrimarySource }
        guard let rear, let front, let layout = record.recipe.dualLayout else { throw .invalidDualSources }
        let timing: DualSourceTiming
        do {
            timing = try DualSourceTiming(
                rearStart: rear.metadata.startOffset, rearDuration: rear.metadata.duration,
                frontStart: front.metadata.startOffset, frontDuration: front.metadata.duration)
        } catch {
            throw .invalidDualSources
        }
        // Exactly one declared owner of the shared mic track; never mix duplicates (05 V03).
        let owners = [rear, front].filter(\.metadata.ownsSharedAudio)
        guard owners.count <= 1 else { throw .invalidDualSources }
        let dual = DualSources(rear: rear, front: front, timing: timing, layout: layout)
        // The canvas follows the rear source (portrait 9:16 capture); both sources share one clock.
        return try make(record: record, access: access, canvasSource: rear, duration: timing.duration,
                        audioSource: owners.first ?? rear, dual: dual)
    }

    private static func make(
        record: ProjectRecord, access: AccessState, canvasSource: SourceReference, duration: RationalTime,
        audioSource: SourceReference, dual: DualSources?
    ) throws(PlanError) -> ExportPlan {
        let hasAudio = dual == nil
            ? audioSource.metadata.hasUsableAudio
            : audioSource.metadata.ownsSharedAudio && audioSource.metadata.hasUsableAudio
        let profile = SourceMediaProfile(
            displayDimensions: canvasSource.metadata.displayDimensions,
            frameRate: canvasSource.metadata.frameRate,
            duration: duration,
            hasUsableAudio: hasAudio)
        switch AccessPolicy.resolve(source: profile, tier: access.effectiveTier) {
        case .exceedsFreeDuration(let limit, _):
            throw .requiresPro(limit: limit)
        case .allowed(let policy):
            return ExportPlan(
                projectID: record.id,
                recipeRevision: record.recipeRevision,
                recipe: record.recipe,
                policy: policy,
                source: audioSource,
                // Muted projects export without audio; source audio stays preserved (01 P06).
                includesAudio: hasAudio && !record.recipe.audioMuted,
                dual: dual)
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
