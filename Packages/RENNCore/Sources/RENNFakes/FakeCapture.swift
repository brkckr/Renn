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
