import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("Dual-Cam flow (01 P05, 05 V03)")
struct DualCaptureFlowTests {
    private func make(access: AccessState = .notConfigured) -> (DualCaptureFlowViewModel, FakeDualCaptureController, InMemoryProjectStore, CallLog) {
        let capture = FakeDualCaptureController()
        let store = InMemoryProjectStore()
        let log = CallLog()
        let viewModel = DualCaptureFlowViewModel(
            lookID: nil, capture: capture, permissions: FakeCapturePermissions(), projects: store,
            access: FakePurchaseService(access: access),
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferences: InMemoryLookPreferencesStore(), telemetry: RecordingTelemetry(),
            makeName: { _ in try! ProjectName("Dual") },
            onFinished: { _ in log.record("finished") },
            onImportInstead: { log.record("import") },
            onClose: { log.record("close") })
        return (viewModel, capture, store, log)
    }

    private func t(_ value: Int64, _ timescale: Int32) -> RationalTime {
        try! RationalTime(value: value, timescale: timescale)
    }

    @Test func recordsTwoSourcesWithOneAudioOwnerAndTheSwapTimeline() async throws {
        let (viewModel, capture, store, log) = make()
        capture.frontStart = t(1, 30)
        await viewModel.start()
        viewModel.chooseCorner(.bottomLeft)
        await viewModel.record()
        #expect(viewModel.isRecording)
        #expect(capture.maximumDuration == .seconds(30), "Free limit applies to Dual-Cam too")
        #expect(viewModel.mainCamera == .rear)

        capture.compositionTime = .seconds(1)
        await viewModel.swap()
        #expect(viewModel.mainCamera == .front)
        await viewModel.swap()  // Same frame: coalesced, not a double swap.
        capture.compositionTime = .seconds(2)
        await viewModel.swap()
        #expect(viewModel.mainCamera == .rear)

        await viewModel.stop()
        guard case .finished(let id) = viewModel.state else { Issue.record("Expected finished"); return }
        let record = try await store.project(id)
        #expect(record.sourceMode == .dualCamera)
        let rear = try #require(record.sources.first { $0.role == .rearCamera })
        let front = try #require(record.sources.first { $0.role == .frontCamera })
        #expect(rear.metadata.ownsSharedAudio && rear.metadata.hasUsableAudio)
        #expect(!front.metadata.ownsSharedAudio && !front.metadata.hasUsableAudio)
        #expect(front.metadata.startOffset == t(1, 30))
        #expect(front.metadata.isMirrored)
        let layout = try #require(record.recipe.dualLayout)
        #expect(layout.insetCorner == .bottomLeft)
        #expect(layout.swaps.map(\.sourceTime) == [.seconds(1), .seconds(2)])
        #expect(capture.tornDown)
        #expect(log.entries == ["finished"])
    }

    @Test func swapAndCornerAreRefusedOutsideTheirPhase() async {
        let (viewModel, capture, _, _) = make()
        await viewModel.start()
        capture.compositionTime = .seconds(1)
        await viewModel.swap()
        #expect(viewModel.layout.swaps.isEmpty, "No swap before recording")
        await viewModel.record()
        viewModel.chooseCorner(.bottomRight)
        #expect(viewModel.layout.insetCorner == .topRight, "Corner is fixed during the take")
    }

    @Test func swapBeforeBothStreamsStartedIsIgnored() async {
        let (viewModel, capture, _, _) = make()
        await viewModel.start()
        await viewModel.record()
        capture.compositionTime = nil
        await viewModel.swap()
        #expect(viewModel.layout.swaps.isEmpty)
    }

    @Test func interruptionStopsBothStreamsAndKeepsTheTake() async throws {
        let (viewModel, capture, store, _) = make()
        await viewModel.start()
        await viewModel.record()
        let observing = Task { await viewModel.observeEvents() }
        capture.emit(.interrupted)
        for _ in 0..<200 where !isFinished(viewModel.state) { await Task.yield() }
        observing.cancel()
        #expect(viewModel.wasInterrupted)
        #expect(capture.stopCount == 1)
        guard case .finished(let id) = viewModel.state else { Issue.record("Expected finished"); return }
        #expect(try await store.project(id).sources.count == 2)
    }

    @Test func failedStreamFailsTheWholeTakeWithoutSingleCameraFallback() async throws {
        let (viewModel, capture, store, _) = make()
        capture.stopResult = .failure(.recordingFailed)
        await viewModel.start()
        await viewModel.record()
        await viewModel.stop()
        #expect(viewModel.state == .failed(.recordingFailed))
        #expect(try await store.projects().isEmpty)
    }

    @Test func tooShortCommonIntervalIsNotAProject() async throws {
        let (viewModel, capture, store, _) = make()
        capture.frontStart = t(9, 2)  // 4.5 s late on a 5 s take: 0.5 s overlap.
        await viewModel.start()
        await viewModel.record()
        await viewModel.stop()
        #expect(viewModel.state == .ready)
        #expect(try await store.projects().isEmpty)
    }

    @Test func proHasNoLimitAndPrepareFailureExplains() async {
        let (viewModel, capture, _, _) = make(access: AccessState(level: .pro, provenance: .developmentFake))
        await viewModel.start()
        await viewModel.record()
        #expect(capture.maximumDuration == nil)

        let (failing, failingCapture, _, _) = make()
        failingCapture.prepareFailure = .configurationFailed
        await failing.start()
        #expect(failing.state == .failed(.cameraUnavailable))
    }

    private func isFinished(_ state: DualCaptureFlowViewModel.State) -> Bool {
        if case .finished = state { return true }
        return false
    }
}
