/// Beat is controlled by enable + intensity and driven only by source audio (01 P06).
public struct BeatSettings: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    /// 0...1; intensity 0 must render identically to Beat off (05 V04).
    public var intensity: Double

    public init(isEnabled: Bool, intensity: Double) {
        self.isEnabled = isEnabled
        self.intensity = intensity.isFinite ? Swift.min(1, Swift.max(0, intensity)) : 0
    }

    public static let `default` = BeatSettings(isEnabled: false, intensity: 0.5)

    /// `effectiveBeat = beatEnabled && !audioMuted && sourceHasUsableAudio` (01 P06).
    /// Muting never mutates `isEnabled`/`intensity`, so unmute restores the previous choice.
    public func isEffective(audioMuted: Bool, sourceHasUsableAudio: Bool) -> Bool {
        isEnabled && !audioMuted && sourceHasUsableAudio
    }

    public func effectiveIntensity(audioMuted: Bool, sourceHasUsableAudio: Bool) -> Double {
        isEffective(audioMuted: audioMuted, sourceHasUsableAudio: sourceHasUsableAudio) ? intensity : 0
    }
}
