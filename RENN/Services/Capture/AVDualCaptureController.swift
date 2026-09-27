import AVFoundation
import UIKit
import RENNDomain

/// Dual-Cam capture (05 V03) over `AVCaptureMultiCamSession`: rear and front wide cameras at the
/// validated 1080p30 pair, each written clean to its own file, and one microphone written only
/// into the rear file (the declared audio owner). Both writers use the same capture clock, so the
/// files' first-sample times give the common offsets. Either stream failing fails the take.
///
/// Physical-device only: the Simulator reports no multi-camera support, so this adapter is
/// compiled on CI but exercised only by the device test plan.
@MainActor
final class AVDualCaptureController: DualCaptureControlling {
    let events: AsyncStream<CaptureEvent>
    /// Latest frames for the live composed preview.
    let rearFrames = CaptureFrameBox()
    let frontFrames = CaptureFrameBox()

    private let eventContinuation: AsyncStream<CaptureEvent>.Continuation
    private let graph = DualCaptureGraph()
    private var observers: [NSObjectProtocol] = []

    init() {
        (events, eventContinuation) = AsyncStream.makeStream(of: CaptureEvent.self, bufferingPolicy: .bufferingNewest(8))
    }

    func prepare(withAudio: Bool) async throws(CaptureFailure) {
        let rearFrames = rearFrames
        let frontFrames = frontFrames
        try await graph.run { graph in
            try graph.configure(withAudio: withAudio, rearFrames: rearFrames, frontFrames: frontFrames)
            graph.session.startRunning()
        }
        observeInterruptions()
    }

    func startRecording(rearFile: URL, frontFile: URL, maximumDuration: RationalTime?) async throws(CaptureFailure) {
        let continuation = eventContinuation
        let limit = maximumDuration.map { CMTime(value: $0.value, timescale: $0.timescale) }
        try await graph.run { graph in
            try graph.startRecording(
                rearFile: rearFile, frontFile: frontFile, limit: limit,
                onDuration: { time in
                    if let duration = try? RationalTime(value: time.value, timescale: time.timescale) {
                        continuation.yield(.recordedDuration(duration))
                    }
                },
                onLimitReached: { continuation.yield(.limitReached) })
        }
    }

    func currentCompositionTime() async -> RationalTime? {
        guard let time = await graph.compositionTime() else { return nil }
        return try? RationalTime(value: time.value, timescale: time.timescale)
    }

    func stopRecording() async throws(CaptureFailure) -> DualRecordedTake {
        let takes = try await graph.stopRecording()
        let earliest = CMTimeMinimum(takes.rear.origin, takes.front.origin)
        func recorded(_ take: SourceRecorder.Take, mirrored: Bool) throws(CaptureFailure) -> RecordedTake {
            guard let dimensions = try? PixelDimensions(width: take.width, height: take.height),
                  let duration = try? RationalTime(value: take.duration.value, timescale: take.duration.timescale)
            else { throw .recordingFailed }
            return RecordedTake(
                file: take.file, duration: duration, displayDimensions: dimensions, frameRate: take.frameRate,
                hasAudio: take.hasAudio, isMirrored: mirrored, wasInterrupted: false)
        }
        func offset(_ origin: CMTime) throws(CaptureFailure) -> RationalTime {
            let delta = CMTimeSubtract(origin, earliest)
            guard let time = try? RationalTime(value: delta.value, timescale: delta.timescale) else { throw .recordingFailed }
            return time
        }
        return DualRecordedTake(
            rear: try recorded(takes.rear, mirrored: false),
            front: try recorded(takes.front, mirrored: true),
            rearStart: try offset(takes.rear.origin),
            frontStart: try offset(takes.front.origin))
    }

    func tearDown() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        graph.stopSession()
    }

    private func observeInterruptions() {
        guard observers.isEmpty else { return }
        let continuation = eventContinuation
        let center = NotificationCenter.default
        // Includes camera loss under system pressure: the take stops coherently (05 V03).
        for name in [
            AVCaptureSession.wasInterruptedNotification,
            AVCaptureSession.runtimeErrorNotification,
            UIApplication.willResignActiveNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                continuation.yield(.interrupted)
            })
        }
    }
}

