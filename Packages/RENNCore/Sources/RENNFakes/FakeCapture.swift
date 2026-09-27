import Foundation
import RENNDomain

@MainActor
public final class FakeCaptureController: CaptureControlling {
    public let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    public var prepareFailure: CaptureFailure?
    public var stopResult: Result<RecordedTake, CaptureFailure>?
    public private(set) var preparedPositions: [CameraPosition] = []
    public private(set) var preparedWithAudio: [Bool] = []
    public private(set) var recordingFile: URL?
    public private(set) var maximumDuration: RationalTime?
    public private(set) var stopCount = 0
    public private(set) var tornDown = false

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
    }

    public func emit(_ event: CaptureEvent) {
        continuation.yield(event)
    }

    public func prepare(position: CameraPosition, withAudio: Bool) async throws(CaptureFailure) {
        if let prepareFailure { throw prepareFailure }
        preparedPositions.append(position)
        preparedWithAudio.append(withAudio)
    }

    public func switchCamera(to position: CameraPosition) async throws(CaptureFailure) {
        preparedPositions.append(position)
    }

    public func startRecording(to file: URL, maximumDuration: RationalTime?) async throws(CaptureFailure) {
        recordingFile = file
        self.maximumDuration = maximumDuration
    }

    public func stopRecording() async throws(CaptureFailure) -> RecordedTake {
        stopCount += 1
        if let stopResult { return try stopResult.get() }
        return RecordedTake(
            file: recordingFile ?? URL(fileURLWithPath: "/take.mov"), duration: .seconds(5),
            displayDimensions: try! PixelDimensions(width: 1080, height: 1920), frameRate: .fps(30),
            hasAudio: preparedWithAudio.last ?? false, isMirrored: preparedPositions.last == .front,
            wasInterrupted: false)
    }

    public func tearDown() {
        tornDown = true
    }
}

public actor FakeCapturePermissions: CapturePermissionProviding {
    public var camera: CapturePermission
    public var microphone: CapturePermission
    public var grantOnRequest: Bool
    public private(set) var cameraRequests = 0

    public init(camera: CapturePermission = .authorized, microphone: CapturePermission = .authorized, grantOnRequest: Bool = true) {
        self.camera = camera
        self.microphone = microphone
        self.grantOnRequest = grantOnRequest
    }

    public func cameraStatus() async -> CapturePermission { camera }
    public func microphoneStatus() async -> CapturePermission { microphone }
    public func requestCamera() async -> Bool {
        cameraRequests += 1
        camera = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }
    public func requestMicrophone() async -> Bool {
        microphone = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }
}

@MainActor
public final class FakeDualCaptureController: DualCaptureControlling {
    public let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    public var prepareFailure: CaptureFailure?
    public var startFailure: CaptureFailure?
    public var stopResult: Result<DualRecordedTake, CaptureFailure>?
    /// What `currentCompositionTime` reports; tests advance it to stamp swaps.
    public var compositionTime: RationalTime?
    public var frontStart: RationalTime = .zero
    public private(set) var preparedWithAudio: [Bool] = []
    public private(set) var files: (rear: URL, front: URL)?
    public private(set) var maximumDuration: RationalTime?
    public private(set) var stopCount = 0
    public private(set) var tornDown = false

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
    }

    public func emit(_ event: CaptureEvent) {
        continuation.yield(event)
    }

    public func prepare(withAudio: Bool) async throws(CaptureFailure) {
        if let prepareFailure { throw prepareFailure }
        preparedWithAudio.append(withAudio)
    }

    public func startRecording(rearFile: URL, frontFile: URL, maximumDuration: RationalTime?) async throws(CaptureFailure) {
        if let startFailure { throw startFailure }
        files = (rearFile, frontFile)
        self.maximumDuration = maximumDuration
    }

    public func currentCompositionTime() async -> RationalTime? {
        compositionTime
    }

    public func stopRecording() async throws(CaptureFailure) -> DualRecordedTake {
        stopCount += 1
        if let stopResult { return try stopResult.get() }
        func take(_ url: URL?, audio: Bool, mirrored: Bool) -> RecordedTake {
            RecordedTake(
                file: url ?? URL(fileURLWithPath: "/take.mov"), duration: .seconds(5),
                displayDimensions: try! PixelDimensions(width: 1080, height: 1920), frameRate: .fps(30),
                hasAudio: audio, isMirrored: mirrored, wasInterrupted: false)
        }
        return DualRecordedTake(
            rear: take(files?.rear, audio: preparedWithAudio.last ?? false, mirrored: false),
            front: take(files?.front, audio: false, mirrored: true),
            rearStart: .zero, frontStart: frontStart)
    }

    public func tearDown() {
        tornDown = true
    }
}
