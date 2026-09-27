import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("Capture flow (01 P05, 05 V02, 06 C06)")
struct CaptureFlowTests {
    private func make(
        permissions: FakeCapturePermissions = FakeCapturePermissions(),
        access: AccessState = .notConfigured
    ) -> (CaptureFlowViewModel, FakeCaptureController, InMemoryProjectStore, CallLog) {
        let capture = FakeCaptureController()
        let store = InMemoryProjectStore()
        let log = CallLog()
        let viewModel = CaptureFlowViewModel(
            lookID: nil, capture: capture, permissions: permissions, projects: store,
            access: FakePurchaseService(access: access),
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferences: InMemoryLookPreferencesStore(), telemetry: RecordingTelemetry(),
            makeName: { _ in try! ProjectName("Tape") },
            onFinished: { _ in log.record("finished") },
            onImportInstead: { log.record("import") },
            onClose: { log.record("close") })
        return (viewModel, capture, store, log)
    }

    @Test func recordsCommitsProjectAndReleasesCamera() async throws {
        let (viewModel, capture, store, log) = make()
        await viewModel.start()
        #expect(viewModel.state == .ready)
        await viewModel.record()
        #expect(viewModel.isRecording)
        #expect(capture.maximumDuration == .seconds(30), "Free records at most 30 s")
        await viewModel.stop()
        guard case .finished(let id) = viewModel.state else { Issue.record("Expected finished"); return }
        let record = try await store.project(id)
        #expect(record.sourceMode == .camera)
        #expect(record.sources.first?.metadata.hasUsableAudio == true)
        #expect(capture.tornDown)
        #expect(log.entries == ["finished"])
    }

    @Test func previewRecipeSeedsTheProject() async throws {
        let (viewModel, _, store, _) = make()
        await viewModel.start()
        let preview = try #require(viewModel.previewRecipe)
        #expect(preview.lookID == "dev.diagnostic")
        await viewModel.record()
        await viewModel.stop()
        guard case .finished(let id) = viewModel.state else { Issue.record("Expected finished"); return }
        let stored = try await store.project(id).recipe
        #expect(stored.seed == preview.seed)
        #expect(stored.intensity == preview.intensity)
    }

    @Test func proHasNoRecordingLimit() async {
        let (viewModel, capture, _, _) = make(access: AccessState(level: .pro, provenance: .developmentFake))
        await viewModel.start()
        await viewModel.record()
        #expect(capture.maximumDuration == nil)
    }

    @Test func cameraDeniedOffersImportInsteadOfRetrying() async {
        let (viewModel, _, _, log) = make(permissions: FakeCapturePermissions(camera: .denied))
        await viewModel.start()
        #expect(viewModel.state == .failed(.cameraDenied))
        viewModel.importInstead()
        #expect(log.entries == ["import"])
    }

    @Test func permissionIsRequestedInContextOnce() async {
        let permissions = FakeCapturePermissions(camera: .notDetermined, microphone: .notDetermined)
        let (viewModel, _, _, _) = make(permissions: permissions)
        await viewModel.start()
        #expect(await permissions.cameraRequests == 1)
        #expect(viewModel.state == .ready)
    }

    @Test func microphoneDeniedRecordsSilently() async throws {
        let (viewModel, capture, store, _) = make(permissions: FakeCapturePermissions(microphone: .denied))
        await viewModel.start()
        #expect(viewModel.isSilent)
        #expect(capture.preparedWithAudio == [false])
        await viewModel.record()
        await viewModel.stop()
        guard case .finished(let id) = viewModel.state else { Issue.record("Expected finished"); return }
        #expect(try await store.project(id).sources.first?.metadata.hasUsableAudio == false, "No fake Beat audio")
    }

    @Test func limitAndStopConvergeOnOneFinalization() async {
        let (viewModel, capture, _, _) = make()
        let events = Task { await viewModel.observeEvents() }
        defer { events.cancel() }
        await viewModel.start()
        await viewModel.record()
        capture.emit(.limitReached)
        await viewModel.stop()
        #expect(await eventually { if case .finished = viewModel.state { true } else { false } })
        #expect(capture.stopCount == 1)
    }

    @Test func interruptionStopsAndKeepsTheTake() async {
        let (viewModel, capture, store, _) = make()
        let events = Task { await viewModel.observeEvents() }
        defer { events.cancel() }
        await viewModel.start()
        await viewModel.record()
        capture.emit(.interrupted)
        #expect(await eventually { if case .finished = viewModel.state { true } else { false } })
        #expect(viewModel.wasInterrupted)
        #expect((try? await store.projects().count) == 1)
    }

