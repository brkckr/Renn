import Foundation
import Observation
import RENNDomain

/// Dual-Cam flow (01 P05, 05 V03): pre-record inset corner, one-tap live swap stamped on the
/// take's composition clock, coherent stop of both streams, and one project with two clean
/// sources, one shared audio track and the full swap timeline. States, failures and the timer
/// behave exactly like the ordinary camera flow.
@MainActor
@Observable
public final class DualCaptureFlowViewModel {
    public typealias State = CaptureFlowViewModel.State
    public typealias Failure = CaptureFlowViewModel.Failure
    public typealias Timer = CaptureFlowViewModel.Timer

    public private(set) var state: State = .idle {
        // Look, Beat and indicators are locked from countdown until the take is finalized (02 D06).
        didSet { draft.isLocked = isCountingDown || isRecording || state == .finalizing }
    }
    /// Pre-record Look/Beat/indicators; seeds the new project's recipe.
    public let draft = RecipeDraftEditor()
    /// Corner fixed before recording; the swap timeline is persisted with it.
    public private(set) var layout = DualCameraLayout()
    public private(set) var isSilent = false
    public private(set) var recordingLimit: RationalTime?
    public private(set) var wasInterrupted = false
    public var previewRecipe: Recipe? { draft.displayRecipe }
    public var timer: Timer = .off

    private var countdownTask: Task<Void, Never>?
    private var isStopping = false
    private var isSwapping = false
    private let sleep: @Sendable (Duration) async throws -> Void
    private let lookID: LookID?
    private let capture: any DualCaptureControlling
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
        capture: any DualCaptureControlling,
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

    /// Camera currently shown full-frame (live preview follows the latest swap).
    public var mainCamera: DualCameraLayout.Camera {
        layout.swaps.last?.mainCamera ?? layout.initialMainCamera
    }

    public func start() async {
        guard state == .idle || isFailedRetryable else { return }
        state = .preparing
        if draft.recipe == nil {
            let catalog = try? await lookCatalog.catalog()
            let look = lookID.flatMap { catalog?.look($0) } ?? catalog?.recommendedLook
            if let stamp = try? StampDate(date: now(), timeZone: timeZone) {
                let telemetry = telemetry
                draft.begin(
                    Recipe.initial(look: look, creationStamp: stamp, seed: UInt64.random(in: .min ... .max)),
                    catalog: catalog,
                    onCommit: { event in Task { await telemetry.record(event) } })
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
            try await capture.prepare(withAudio: !isSilent)
            state = .ready
        } catch {
            state = .failed(.cameraUnavailable)
        }
    }

    public func observeEvents() async {
        for await event in capture.events {
            switch event {
            case .recordedDuration(let duration):
                if isRecording { state = .recording(duration) }
            case .limitReached:
                await stop()
            case .interrupted:
                // Missing stream or pressure stops the take coherently (05 V03).
                wasInterrupted = true
                cancelCountdown()
                if isRecording { await stop() }
            }
        }
    }

    /// Pre-record only; fixed for the take (01 P05).
    public func chooseCorner(_ corner: DualCameraLayout.Corner) {
        guard state == .ready else { return }
        layout = DualCameraLayout(insetCorner: corner, initialMainCamera: layout.initialMainCamera)
    }

    /// One-tap live swap while recording, stamped with the take's composition time.
    public func swap() async {
        guard isRecording, !isSwapping else { return }
        isSwapping = true
        defer { isSwapping = false }
        guard let time = await capture.currentCompositionTime(), isRecording else { return }
        layout.recordSwap(at: time)
    }

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
        // A new take starts a new swap timeline with the chosen corner.
        layout = DualCameraLayout(insetCorner: layout.insetCorner, initialMainCamera: layout.initialMainCamera)
        let rearFile: URL
        let frontFile: URL
        do {
            rearFile = try await projects.makeStagingFileURL(fileExtension: "mov")
            frontFile = try await projects.makeStagingFileURL(fileExtension: "mov")
        } catch {
            state = .failed(.insufficientStorage)
            return
        }
        do {
            try await capture.startRecording(rearFile: rearFile, frontFile: frontFile, maximumDuration: recordingLimit)
            state = .recording(.zero)
            await telemetry.record(.creationStarted(mode: .dualCamera))
        } catch .insufficientStorage {
            state = .failed(.insufficientStorage)
        } catch {
            state = .failed(.recordingFailed)
        }
    }

    public func stop() async {
        guard isRecording, !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        state = .finalizing
        let take: DualRecordedTake
        do {
            take = try await capture.stopRecording()
        } catch .emptyRecording {
            state = .ready
            return
        } catch {
            state = .failed(.recordingFailed)
            return
        }
        // Both sources must share a playable interval; a too-short take is not a project.
        guard (try? DualSourceTiming(
            rearStart: take.rearStart, rearDuration: take.rear.duration,
            frontStart: take.frontStart, frontDuration: take.front.duration)) != nil
        else {
            state = .ready
            return
        }
        await commit(take)
    }

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

    private func commit(_ take: DualRecordedTake) async {
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
        recipe.dualLayout = layout
        func staged(_ recorded: RecordedTake, role: SourceRole, start: RationalTime, ownsAudio: Bool) -> StagedSource {
            StagedSource(
                role: role, stagedFile: recorded.file, fileName: "\(role.rawValue).mov",
                metadata: SourceMetadata(
                    duration: recorded.duration, startOffset: start,
                    displayDimensions: recorded.displayDimensions, frameRate: recorded.frameRate,
                    hasUsableAudio: ownsAudio && recorded.hasAudio, isMirrored: recorded.isMirrored,
                    ownsSharedAudio: ownsAudio && recorded.hasAudio, isHDR: false))
        }
        let projectDraft = NewProjectDraft(
            createdAt: createdAt,
            name: makeName(createdAt),
            sourceMode: .dualCamera,
            sources: [
                // The rear source is the declared owner of the one shared mic track (05 V03).
                staged(take.rear, role: .rearCamera, start: take.rearStart, ownsAudio: true),
                staged(take.front, role: .frontCamera, start: take.frontStart, ownsAudio: false),
            ],
            recipe: recipe)
        do {
            let record = try await projects.createProject(projectDraft)
            if let lookID = record.recipe.lookID {
                await lookPreferences.recordUse(of: lookID)
            }
            let duration = min(take.rear.duration, take.front.duration)
            await telemetry.record(.sourceReady(mode: .dualCamera, duration: .bucket(duration)))
            capture.tearDown()
            state = .finished(record.id)
            onFinished(record.id)
        } catch .insufficientStorage {
            state = .failed(.insufficientStorage)
        } catch {
            state = .failed(.couldNotSave)
        }
    }
}
