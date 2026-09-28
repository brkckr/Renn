import AVFoundation
import UIKit
import RENNDomain

/// Contextual camera/microphone permissions (06 C06).
struct AVCapturePermissions: CapturePermissionProviding {
    func cameraStatus() async -> CapturePermission { Self.map(AVCaptureDevice.authorizationStatus(for: .video)) }
    func microphoneStatus() async -> CapturePermission { Self.map(AVCaptureDevice.authorizationStatus(for: .audio)) }
    func requestCamera() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
    func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    private static func map(_ status: AVAuthorizationStatus) -> CapturePermission {
        switch status {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        default: .denied
        }
    }
}

/// Single-camera capture (05 V01/V02): portrait, with the format chosen per tier before recording
/// by `CaptureFormatSelection` (Free up to 1080p30, Pro up to 4K60). The capture graph lives on
/// `sessionQueue`; samples arrive on `dataQueue`, where the `SourceRecorder` writes clean media.
/// Nothing drawn by the app (controls, countdown, REC UI) can enter the recorded pixels.
@MainActor
final class AVCaptureController: CaptureControlling {
    let events: AsyncStream<CaptureEvent>
    /// Latest frame for the live Look preview.
    let frames = CaptureFrameBox()

    private let eventContinuation: AsyncStream<CaptureEvent>.Continuation
    private let graph = CaptureGraph()
    private var position: CameraPosition = .rear
    private var withAudio = true
    private var tier: AccessTier = .free
    private var observers: [NSObjectProtocol] = []

    init() {
        (events, eventContinuation) = AsyncStream.makeStream(of: CaptureEvent.self, bufferingPolicy: .bufferingNewest(8))
    }

    var isMirrored: Bool { position == .front }

    func prepare(position: CameraPosition, withAudio: Bool, tier: AccessTier) async throws(CaptureFailure) {
        self.position = position
        self.withAudio = withAudio
        self.tier = tier
        let frames = frames
        try await graph.run { graph in
            try graph.configure(position: position, withAudio: withAudio, tier: tier, frames: frames)
            graph.session.startRunning()
        }
        observeInterruptions()
    }

    func switchCamera(to position: CameraPosition) async throws(CaptureFailure) {
        let frames = frames
        let withAudio = withAudio
        let tier = tier
        try await graph.run { graph in
            try graph.configure(position: position, withAudio: withAudio, tier: tier, frames: frames)
        }
        self.position = position
    }

    func startRecording(to file: URL, maximumDuration: RationalTime?) async throws(CaptureFailure) {
        let continuation = eventContinuation
        let limit = maximumDuration.map { CMTime(value: $0.value, timescale: $0.timescale) }
        try await graph.run { graph in
            try graph.startRecording(
                to: file, limit: limit,
                onDuration: { time in
                    if let duration = try? RationalTime(value: time.value, timescale: time.timescale) {
                        continuation.yield(.recordedDuration(duration))
                    }
                },
                onLimitReached: { continuation.yield(.limitReached) })
        }
    }

    func stopRecording() async throws(CaptureFailure) -> RecordedTake {
        let take = try await graph.stopRecording()
        guard let dimensions = try? PixelDimensions(width: take.width, height: take.height),
              let duration = try? RationalTime(value: take.duration.value, timescale: take.duration.timescale)
        else { throw .recordingFailed }
        return RecordedTake(
            file: take.file, duration: duration, displayDimensions: dimensions, frameRate: take.frameRate,
            hasAudio: take.hasAudio, isMirrored: isMirrored, wasInterrupted: false)
    }

