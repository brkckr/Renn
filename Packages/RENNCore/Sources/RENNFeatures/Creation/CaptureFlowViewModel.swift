import Foundation
import Observation
import RENNDomain

/// Ordinary camera flow (01 P05, 04 A05, 05 V02): explicit capture state machine, pre-record
/// front/rear choice, Free 30 s safe stop, coherent stop on interruption, clean take committed
/// as a project. Recorded media is never discarded because of a failed commit.
@MainActor
@Observable
public final class CaptureFlowViewModel {
    /// Capture timer (01 P05): both tiers and modes; default Off on a new flow.
    public enum Timer: Int, Sendable, CaseIterable {
        case off = 0
        case three = 3
        case ten = 10
    }

    public enum State: Equatable, Sendable {
        case idle
        case preparing
        case ready
        /// Seconds left; nothing is being recorded yet.
        case countdown(Int)
        case recording(RationalTime)
        case finalizing
        case failed(Failure)
        case finished(ProjectID)
    }

    public enum Failure: Equatable, Sendable {
        /// Camera denied/restricted: explain and offer import and Settings (06 C06).
        case cameraDenied
        case cameraUnavailable
        case recordingFailed
        case insufficientStorage
        case couldNotSave
    }

    public private(set) var state: State = .idle {
        // Look, Beat and indicators are locked from countdown until the take is finalized (02 D06).
        didSet { draft.isLocked = isCountingDown || isRecording || state == .finalizing }
    }
    /// Pre-record Look/Beat/indicators; seeds the new project's recipe.
    public let draft = RecipeDraftEditor()
    public private(set) var position: CameraPosition = .rear
    /// Microphone denied: silent capture, Beat unavailable (05 V02).
    public private(set) var isSilent = false
    public private(set) var recordingLimit: RationalTime?
    public private(set) var wasInterrupted = false
    /// Recipe the live preview renders with (the draft, or the staged Look while the selector is
    /// open). The recorded file stays clean (05 V02); the draft seeds the new project.
    public var previewRecipe: Recipe? { draft.displayRecipe }
    /// Retained within this camera flow only.
    public var timer: Timer = .off

    private var countdownTask: Task<Void, Never>?
    private let sleep: @Sendable (Duration) async throws -> Void

    private var isStopping = false
    private let lookID: LookID?
    private let capture: any CaptureControlling
    private let permissions: any CapturePermissionProviding
    private let projects: any ProjectStoring
    private let access: any AccessStateProviding
    private let lookCatalog: any LookCatalogProviding
    private let lookPreferences: any LookPreferencesStoring
    private let telemetry: any TelemetryRecording
    private let makeName: @MainActor (Date) -> ProjectName
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private let onFinished: @MainActor (ProjectID) -> Void
    private let onImportInstead: @MainActor () -> Void
    private let onClose: @MainActor () -> Void

    public init(
        lookID: LookID?,
        capture: any CaptureControlling,
        permissions: any CapturePermissionProviding,
        projects: any ProjectStoring,
        access: any AccessStateProviding,
        lookCatalog: any LookCatalogProviding,
        lookPreferences: any LookPreferencesStoring,
        telemetry: any TelemetryRecording,
        makeName: @escaping @MainActor (Date) -> ProjectName,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current,
        onFinished: @escaping @MainActor (ProjectID) -> Void,
        onImportInstead: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.sleep = sleep
        self.lookID = lookID
        self.capture = capture
        self.permissions = permissions
        self.projects = projects
        self.access = access
        self.lookCatalog = lookCatalog
        self.lookPreferences = lookPreferences
        self.telemetry = telemetry
        self.makeName = makeName
        self.now = now
        self.timeZone = timeZone
        self.onFinished = onFinished
        self.onImportInstead = onImportInstead
        self.onClose = onClose
    }

    public var isCountingDown: Bool {
        if case .countdown = state { return true }
        return false
    }

    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Asks for permissions in context, then prepares the camera.
    public func start() async {
        guard state == .idle || isFailedRetryable else { return }
        state = .preparing
        if draft.recipe == nil {
            let catalog = try? await lookCatalog.catalog()
            let look = lookID.flatMap { catalog?.look($0) } ?? catalog?.recommendedLook
            if let stamp = try? StampDate(date: now(), timeZone: timeZone) {
                draft.begin(Recipe.initial(look: look, creationStamp: stamp, seed: UInt64.random(in: .min ... .max)), catalog: catalog)
            }
        }
        var camera = await permissions.cameraStatus()
        if camera == .notDetermined {
            camera = await permissions.requestCamera() ? .authorized : .denied
        }
        guard camera == .authorized else {
            state = .failed(.cameraDenied)
            return
        }
        var microphone = await permissions.microphoneStatus()
        if microphone == .notDetermined {
            microphone = await permissions.requestMicrophone() ? .authorized : .denied
        }
        isSilent = microphone != .authorized
        do {
            try await capture.prepare(position: position, withAudio: !isSilent)
            state = .ready
        } catch {
            state = .failed(.cameraUnavailable)
        }
    }

