/// The persisted creative recipe of a project (05 V07). Rendering (M03) consumes it as an
/// immutable snapshot. There are deliberately no trim/crop/timeline fields (01 P12).
public struct Recipe: Sendable, Equatable, Codable {
    public static let currentVersion = 1
    /// Initial renderer version; bumped when rendering semantics change (05 V04).
    public static let currentRenderVersion = 1
    public static let currentBeatAlgorithmVersion = 1

    public var version: Int
    public var renderVersion: Int
    public var lookID: LookID?
    public var lookVersion: Int?
    /// Resolved Look parameters, persisted so later catalog tuning cannot silently alter
    /// existing projects (05 V04).
    public var lookParameters: [String: Double]
    public var intensity: LookIntensity
    /// Stable per-project seed for deterministic procedural effects.
    public var seed: UInt64
    public var beat: BeatSettings
    public var beatAlgorithmVersion: Int
    public var audioMuted: Bool
    public var indicators: IndicatorSettings
    /// Present only for Dual-Cam projects.
    public var dualLayout: DualCameraLayout?

    public init(
        version: Int = Recipe.currentVersion,
        renderVersion: Int = Recipe.currentRenderVersion,
        lookID: LookID?,
        lookVersion: Int?,
        lookParameters: [String: Double] = [:],
        intensity: LookIntensity,
        seed: UInt64,
        beat: BeatSettings = .default,
        beatAlgorithmVersion: Int = Recipe.currentBeatAlgorithmVersion,
        audioMuted: Bool = false,
        indicators: IndicatorSettings,
        dualLayout: DualCameraLayout? = nil
    ) {
        self.version = version
        self.renderVersion = renderVersion
        self.lookID = lookID
        self.lookVersion = lookVersion
        self.lookParameters = lookParameters
        self.intensity = intensity
        self.seed = seed
        self.beat = beat
        self.beatAlgorithmVersion = beatAlgorithmVersion
        self.audioMuted = audioMuted
        self.indicators = indicators
        self.dualLayout = dualLayout
    }

    /// Recipe for a new project: the chosen Look at its catalog default intensity, Beat off,
    /// indicators off with the creation date as the stamp (01 P04/P07).
    public static func initial(
        look: LookDefinition?,
        creationStamp: StampDate,
        seed: UInt64,
        dualLayout: DualCameraLayout? = nil
    ) -> Recipe {
        Recipe(
            lookID: look?.id,
            lookVersion: look?.version,
            // Snapshot: later catalog tuning never alters this project (05 V04).
            lookParameters: look?.parameters ?? [:],
            intensity: look?.defaultIntensity ?? .off,
            seed: seed,
            indicators: IndicatorSettings(stampDate: creationStamp),
            dualLayout: dualLayout)
    }

    /// The recipe with another Look (01 P04): its version, a fresh parameter snapshot and its
    /// default intensity. Beat, mute, indicators, seed and the Dual-Cam layout are untouched.
    /// Re-selecting the current Look keeps the saved intensity.
    public func switchingLook(to look: LookDefinition?) -> Recipe {
        guard look?.id != lookID || look?.version != lookVersion else { return self }
        var result = self
        result.lookID = look?.id
        result.lookVersion = look?.version
        result.lookParameters = look?.parameters ?? [:]
        result.intensity = look?.defaultIntensity ?? .off
        return result
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case unsupportedVersion(Int)
        case nonFiniteParameter(String)
        case invalidVersionNumber
        case invalidSwapTimeline
    }

    /// Parameter value applied at the recipe's intensity (linear, 0 at intensity 0).
    public func effectiveParameter(_ key: String) -> Double {
        (lookParameters[key] ?? 0) * intensity.value
    }

    /// A shape parameter (`LookParameter.unscaled`), independent of intensity, or `fallback` when the
    /// Look does not set it.
    public func shapeParameter(_ key: String, fallback: Double) -> Double {
        lookParameters[key] ?? fallback
    }

    public func validate() throws(ValidationError) {
        guard (1...Recipe.currentVersion).contains(version) else { throw .unsupportedVersion(version) }
        guard renderVersion > 0, beatAlgorithmVersion > 0, lookVersion.map({ $0 > 0 }) ?? true else {
            throw .invalidVersionNumber
        }
        for (name, value) in lookParameters where !value.isFinite {
            throw .nonFiniteParameter(name)
        }
        if let dualLayout, !dualLayout.isValidTimeline {
            throw .invalidSwapTimeline
        }
    }
}

/// Independent REC / PLAY / Battery / Date indicators (01 P07). Baseline: all off.
public struct IndicatorSettings: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public var version: Int
    public var showsRec: Bool
    public var showsPlay: Bool
    public var showsBattery: Bool
    public var showsDate: Bool
    /// Kept when Date is turned off, so turning it back on restores the selection.
    public var stampDate: StampDate

    public init(
        version: Int = IndicatorSettings.currentVersion,
        showsRec: Bool = false,
        showsPlay: Bool = false,
        showsBattery: Bool = false,
        showsDate: Bool = false,
        stampDate: StampDate
    ) {
        self.version = version
        self.showsRec = showsRec
        self.showsPlay = showsPlay
        self.showsBattery = showsBattery
        self.showsDate = showsDate
        self.stampDate = stampDate
    }
}

/// Dual-Cam layout: fixed pre-record corner and ordered live swap events (01 P05, 05 V03).
public struct DualCameraLayout: Sendable, Equatable, Codable {
    public enum Camera: String, Sendable, Codable {
        case rear
        case front
    }

    public enum Corner: String, Sendable, Codable, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    public struct SwapEvent: Sendable, Equatable, Codable {
        public let sourceTime: RationalTime
        public let mainCamera: Camera

        public init(sourceTime: RationalTime, mainCamera: Camera) {
            self.sourceTime = sourceTime
            self.mainCamera = mainCamera
        }
    }

    public var insetCorner: Corner
    public var initialMainCamera: Camera
    public private(set) var swaps: [SwapEvent]

    /// Baseline: rear main, front inset top-right.
    public init(insetCorner: Corner = .topRight, initialMainCamera: Camera = .rear, swaps: [SwapEvent] = []) {
        self.insetCorner = insetCorner
        self.initialMainCamera = initialMainCamera
        self.swaps = swaps
    }

    /// Main camera at a media time: the last swap at or before `time` wins.
    public func mainCamera(at time: RationalTime) -> Camera {
        swaps.last { $0.sourceTime <= time }?.mainCamera ?? initialMainCamera
    }

    /// Records a live swap. Impossible inputs are coalesced: non-increasing times and swaps
    /// to the camera that is already main are ignored. Returns whether it was recorded.
    @discardableResult
    public mutating func recordSwap(at time: RationalTime) -> Bool {
        guard time >= .zero else { return false }
        if let last = swaps.last, time <= last.sourceTime { return false }
        let current = swaps.last?.mainCamera ?? initialMainCamera
        swaps.append(SwapEvent(sourceTime: time, mainCamera: current == .rear ? .front : .rear))
        return true
    }

    var isValidTimeline: Bool {
        var previous: RationalTime?
        var main = initialMainCamera
        for swap in swaps {
            if swap.sourceTime < .zero { return false }
            if let previous, swap.sourceTime <= previous { return false }
            if swap.mainCamera == main { return false }
            previous = swap.sourceTime
            main = swap.mainCamera
        }
        return true
    }
}