    /// Releases camera and microphone (04 A03 camera-flow lifetime).
    func tearDown() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        graph.stopSession()
    }

    private func observeInterruptions() {
        guard observers.isEmpty else { return }
        let continuation = eventContinuation
        let center = NotificationCenter.default
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

/// Capture graph confined to `sessionQueue` (configuration) and `dataQueue` (samples).
/// `@unchecked Sendable` because every member is only touched on those serial queues.
final class CaptureGraph: NSObject, @unchecked Sendable,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "renn.capture.session")
    private let dataQueue = DispatchQueue(label: "renn.capture.data", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var frames: CaptureFrameBox?
    private var recorder: SourceRecorder?
    private var pendingStop: [CheckedContinuation<SourceRecorder.Take, any Error>] = []
    private var isStopping = false
    /// Rate of the configured format; the recorder writes it as the source cadence.
    private var frameRate = FrameRate.fps(30)

    /// Runs `body` on the session queue.
    func run(_ body: @escaping @Sendable (CaptureGraph) throws -> Void) async throws(CaptureFailure) {
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

    func configure(position: CameraPosition, withAudio: Bool, tier: AccessTier, frames: CaptureFrameBox) throws(CaptureFailure) {
        self.frames = frames
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // The device format decides size and rate (set below), not a preset.
        session.sessionPreset = .inputPriority

        if let videoInput { session.removeInput(videoInput) }
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: position == .front ? .front : .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
        else { throw .cameraUnavailable }
        session.addInput(input)
        videoInput = input
        let candidates = device.formats.enumerated().compactMap { index, format -> CaptureFormatSelection.Candidate? in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard let dimensions = try? PixelDimensions(width: Int(size.width), height: Int(size.height)) else { return nil }
            let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return CaptureFormatSelection.Candidate(index: index, dimensions: dimensions, maximumFrameRate: maxRate)
        }
        guard let choice = CaptureFormatSelection.select(candidates, tier: tier) else { throw .configurationFailed }
        do {
            try device.lockForConfiguration()
            device.activeFormat = device.formats[choice.candidate.index]
            let duration = CMTime(value: 1, timescale: choice.frameRate.frames)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            throw .configurationFailed
        }
        frameRate = choice.frameRate

        if withAudio, audioInput == nil,
           let microphone = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }

        if !session.outputs.contains(videoOutput) {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: dataQueue)
            guard session.canAddOutput(videoOutput) else { throw .configurationFailed }
            session.addOutput(videoOutput)
        }
        if audioInput != nil, !session.outputs.contains(audioOutput) {
            audioOutput.setSampleBufferDelegate(self, queue: dataQueue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        }

        // Portrait 9:16 buffers; front camera mirrored like the preview (05 V03 mirror rule).
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
    }

    func startRecording(
        to file: URL, limit: CMTime?,
        onDuration: @escaping @Sendable (CMTime) -> Void, onLimitReached: @escaping @Sendable () -> Void
    ) throws(CaptureFailure) {
        let audioSettings = audioInput == nil
            ? nil : audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any]
        let recorder = SourceRecorder(
            file: file, limit: limit, audioSettings: audioSettings, frameRate: frameRate,
            onDuration: onDuration, onLimitReached: onLimitReached)
        dataQueue.sync {
            self.isStopping = false
            self.recorder = recorder
        }
    }

    /// Repeated stop requests converge on one finalization (05 V02).
    func stopRecording() async throws(CaptureFailure) -> SourceRecorder.Take {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                dataQueue.async {
                    self.pendingStop.append(continuation)
                    guard !self.isStopping else { return }
                    self.isStopping = true
                    guard let recorder = self.recorder else {
                        self.resolveStops(.failure(.emptyRecording))
                        return
                    }
                    recorder.finish { result in
                        self.dataQueue.async {
                            self.recorder = nil
                            self.resolveStops(result)
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

    private func resolveStops(_ result: Result<SourceRecorder.Take, CaptureFailure>) {
        let waiting = pendingStop
        pendingStop = []
        for continuation in waiting {
            continuation.resume(with: result.mapError { $0 as any Error })
        }
    }

    // MARK: Sample delegates (dataQueue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                frames?.store(CIImage(cvPixelBuffer: buffer), time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            }
            recorder?.appendVideo(sampleBuffer)
        } else {
            recorder?.appendAudio(sampleBuffer)
        }
    }
}
