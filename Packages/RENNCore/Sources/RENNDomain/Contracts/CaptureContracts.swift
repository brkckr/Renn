import Foundation

public enum CameraPosition: String, Sendable, Equatable, CaseIterable {
    case rear
    case front
}

public enum CapturePermission: Sendable, Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

/// Contextual permission requests (06 C06): asked only when a capture action is requested.
public protocol CapturePermissionProviding: Sendable {
    func cameraStatus() async -> CapturePermission
    func microphoneStatus() async -> CapturePermission
    func requestCamera() async -> Bool
    func requestMicrophone() async -> Bool
}

public enum CaptureFailure: Error, Sendable, Equatable {
    case cameraUnavailable
    case configurationFailed
    case recordingFailed
    case insufficientStorage
    /// Nothing usable was recorded (e.g. stopped before the first frame).
    case emptyRecording
}

/// Finalized clean source of one take (05 V02). Pixels contain no app UI or countdown.
public struct RecordedTake: Sendable, Equatable {
    public let file: URL
    public let duration: RationalTime
    public let displayDimensions: PixelDimensions
    public let frameRate: FrameRate
    public let hasAudio: Bool
    public let isMirrored: Bool
    /// The take ended because of an interruption; it was finalized best-effort.
    public let wasInterrupted: Bool

    public init(
        file: URL, duration: RationalTime, displayDimensions: PixelDimensions, frameRate: FrameRate,
        hasAudio: Bool, isMirrored: Bool, wasInterrupted: Bool
    ) {
        self.file = file
        self.duration = duration
        self.displayDimensions = displayDimensions
        self.frameRate = frameRate
        self.hasAudio = hasAudio
        self.isMirrored = isMirrored
        self.wasInterrupted = wasInterrupted
    }
}

public enum CaptureEvent: Sendable, Equatable {
    /// Recorded media time, measured from sample timestamps (never a UI timer).
    case recordedDuration(RationalTime)
    /// The Free limit was reached; the recorder stopped accepting samples.
    case limitReached
    /// Audio route change, phone call, background or system pressure (05 V02).
    case interrupted
}

/// Single-camera capture (M02). Implementations own the capture graph on their own serialized
/// queues; repeated stop requests converge on one finalization (05 V02).
@MainActor
public protocol CaptureControlling: AnyObject {
    var events: AsyncStream<CaptureEvent> { get }
    /// Configures a portrait 9:16 session for `position`; `withAudio` false records silently.
    func prepare(position: CameraPosition, withAudio: Bool) async throws(CaptureFailure)
    /// Pre-record only (01 P05).
    func switchCamera(to position: CameraPosition) async throws(CaptureFailure)
    /// Starts writing clean media to `file`. `maximumDuration` is the Free limit, nil for Pro.
    func startRecording(to file: URL, maximumDuration: RationalTime?) async throws(CaptureFailure)
    func stopRecording() async throws(CaptureFailure) -> RecordedTake
    /// Releases camera and microphone when leaving the flow.
    func tearDown()
}

/// Finalized Dual-Cam take (05 V03): two clean sources on one capture clock. Exactly one of them
/// (the rear) carries the shared microphone track.
public struct DualRecordedTake: Sendable, Equatable {
    public let rear: RecordedTake
    public let front: RecordedTake
    /// First-sample times on the shared capture clock, relative to the earlier of the two.
    public let rearStart: RationalTime
    public let frontStart: RationalTime

    public init(rear: RecordedTake, front: RecordedTake, rearStart: RationalTime, frontStart: RationalTime) {
        self.rear = rear
        self.front = front
        self.rearStart = rearStart
        self.frontStart = frontStart
    }
}

/// Simultaneous front/rear capture (01 P05, 05 V03). A failure of either stream stops the whole
/// take coherently; there is no hidden single-camera substitution.
@MainActor
public protocol DualCaptureControlling: AnyObject {
    var events: AsyncStream<CaptureEvent> { get }
    /// Configures the multi-camera session with the validated 1080p30 format pair.
    func prepare(withAudio: Bool) async throws(CaptureFailure)
    /// Starts both clean writers. `maximumDuration` is the Free limit, nil for Pro.
    func startRecording(rearFile: URL, frontFile: URL, maximumDuration: RationalTime?) async throws(CaptureFailure)
    /// Composition time of the newest frame of the running take (both sources started), else nil.
    /// Live swaps are stamped with it, so preview and export replay them on the same frame.
    func currentCompositionTime() async -> RationalTime?
    /// Finalizes both files. Repeated calls converge on one finalization.
    func stopRecording() async throws(CaptureFailure) -> DualRecordedTake
    func tearDown()
}
