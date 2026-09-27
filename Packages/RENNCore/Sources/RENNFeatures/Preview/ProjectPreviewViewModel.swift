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

    public enum ExportEntry: Equatable, Sendable {
        case none
        case summary(ExportSummary)
        case requiresPro
    }

    public static let saveDebounce: Duration = .milliseconds(500)

    public private(set) var loadState: LoadState = .loading
    public private(set) var record: ProjectRecord?
    public private(set) var sourceURL: URL?
    /// Working copy of the recipe shown by the preview; persisted in revisions.
    public private(set) var recipe: Recipe?
    public private(set) var showsWatermark = true
    public private(set) var exportEntry: ExportEntry = .none
    public var showsOriginal = false
    public var isLooping = true

    private var pendingSave: Task<Void, Never>?
    private let projectID: ProjectID
    private let projects: any ProjectStoring
    private let access: any AccessStateProviding
    private let exporter: ExportCoordinator
    private let telemetry: any TelemetryRecording
    private let onClose: @MainActor () -> Void
    private let onShowPaywall: @MainActor () -> Void

    public init(
        projectID: ProjectID,
        projects: any ProjectStoring,
        access: any AccessStateProviding,
        exporter: ExportCoordinator,
        telemetry: any TelemetryRecording,
        onClose: @escaping @MainActor () -> Void,
        onShowPaywall: @escaping @MainActor () -> Void
    ) {
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
    public var hasAudio: Bool { record?.sources.first?.metadata.hasUsableAudio ?? false }
    public var displayDimensions: PixelDimensions? { record?.sources.first?.metadata.displayDimensions }
    public var name: String { record?.name.value ?? "" }

    public func load() async {
        do {
            let loaded = try await projects.project(projectID)
            guard loaded.readiness == .ready, let source = loaded.sources.first else {
                loadState = .unavailable(loaded.readiness)
                return
            }
            record = loaded
            recipe = loaded.recipe
            sourceURL = await projects.fileURL(source.relativePath)
            await refreshWatermark()
            loadState = .ready
            await telemetry.record(.previewReady)
        } catch {
            loadState = .unavailable(nil)
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
