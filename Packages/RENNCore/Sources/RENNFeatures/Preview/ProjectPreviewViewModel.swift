import Foundation
import Observation
import RENNDomain

/// Simplified project preview (01 P07, 02 D05): Look intensity, mute, before/after, loop and
/// Export. Playback controls never edit duration; before/after never mutates the recipe or
/// removes the policy watermark. Intensity autosaves with a bounded debounce (05 V08).
@MainActor
@Observable
public final class ProjectPreviewViewModel {
    public enum LoadState: Equatable, Sendable {
        case loading
        case ready
        case unavailable(ProjectSummary.Readiness?)
    }

    /// What the Beat panel can say about the source audio (02 D05 S11).
    public enum BeatAvailability: Equatable, Sendable {
        case analyzing
        case available
        /// The video has no usable sound: Look-only processing stays available.
        case noAudio
        case failed
    }

    public enum ExportEntry: Equatable, Sendable {
        case none
        case summary(ExportSummary)
        case requiresPro
    }

    public static let saveDebounce: Duration = .milliseconds(500)

    public private(set) var loadState: LoadState = .loading
    public private(set) var record: ProjectRecord?
    /// The single source, or the Dual-Cam audio owner (drives Beat and sound).
    public private(set) var sourceURL: URL?
    /// Present for Dual-Cam projects: both files and their common interval (05 V03).
    public private(set) var dualPreview: DualPreview?
    /// Beat timeline times are file times of `sourceURL`; composition time + this offset.
    public private(set) var beatTimeOffset: RationalTime = .zero

    public struct DualPreview: Sendable, Equatable {
        public let rearURL: URL
        public let frontURL: URL
        public let timing: DualSourceTiming
        public let layout: DualCameraLayout
        public let audioFromRear: Bool
    }
    /// Working copy of the recipe shown by the preview; persisted in revisions.
    public private(set) var recipe: Recipe?
    public private(set) var showsWatermark = true
    public private(set) var exportEntry: ExportEntry = .none
    public private(set) var beatTimeline: BeatTimeline?
    public private(set) var beatAvailability: BeatAvailability = .analyzing
    public var showsOriginal = false
    public var isLooping = true

    private var pendingSave: Task<Void, Never>?
    private let projectID: ProjectID
    private let projects: any ProjectStoring
    private let access: any AccessStateProviding
    private let exporter: ExportCoordinator
    private let telemetry: any TelemetryRecording
    private let beatTimelines: (any BeatTimelineProviding)?
    private let onClose: @MainActor () -> Void
    private let onShowPaywall: @MainActor () -> Void

    public init(
        projectID: ProjectID,
        projects: any ProjectStoring,
        access: any AccessStateProviding,
        exporter: ExportCoordinator,
        telemetry: any TelemetryRecording,
        beatTimelines: (any BeatTimelineProviding)? = nil,
        onClose: @escaping @MainActor () -> Void,
        onShowPaywall: @escaping @MainActor () -> Void
    ) {
        self.beatTimelines = beatTimelines
        self.projectID = projectID
        self.projects = projects
        self.access = access
        self.exporter = exporter
        self.telemetry = telemetry
        self.onClose = onClose
        self.onShowPaywall = onShowPaywall
    }

    public var exportState: ExportCoordinator.JobState { exporter.state }
    public var isMuted: Bool { recipe?.audioMuted ?? false }
    public var intensity: Double { recipe?.intensity.value ?? 0 }
    public var hasAudio: Bool { record.flatMap(Self.audioSource)?.metadata.hasUsableAudio ?? false }
    /// Canvas of the single source, or of the rear camera for Dual-Cam.
    public var displayDimensions: PixelDimensions? {
        (record?.sources.first { $0.role == .primary || $0.role == .rearCamera } ?? record?.sources.first)?.metadata.displayDimensions
    }
    public var name: String { record?.name.value ?? "" }
    public var isBeatEnabled: Bool { recipe?.beat.isEnabled ?? false }
    public var beatIntensity: Double { recipe?.beat.intensity ?? 0 }
    /// Beat modulation actually applies: enabled, not muted, usable audio (01 P06).
    public var isBeatEffective: Bool {
        guard let recipe else { return false }
        return recipe.beat.isEffective(audioMuted: recipe.audioMuted, sourceHasUsableAudio: beatAvailability == .available)
    }

    /// The source whose audio the project uses: the single source, or the declared Dual-Cam owner
    /// (the rear camera when none owns it, which then means a silent take).
    static func audioSource(_ record: ProjectRecord) -> SourceReference? {
        if let primary = record.sources.first(where: { $0.role == .primary }) { return primary }
        return record.sources.first { $0.metadata.ownsSharedAudio }
            ?? record.sources.first { $0.role == .rearCamera }
            ?? record.sources.first
    }