/// Multi-camera graph confined to `sessionQueue` (configuration) and `dataQueue` (samples).
final class DualCaptureGraph: NSObject, @unchecked Sendable,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "renn.dualcapture.session")
    private let dataQueue = DispatchQueue(label: "renn.dualcapture.data", qos: .userInitiated)
    private let rearOutput = AVCaptureVideoDataOutput()
    private let frontOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var isConfigured = false
    private var hasAudio = false
    private var rearFrames: CaptureFrameBox?
    private var frontFrames: CaptureFrameBox?
    private var rearRecorder: SourceRecorder?
    private var frontRecorder: SourceRecorder?
    private var pendingStop: [CheckedContinuation<(rear: SourceRecorder.Take, front: SourceRecorder.Take), any Error>] = []
    private var isStopping = false

    func run(_ body: @escaping @Sendable (DualCaptureGraph) throws -> Void) async throws(CaptureFailure) {
        let result: Result<Void, CaptureFailure> = await withCheckedContinuation { continuation in
            sessionQueue.async {
                do {
                    try body(self)
                    continuation.resume(returning: .success(()))
                } catch {
                    continuation.resume(returning: .failure(error as? CaptureFailure ?? .configurationFailed))
                }
            }
        }
        try result.get()
    }

    func configure(withAudio: Bool, rearFrames: CaptureFrameBox, frontFrames: CaptureFrameBox) throws(CaptureFailure) {
        self.rearFrames = rearFrames
        self.frontFrames = frontFrames
        guard !isConfigured else { return }
        guard AVCaptureMultiCamSession.isMultiCamSupported,
              let pair = DeviceCaptureCapabilities.dualFormatPair()
        else { throw .cameraUnavailable }

        session.beginConfiguration()
        do {
            try addCamera(position: .back, formatIndex: pair.rear.index, output: rearOutput, mirrored: false)
            try addCamera(position: .front, formatIndex: pair.front.index, output: frontOutput, mirrored: true)
            if withAudio { addMicrophone() }
        } catch {
            session.commitConfiguration()
            throw error
        }
        session.commitConfiguration()

        // The combination must fit the hardware budget; never silently degrade (05 V03).
        guard session.hardwareCost <= 1, session.systemPressureCost <= 1 else { throw .configurationFailed }
        isConfigured = true
    }

    private func addCamera(
        position: AVCaptureDevice.Position, formatIndex: Int, output: AVCaptureVideoDataOutput, mirrored: Bool
    ) throws(CaptureFailure) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              device.formats.indices.contains(formatIndex),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
        else { throw .cameraUnavailable }
        session.addInputWithNoConnections(input)
        do {
            try device.lockForConfiguration()
            device.activeFormat = device.formats[formatIndex]
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        } catch {
            throw .configurationFailed
        }

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: dataQueue)
        guard session.canAddOutput(output) else { throw .configurationFailed }
        session.addOutputWithNoConnections(output)

        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: position).first
        else { throw .configurationFailed }
        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else { throw .configurationFailed }
        session.addConnection(connection)
        // Portrait buffers; the front mirror choice is baked like its preview (05 V03).
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    /// One microphone, connected to the single audio output (never duplicated per camera).
    private func addMicrophone() {
        guard let microphone = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(input)
        else { return }
        session.addInputWithNoConnections(input)
        let ports = input.ports(for: .audio, sourceDeviceType: microphone.deviceType, sourceDevicePosition: .back)
        guard let port = ports.first ?? input.ports.first(where: { $0.mediaType == .audio }) else { return }
        audioOutput.setSampleBufferDelegate(self, queue: dataQueue)
        guard session.canAddOutput(audioOutput) else { return }
        session.addOutputWithNoConnections(audioOutput)
        let connection = AVCaptureConnection(inputPorts: [port], output: audioOutput)
        guard session.canAddConnection(connection) else { return }
        session.addConnection(connection)
        hasAudio = true
    }

    func startRecording(
        rearFile: URL, frontFile: URL, limit: CMTime?,
        onDuration: @escaping @Sendable (CMTime) -> Void, onLimitReached: @escaping @Sendable () -> Void
    ) throws(CaptureFailure) {
        guard isConfigured else { throw .configurationFailed }
        let audioSettings = hasAudio
            ? audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any] : nil
        let rear = SourceRecorder(
            file: rearFile, limit: limit, audioSettings: audioSettings, frameRate: .fps(30),
            onDuration: onDuration, onLimitReached: onLimitReached)
        // The front writer reports nothing: the rear take drives duration and the Free limit UI.
        let front = SourceRecorder(
            file: frontFile, limit: limit, audioSettings: nil, frameRate: .fps(30),
            onDuration: { _ in }, onLimitReached: {})
        dataQueue.sync {
            self.isStopping = false
            self.rearRecorder = rear
            self.frontRecorder = front
        }
    }

    /// Newest composition time: from the later start to the older of the two newest frames.
    func compositionTime() async -> CMTime? {
        await withCheckedContinuation { continuation in
            dataQueue.async {
                guard let rear = self.rearRecorder?.writtenRange, let front = self.frontRecorder?.writtenRange else {
                    continuation.resume(returning: nil)
                    return
                }
                let start = CMTimeMaximum(rear.origin, front.origin)
                let latest = CMTimeMinimum(rear.latest, front.latest)
                continuation.resume(returning: CMTimeMaximum(.zero, CMTimeSubtract(latest, start)))
            }
        }
    }

    /// Finalizes both writers; repeated calls converge. Either failing fails the take and both
    /// files are removed, so a Dual-Cam project never degrades to one camera.
    func stopRecording() async throws(CaptureFailure) -> (rear: SourceRecorder.Take, front: SourceRecorder.Take) {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                dataQueue.async {
                    self.pendingStop.append(continuation)
                    guard !self.isStopping else { return }
                    self.isStopping = true
                    guard let rear = self.rearRecorder, let front = self.frontRecorder else {
                        self.resolveStops(.failure(.emptyRecording))
                        return
                    }
                    let results = TakeResults()
                    let group = DispatchGroup()
                    group.enter()
                    rear.finish { result in
                        results.set(rear: result)
                        group.leave()
                    }
                    group.enter()
                    front.finish { result in
                        results.set(front: result)
                        group.leave()
                    }
                    group.notify(queue: self.dataQueue) {
                        self.rearRecorder = nil
                        self.frontRecorder = nil
                        switch (results.rear, results.front) {
                        case (.success(let rearTake)?, .success(let frontTake)?):
                            self.resolveStops(.success((rearTake, frontTake)))
                        default:
                            try? FileManager.default.removeItem(at: rear.file)
                            try? FileManager.default.removeItem(at: front.file)
                            func isEmpty(_ result: Result<SourceRecorder.Take, CaptureFailure>?) -> Bool {
                                if case .failure(.emptyRecording)? = result { return true }
                                return false
                            }
                            let empty = isEmpty(results.rear) || isEmpty(results.front)
                            self.resolveStops(.failure(empty ? .emptyRecording : .recordingFailed))
                        }
                    }
                }
            }
        } catch let failure as CaptureFailure {
            throw failure
        } catch {
            throw .recordingFailed
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func resolveStops(_ result: Result<(rear: SourceRecorder.Take, front: SourceRecorder.Take), CaptureFailure>) {
        let waiting = pendingStop
        pendingStop = []
        for continuation in waiting {
            continuation.resume(with: result.mapError { $0 as any Error })
        }
    }

    // MARK: Sample delegates (dataQueue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === rearOutput || output === frontOutput {
            let isRear = output === rearOutput
            if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                (isRear ? rearFrames : frontFrames)?.store(
                    CIImage(cvPixelBuffer: buffer), time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            }
            (isRear ? rearRecorder : frontRecorder)?.appendVideo(sampleBuffer)
        } else {
            rearRecorder?.appendAudio(sampleBuffer)
        }
    }
}

/// Collects both writers' outcomes; set from their finish callbacks, read after both left.
private final class TakeResults: @unchecked Sendable {
    private let lock = NSLock()
    private var rearResult: Result<SourceRecorder.Take, CaptureFailure>?
    private var frontResult: Result<SourceRecorder.Take, CaptureFailure>?

    var rear: Result<SourceRecorder.Take, CaptureFailure>? { lock.withLock { rearResult } }
    var front: Result<SourceRecorder.Take, CaptureFailure>? { lock.withLock { frontResult } }

    func set(rear result: Result<SourceRecorder.Take, CaptureFailure>) { lock.withLock { rearResult = result } }
    func set(front result: Result<SourceRecorder.Take, CaptureFailure>) { lock.withLock { frontResult = result } }
}