    @Test func switchingCameraOnlyBeforeRecording() async {
        let (viewModel, capture, _, _) = make()
        await viewModel.start()
        await viewModel.switchCamera()
        #expect(viewModel.position == .front)
        await viewModel.record()
        await viewModel.switchCamera()
        #expect(viewModel.position == .front, "No mid-take camera switch in V1")
        #expect(capture.preparedPositions == [.rear, .front])
    }

    @Test func backWhileRecordingKeepsTheTake() async throws {
        let (viewModel, _, store, _) = make()
        await viewModel.start()
        await viewModel.record()
        await viewModel.close()
        #expect(try await store.projects().count == 1)
    }

    @Test func emptyTakeReturnsToReady() async {
        let (viewModel, capture, _, _) = make()
        capture.stopResult = .failure(.emptyRecording)
        await viewModel.start()
        await viewModel.record()
        await viewModel.stop()
        #expect(viewModel.state == .ready)
    }

    @Test func durationEventsUpdateRecordingTime() async {
        let (viewModel, capture, _, _) = make()
        let events = Task { await viewModel.observeEvents() }
        defer { events.cancel() }
        await viewModel.start()
        await viewModel.record()
        capture.emit(.recordedDuration(.seconds(3)))
        #expect(await eventually { viewModel.state == .recording(.seconds(3)) })
    }
}

private actor SleepGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var sleeps = 0
    func sleep() async {
        sleeps += 1
        await withCheckedContinuation { waiters.append($0) }
    }
    func releaseOne() {
        if !waiters.isEmpty { waiters.removeFirst().resume() }
    }
    func releaseAll() {
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
@Suite("Capture timer (01 P05)")
struct CaptureTimerTests {
    private func make(gate: SleepGate) -> (CaptureFlowViewModel, FakeCaptureController) {
        let capture = FakeCaptureController()
        let viewModel = CaptureFlowViewModel(
            lookID: nil, capture: capture, permissions: FakeCapturePermissions(), projects: InMemoryProjectStore(),
            access: FakePurchaseService(),
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferences: InMemoryLookPreferencesStore(), telemetry: RecordingTelemetry(),
            makeName: { _ in try! ProjectName("Tape") }, onFinished: { _ in }, onImportInstead: {}, onClose: {},
            sleep: { _ in
                await gate.sleep()
                try Task.checkCancellation()
            })
        return (viewModel, capture)
    }

    @Test func defaultIsOff() {
        let (viewModel, _) = make(gate: SleepGate())
        #expect(viewModel.timer == .off)
    }

    @Test func threeSecondCountdownThenRecordsWithFullFreeAllowance() async {
        let gate = SleepGate()
        let (viewModel, capture) = make(gate: gate)
        await viewModel.start()
        viewModel.timer = .three
        let recording = Task { await viewModel.record() }
        #expect(await eventually { viewModel.state == .countdown(3) })
        #expect(capture.recordingFile == nil, "Nothing is recorded during the countdown")
        await gate.releaseOne()
        #expect(await eventually { viewModel.state == .countdown(2) })
        await gate.releaseOne()
        #expect(await eventually { viewModel.state == .countdown(1) })
        await gate.releaseOne()
        await recording.value
        #expect(viewModel.isRecording)
        #expect(capture.maximumDuration == .seconds(30), "Countdown does not use the Free 30 s")
    }

    @Test func backCancelsTheCountdownWithoutRecording() async {
        let gate = SleepGate()
        let (viewModel, capture) = make(gate: gate)
        await viewModel.start()
        viewModel.timer = .ten
        let recording = Task { await viewModel.record() }
        #expect(await eventually { viewModel.state == .countdown(10) })
        viewModel.cancelCountdown()
        await gate.releaseAll()
        await recording.value
        #expect(viewModel.state == .ready)
        #expect(capture.recordingFile == nil)
    }

    @Test func interruptionCancelsTheCountdown() async {
        let gate = SleepGate()
        let (viewModel, capture) = make(gate: gate)
        let events = Task { await viewModel.observeEvents() }
        defer { events.cancel() }
        await viewModel.start()
        viewModel.timer = .three
        let recording = Task { await viewModel.record() }
        #expect(await eventually { viewModel.isCountingDown })
        capture.emit(.interrupted)
        #expect(await eventually { viewModel.state == .ready })
        await gate.releaseAll()
        await recording.value
        #expect(capture.recordingFile == nil)
    }
}
