/// Inspected properties of a prepared source that output policy depends on.
/// Produced by the media preparer (M02); pure value, no AVFoundation types.
public struct SourceMediaProfile: Sendable, Hashable, Codable {
    public var displayDimensions: PixelDimensions
    public var frameRate: FrameRate
    public var duration: RationalTime
    public var hasUsableAudio: Bool

    public init(
        displayDimensions: PixelDimensions,
        frameRate: FrameRate,
        duration: RationalTime,
        hasUsableAudio: Bool
    ) {
        self.displayDimensions = displayDimensions
        self.frameRate = frameRate
        self.duration = duration
        self.hasUsableAudio = hasUsableAudio
    }
}