    /// Follows recorder events for the lifetime of the view.
    public func observeEvents() async {
        for await event in capture.events {
            switch event {
            case .recordedDuration(let duration):
                if isRecording { state = .recording(duration) }
            case .limitReached:
                await stop()
            case .interrupted:
                wasInterrupted = true
                cancelCountdown()
                if isRecording { await stop() }
            }
        }
    }

    /// Front/rear choice before recording only.
    public func switchCamera() async {
        guard state == .ready else { return }
        let next: CameraPosition = position == .rear ? .front : .rear
        state = .preparing
        do {
            try await capture.switchCamera(to: next)
            position = next
            state = .ready
        } catch {
            state = .ready
        }
    }

    /// Starts the countdown (if a timer is set) and then recording. The countdown is not
    /// recorded and does not count toward the Free limit.
    public func record() async {
        guard state == .ready else { return }
        guard timer != .off else {
            await beginRecording()
            return
        }
        countdownTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: self.timer.rawValue, to: 0, by: -1) {
                self.state = .countdown(remaining)
                do {
                    try await self.sleep(.seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled, self.isCountingDown else { return }
            }
            await self.beginRecording()
        }
        countdownTask = task
        await task.value
    }

    /// Back/background/interruption cancel a running countdown (01 P05).
    public func cancelCountdown() {
        guard isCountingDown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        state = .ready
    }

    private func beginRecording() async {
        guard state == .ready || isCountingDown else { return }
        countdownTask = nil
        let tier = await access.currentAccess().effectiveTier
        recordingLimit = tier == .free ? AccessPolicy.freeMaximumDuration : nil
        wasInterrupted = false
        let file: URL
        do {
            file = try await projects.makeStagingFileURL(fileExtension: "mov")
        } catch {
            state = .failed(.insufficientStorage)
            return
        }
        do {
            try await capture.startRecording(to: file, maximumDuration: recordingLimit)
            state = .recording(.zero)
            await telemetry.record(.creationStarted(mode: .camera))
        } catch .insufficientStorage {
            state = .failed(.insufficientStorage)
        } catch {
            state = .failed(.recordingFailed)
        }
    }

    /// Stop button, Free limit and interruptions all converge here exactly once.
    public func stop() async {
        guard isRecording, !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        state = .finalizing
        let take: RecordedTake
        do {
            take = try await capture.stopRecording()
        } catch .emptyRecording {
            state = .ready
            return
        } catch {
            state = .failed(.recordingFailed)
            return
        }
        await commit(take)
    }

    /// Back while recording stops and keeps the take; nothing recorded is thrown away.
    public func close() async {
        if isCountingDown {
            cancelCountdown()
        }
        if isRecording {
            await stop()
            return
        }
        capture.tearDown()
        onClose()
    }

    public func importInstead() {
        capture.tearDown()
        onImportInstead()
    }

    private var isFailedRetryable: Bool {
        if case .failed(let failure) = state { return failure != .cameraDenied }
        return false
    }

    private func commit(_ take: RecordedTake) async {
        let createdAt = now()
        let catalog = try? await lookCatalog.catalog()
        let look = lookID.flatMap { catalog?.look($0) } ?? catalog?.recommendedLook
        guard let stamp = try? StampDate(date: createdAt, timeZone: timeZone) else {
            state = .failed(.couldNotSave)
            return
        }
        var recipe = Recipe.initial(look: look, creationStamp: stamp, seed: UInt64.random(in: .min ... .max))
        if let chosen = draft.recipe {
            // What the user set up and saw while recording: Look, intensity, Beat, indicators, seed.
            recipe = chosen
        }
        let projectDraft = NewProjectDraft(
            createdAt: createdAt,
            name: makeName(createdAt),
            sourceMode: .camera,
            sources: [StagedSource(
                role: .primary,
                stagedFile: take.file,
                fileName: "source.mov",
                metadata: SourceMetadata(
                    duration: take.duration,
                    displayDimensions: take.displayDimensions,
                    frameRate: take.frameRate,
                    hasUsableAudio: take.hasAudio,
                    isMirrored: take.isMirrored,
                    ownsSharedAudio: take.hasAudio,
                    isHDR: false))],
            recipe: recipe)
        do {
            let record = try await projects.createProject(projectDraft)
            if let lookID = record.recipe.lookID {
                await lookPreferences.recordUse(of: lookID)
            }
            await telemetry.record(.sourceReady(mode: .camera, duration: .bucket(take.duration)))
            capture.tearDown()
            state = .finished(record.id)
            onFinished(record.id)
        } catch .insufficientStorage {
            state = .failed(.insufficientStorage)
        } catch {
            // The take stays in staging this launch; the project, if partially committed, is
            // marked interrupted by the store rather than deleted.
            state = .failed(.couldNotSave)
        }
    }
}