    public func load() async {
        do {
            let loaded = try await projects.project(projectID)
            guard loaded.readiness == .ready, let source = Self.audioSource(loaded) else {
                loadState = .unavailable(loaded.readiness)
                return
            }
            if let rear = loaded.sources.first(where: { $0.role == .rearCamera }),
               let front = loaded.sources.first(where: { $0.role == .frontCamera }) {
                // A Dual-Cam project previews as a composite or not at all; never one camera.
                guard let layout = loaded.recipe.dualLayout,
                      let timing = try? DualSourceTiming(
                          rearStart: rear.metadata.startOffset, rearDuration: rear.metadata.duration,
                          frontStart: front.metadata.startOffset, frontDuration: front.metadata.duration)
                else {
                    loadState = .unavailable(nil)
                    return
                }
                dualPreview = DualPreview(
                    rearURL: await projects.fileURL(rear.relativePath),
                    frontURL: await projects.fileURL(front.relativePath),
                    timing: timing, layout: layout, audioFromRear: source.role == .rearCamera)
                beatTimeOffset = source.role == .rearCamera ? timing.rearOffset : timing.frontOffset
            }
            record = loaded
            recipe = loaded.recipe
            sourceURL = await projects.fileURL(source.relativePath)
            await refreshWatermark()
            loadState = .ready
            await telemetry.record(.previewReady)
            await loadBeatTimeline(source: source)
        } catch {
            loadState = .unavailable(nil)
        }
    }

    /// Follows access changes so the preview watermark matches the current tier.
    public func observeAccess() async {
        for await state in await access.accessUpdates() {
            showsWatermark = state.effectiveTier == .free
        }
    }

    /// The preview shows the effective watermark placement for the current access (02 D07).
    public func refreshWatermark() async {
        showsWatermark = await access.currentAccess().effectiveTier == .free
    }

    // MARK: Adjustments

    public func setIntensity(_ value: Double) {
        guard var recipe, let intensity = LookIntensity(value) else { return }
        recipe.intensity = intensity
        self.recipe = recipe
        scheduleSave()
    }

    /// Apply from the indicators panel: one recipe revision for the whole staged change.
    public func applyIndicators(_ draft: IndicatorsDraft) {
        guard var recipe else { return }
        let updated = draft.applied(to: recipe.indicators)
        guard updated != recipe.indicators else { return }
        recipe.indicators = updated
        self.recipe = recipe
        scheduleSave(immediately: true)
    }

    public func setBeatEnabled(_ enabled: Bool) {
        guard var recipe, recipe.beat.isEnabled != enabled else { return }
        recipe.beat = BeatSettings(isEnabled: enabled, intensity: recipe.beat.intensity)
        self.recipe = recipe
        scheduleSave(immediately: true)
    }

    /// Beat intensity 0 renders identically to Beat off (05 V04).
    public func setBeatIntensity(_ value: Double) {
        guard var recipe else { return }
        recipe.beat = BeatSettings(isEnabled: recipe.beat.isEnabled, intensity: value)
        self.recipe = recipe
        scheduleSave()
    }

    /// Mute suppresses output audio and Beat modulation; Beat settings are kept (01 P06).
    public func toggleMute() {
        guard var recipe else { return }
        recipe.audioMuted.toggle()
        self.recipe = recipe
        scheduleSave(immediately: true)
    }

    /// Flushes pending changes at safe navigation transitions (05 V08).
    public func flush() async {
        pendingSave?.cancel()
        pendingSave = nil
        await persist()
    }

    public func close() async {
        await flush()
        onClose()
    }

    // MARK: Export

    public func requestExport() async {
        await flush()
        switch await exporter.summary(for: projectID) {
        case .ready(let summary): exportEntry = .summary(summary)
        case .requiresPro: exportEntry = .requiresPro
        case .unavailable: exportEntry = .none
        }
    }

    public func confirmExport() {
        guard case .summary = exportEntry else { return }
        exportEntry = .none
        exporter.start(projectID)
    }

    public func dismissExportEntry() {
        exportEntry = .none
    }

    /// Explicit Pro intent from the export summary (06 C04). Never forced after a valid export.
    public func upgradeForExport() {
        exportEntry = .none
        onShowPaywall()
    }

    /// Absolute URL of an output for Share / Watch in RENN.
    public func url(for output: OutputRecord) async -> URL {
        await projects.fileURL(output.relativePath)
    }

    /// Clears a finished job's result after its sheet is closed.
    public func acknowledgeExport() {
        exporter.acknowledge()
    }

    public func cancelExport() {
        exporter.cancel()
    }

    public func retryPhotosSave() async {
        await exporter.retrySave()
    }

    private func loadBeatTimeline(source: SourceReference) async {
        guard source.metadata.hasUsableAudio else {
            beatAvailability = .noAudio
            return
        }
        guard let beatTimelines, let url = sourceURL else {
            beatAvailability = .failed
            return
        }
        do {
            beatTimeline = try await beatTimelines.timeline(for: source, fileURL: url)
            beatAvailability = beatTimeline == nil ? .noAudio : .available
        } catch {
            beatAvailability = .failed
        }
    }

    // MARK: Persistence

    private func scheduleSave(immediately: Bool = false) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: Self.saveDebounce)
                guard !Task.isCancelled else { return }
            }
            await self?.persist()
        }
    }

    private func persist() async {
        guard let record, let recipe, recipe != record.recipe else { return }
        do {
            self.record = try await projects.updateRecipe(projectID, expectedRevision: record.recipeRevision, recipe: recipe)
        } catch .staleRevision {
            // Another writer won: reload the authoritative record rather than overwrite it.
            if let reloaded = try? await projects.project(projectID) {
                self.record = reloaded
                self.recipe = reloaded.recipe
            }
        } catch {
            // Keep the working copy; the next change or flush retries.
        }
    }
}
