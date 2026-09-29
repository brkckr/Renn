import Foundation

/// Versioned Beat analysis constants (05 V05). These are engineering starting values, not
/// proven DSP quality; changing any of them changes `version` and invalidates cached timelines.
public struct BeatAnalysisConfiguration: Sendable, Hashable, Codable {
    public var version = 1
    public var sampleRate = 48_000.0
    public var windowSize = 1024
    public var hopSize = 512
    public var lowBand: ClosedRange<Double> = 20...250
    public var midBand: ClosedRange<Double> = 250...2000
    public var highBand: ClosedRange<Double> = 2000...16_000
    public var silenceGateDBFS = -55.0
    public var onsetStandardDeviations = 1.5
    public var refractorySeconds = 0.160
    public var attackSeconds = 0.020
    public var releaseSeconds = 0.150
    public var normalizationSeconds = 2.0
    /// Flux is measured relative to the frame's total spectral magnitude; an onset also needs
    /// at least this relative rise. Added in v1 because a steady tone has near-zero flux
    /// variance, which let numerical noise cross a pure mean + k·σ threshold.
    public var minimumRelativeFlux = 0.05

    public init() {}

    public static let v1 = BeatAnalysisConfiguration()

    var hopSeconds: Double { Double(hopSize) / sampleRate }
    var normalizationHops: Int { max(1, Int((normalizationSeconds / hopSeconds).rounded())) }
}

/// One analysis hop. All values are finite and clamped to 0...1 (05 V05).
public struct BeatFrame: Sendable, Equatable, Codable {
    /// Index (in analysis samples) of the last sample in the window.
    public let endSample: Int64
    /// Energy envelope (attack/release follower of normalized RMS).
    public let energy: Float
    /// Onset strength; 0 when no onset fired on this hop.
    public let onset: Float
    public let low: Float
    public let mid: Float
    public let high: Float
}

/// Immutable canonical timeline for a source (05 V05). Seeking samples the same source-time
/// signal; no wall-clock or live-microphone analysis is involved.
public struct BeatTimeline: Sendable, Equatable, Codable {
    public let configuration: BeatAnalysisConfiguration
    /// Offset of the analysed audio relative to the source timebase.
    public let startOffset: RationalTime
    public let frames: [BeatFrame]

    public init(configuration: BeatAnalysisConfiguration, startOffset: RationalTime, frames: [BeatFrame]) {
        self.configuration = configuration
        self.startOffset = startOffset
        self.frames = frames
    }

    /// Source time of a frame: window end sample plus the audio offset.
    public func time(of frame: BeatFrame) -> Double {
        startOffset.approximateSeconds + Double(frame.endSample) / configuration.sampleRate
    }

    /// The latest frame at or before `time` (causal); silence before the first frame.
    public func frame(at time: RationalTime) -> BeatFrame? {
        frameIndex(at: time).map { frames[$0] }
    }

    /// Index of `frame(at:)`, or nil before the first frame.
    func frameIndex(at time: RationalTime) -> Int? {
        let local = time.approximateSeconds - startOffset.approximateSeconds
        guard local >= 0, !frames.isEmpty else { return nil }
        // Small tolerance so a time that is exactly a window end maps to that window.
        let index = Int(floor(local * configuration.sampleRate + 1e-6))
        // Frames end at windowSize - 1 + k * hop.
        let k = (index - (configuration.windowSize - 1)) / configuration.hopSize
        guard index >= configuration.windowSize - 1 else { return nil }
        return min(frames.count - 1, max(0, k))
    }

    /// The latest onset at or before `time` and no older than `window` seconds (causal).
    public func recentOnset(at time: RationalTime, within window: Double) -> (strength: Float, age: Double, index: Int)? {
        guard let current = frameIndex(at: time) else { return nil }
        let now = time.approximateSeconds
        var index = current
        while index >= 0 {
            let frame = frames[index]
            let age = now - self.time(of: frame)
            if age > window { return nil }
            if frame.onset > 0 { return (frame.onset, max(0, age), index) }
            index -= 1
        }
        return nil
    }
}

/// Streaming analyser. State persists across `process` calls, so chunking never changes the
/// result (tested). Pure Swift (a small radix-2 FFT) so it runs identically on every platform.
public struct BeatAnalyzer: Sendable {
    public let configuration: BeatAnalysisConfiguration

    private var pending: [Float] = []
    private var consumedSamples: Int64 = 0
    private var previousMagnitudes: [Float]
    private var fluxHistory: RingBuffer
    private var rmsHistory: RingBuffer
    private var lowHistory: RingBuffer
    private var midHistory: RingBuffer
    private var highHistory: RingBuffer
    private var envelope: Float = 0
    private var lastOnsetSample: Int64 = .min / 2
    private let window: [Float]
    private let fft: RealFFT
    private let attackCoefficient: Float
    private let releaseCoefficient: Float

    public init(configuration: BeatAnalysisConfiguration = .v1) {
        self.configuration = configuration
        let n = configuration.windowSize
        window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n))) }
        fft = RealFFT(size: n)
        previousMagnitudes = [Float](repeating: 0, count: n / 2 + 1)
        let hops = configuration.normalizationHops
        fluxHistory = RingBuffer(capacity: hops)
        rmsHistory = RingBuffer(capacity: hops)
        lowHistory = RingBuffer(capacity: hops)
        midHistory = RingBuffer(capacity: hops)
        highHistory = RingBuffer(capacity: hops)
        attackCoefficient = Float(exp(-configuration.hopSeconds / configuration.attackSeconds))
        releaseCoefficient = Float(exp(-configuration.hopSeconds / configuration.releaseSeconds))
    }

    /// Feeds mono Float32 PCM at `configuration.sampleRate`; returns completed frames.
    public mutating func process(_ samples: [Float]) -> [BeatFrame] {
        pending.append(contentsOf: samples)
        var frames: [BeatFrame] = []
        let n = configuration.windowSize
        let hop = configuration.hopSize
        while pending.count >= n {
            frames.append(analyzeWindow(Array(pending[0..<n])))
            pending.removeFirst(hop)
            consumedSamples += Int64(hop)
        }
        return frames
    }

    /// Convenience: analyse a whole buffer into a timeline.
    public static func timeline(
        samples: [Float], startOffset: RationalTime = .zero, configuration: BeatAnalysisConfiguration = .v1
    ) -> BeatTimeline {
        var analyzer = BeatAnalyzer(configuration: configuration)
        return BeatTimeline(configuration: configuration, startOffset: startOffset, frames: analyzer.process(samples))
    }

    private mutating func analyzeWindow(_ samples: [Float]) -> BeatFrame {
        let endSample = consumedSamples + Int64(configuration.windowSize - 1)
        var sumSquares: Float = 0
        var windowed = [Float](repeating: 0, count: samples.count)
        for index in samples.indices {
            let value = samples[index].isFinite ? samples[index] : 0
            sumSquares += value * value
            windowed[index] = value * window[index]
        }
        let rms = (sumSquares / Float(samples.count)).squareRoot()
        let dbfs = 20 * log10(Double(max(rms, 1e-9)))
        let isSilent = dbfs < configuration.silenceGateDBFS

        let magnitudes = fft.magnitudes(windowed)
        var rawFlux: Float = 0
        var total: Float = 0
        for bin in magnitudes.indices {
            let rise = magnitudes[bin] - previousMagnitudes[bin]
            if rise > 0 { rawFlux += rise }
            total += magnitudes[bin]
        }
        // Relative positive spectral flux, bounded denominator.
        let flux = Self.clamp(rawFlux / max(total, 1e-6))
        previousMagnitudes = magnitudes
        let low = bandEnergy(magnitudes, configuration.lowBand)
        let mid = bandEnergy(magnitudes, configuration.midBand)
        let high = bandEnergy(magnitudes, configuration.highBand)

        // Onset: flux above the rolling mean + k·std, outside the refractory period, not silent.
        let (fluxMean, fluxStd) = fluxHistory.meanAndStandardDeviation()
        let threshold = fluxMean + Float(configuration.onsetStandardDeviations) * fluxStd
        let refractorySamples = Int64(configuration.refractorySeconds * configuration.sampleRate)
        var onset: Float = 0
        if !isSilent, fluxHistory.count > 0, flux > threshold, flux >= Float(configuration.minimumRelativeFlux),
           endSample - lastOnsetSample >= refractorySamples {
            let denominator = max(Float(configuration.onsetStandardDeviations) * fluxStd, max(fluxMean, 1e-6))
            onset = Self.clamp((flux - threshold) / denominator + 0.5)
            lastOnsetSample = endSample
        }
        fluxHistory.append(flux)

        // Causal rolling normalization with bounded denominators.
        rmsHistory.append(rms)
        lowHistory.append(low)
        midHistory.append(mid)
        highHistory.append(high)
        let normalizedRMS = isSilent ? 0 : Self.clamp(rms / max(rmsHistory.maximum, 1e-4))
        let coefficient = normalizedRMS > envelope ? attackCoefficient : releaseCoefficient
        envelope = Self.clamp(coefficient * envelope + (1 - coefficient) * normalizedRMS)

        return BeatFrame(
            endSample: endSample,
            energy: envelope,
            onset: onset,
            low: isSilent ? 0 : Self.clamp(low / max(lowHistory.maximum, 1e-4)),
            mid: isSilent ? 0 : Self.clamp(mid / max(midHistory.maximum, 1e-4)),
            high: isSilent ? 0 : Self.clamp(high / max(highHistory.maximum, 1e-4)))
    }

    private func bandEnergy(_ magnitudes: [Float], _ band: ClosedRange<Double>) -> Float {
        let nyquist = configuration.sampleRate / 2
        let binWidth = configuration.sampleRate / Double(configuration.windowSize)
        let lower = max(0, Int((min(band.lowerBound, nyquist) / binWidth).rounded(.up)))
        let upper = min(magnitudes.count - 1, Int((min(band.upperBound, nyquist) / binWidth).rounded(.down)))
        guard upper >= lower else { return 0 }
        var sum: Float = 0
        for bin in lower...upper { sum += magnitudes[bin] * magnitudes[bin] }
        return (sum / Float(upper - lower + 1)).squareRoot()
    }

    static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

/// Fixed-capacity history for causal rolling statistics.
struct RingBuffer: Sendable {
    private var storage: [Float]
    private var start = 0
    private(set) var count = 0

    init(capacity: Int) {
        storage = [Float](repeating: 0, count: max(1, capacity))
    }

    mutating func append(_ value: Float) {
        let capacity = storage.count
        if count < capacity {
            storage[(start + count) % capacity] = value
            count += 1
        } else {
            storage[start] = value
            start = (start + 1) % capacity
        }
    }

    private var values: ArraySlice<Float> {
        let capacity = storage.count
        return ArraySlice((0..<count).map { storage[(start + $0) % capacity] })
    }

    var maximum: Float { values.max() ?? 0 }

    func meanAndStandardDeviation() -> (Float, Float) {
        guard count > 0 else { return (0, 0) }
        let slice = values
        let mean = slice.reduce(0, +) / Float(count)
        let variance = slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(count)
        return (mean, variance.squareRoot())
    }
}

/// Minimal iterative radix-2 FFT for real input of power-of-two size.
struct RealFFT: Sendable {
    let size: Int
    private let cosines: [Double]
    private let sines: [Double]
    private let bitReversed: [Int]

    init(size: Int) {
        precondition(size > 1 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        cosines = (0..<size / 2).map { cos(-2 * Double.pi * Double($0) / Double(size)) }
        sines = (0..<size / 2).map { sin(-2 * Double.pi * Double($0) / Double(size)) }
        let bits = Int(log2(Double(size)))
        bitReversed = (0..<size).map { index in
            var reversed = 0
            var value = index
            for _ in 0..<bits {
                reversed = (reversed << 1) | (value & 1)
                value >>= 1
            }
            return reversed
        }
    }

    /// Magnitudes of bins 0...size/2, scaled by 2/size.
    func magnitudes(_ input: [Float]) -> [Float] {
        var real = [Double](repeating: 0, count: size)
        var imaginary = [Double](repeating: 0, count: size)
        for index in 0..<size { real[bitReversed[index]] = Double(input[index]) }
        var length = 2
        while length <= size {
            let half = length / 2
            let step = size / length
            var blockStart = 0
            while blockStart < size {
                for offset in 0..<half {
                    let twiddle = offset * step
                    let even = blockStart + offset
                    let odd = even + half
                    let tr = cosines[twiddle] * real[odd] - sines[twiddle] * imaginary[odd]
                    let ti = cosines[twiddle] * imaginary[odd] + sines[twiddle] * real[odd]
                    real[odd] = real[even] - tr
                    imaginary[odd] = imaginary[even] - ti
                    real[even] += tr
                    imaginary[even] += ti
                }
                blockStart += length
            }
            length <<= 1
        }
        let scale = 2 / Double(size)
        return (0...size / 2).map { Float((real[$0] * real[$0] + imaginary[$0] * imaginary[$0]).squareRoot() * scale) }
    }
}

/// Canonical Beat timeline for a stored source (05 V05). The live adapter decodes the source's
/// own audio and caches by source fingerprint + algorithm configuration; intensity and mute
/// never invalidate the cache. Returns nil when the source has no usable audio.
public protocol BeatTimelineProviding: Sendable {
    func timeline(for source: SourceReference, fileURL: URL) async throws -> BeatTimeline?
}

extension BeatTimeline {
    /// Cache identity: source fingerprint, algorithm version and constants.
    public static func cacheKey(for source: SourceReference, configuration: BeatAnalysisConfiguration = .v1) -> String {
        var hasher = StableHasher()
        hasher.mix(UInt64(bitPattern: source.fingerprint.byteCount))
        hasher.mix(source.fingerprint.sampleHash)
        hasher.mix(UInt64(configuration.version))
        for value in [
            configuration.sampleRate, Double(configuration.windowSize), Double(configuration.hopSize),
            configuration.silenceGateDBFS, configuration.onsetStandardDeviations, configuration.refractorySeconds,
            configuration.attackSeconds, configuration.releaseSeconds, configuration.normalizationSeconds,
            configuration.minimumRelativeFlux, configuration.lowBand.lowerBound, configuration.lowBand.upperBound,
            configuration.midBand.lowerBound, configuration.midBand.upperBound,
            configuration.highBand.lowerBound, configuration.highBand.upperBound,
        ] {
            hasher.mix(value.bitPattern)
        }
        hasher.mix(UInt64(bitPattern: source.metadata.startOffset.value))
        hasher.mix(UInt64(source.metadata.startOffset.timescale))
        return "beat-v\(configuration.version)-" + String(hasher.value, radix: 16)
    }
}

/// FNV-1a over 64-bit words; stable across launches and platforms (unlike `Hasher`).
struct StableHasher {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func mix(_ word: UInt64) {
        var word = word
        for _ in 0..<8 {
            value ^= word & 0xFF
            value = value &* 0x0000_0100_0000_01B3
            word >>= 8
        }
    }
}

/// Bounded Beat modulation for one frame (05 V04): pulse from onsets, sway from energy, and a
/// short tape glitch after each onset. All are zero when Beat is not effective or intensity is
/// zero, so intensity 0 equals Beat off.
///
/// The glitch never changes brightness (no flashes): it displaces a few horizontal blocks and
/// splits red/blue sideways, peaks on the onset and decays within `glitchWindow`.
public struct BeatModulation: Sendable, Equatable {
    /// Brightness lift, at most 0.06 (no full-frame strobing).
    public let brightness: Double
    /// Scale above 1, at most 1.5% (no uncontrolled shake).
    public let zoom: Double
    /// Red/blue horizontal split, 0...1 (the kernel maps 1 to 6 px at a 1080 px short edge).
    public let rgbSplit: Double
    /// Sideways displacement of a few horizontal blocks, 0...1 (1 = 24 px at 1080).
    public let blockShift: Double
    /// Identifies the onset that caused the glitch, so its blocks stay put while it decays and
    /// the next hit picks different ones.
    public let glitchSeed: Double

    public static let none = BeatModulation(brightness: 0, zoom: 0)
    /// Glitch decay time constant and the age after which it is gone.
    public static let glitchDecay = 0.08
    public static let glitchWindow = 0.25

    public init(brightness: Double, zoom: Double, rgbSplit: Double = 0, blockShift: Double = 0, glitchSeed: Double = 0) {
        self.brightness = brightness
        self.zoom = zoom
        self.rgbSplit = rgbSplit
        self.blockShift = blockShift
        self.glitchSeed = glitchSeed
    }

    /// The glitch stage is skipped when both strengths are 0.
    public var hasGlitch: Bool { rgbSplit > 0 || blockShift > 0 }

    public static func at(
        _ time: RationalTime, timeline: BeatTimeline?, beat: BeatSettings, audioMuted: Bool
    ) -> BeatModulation {
        guard let timeline,
              beat.isEffective(audioMuted: audioMuted, sourceHasUsableAudio: true),
              beat.intensity > 0,
              let frame = timeline.frame(at: time)
        else { return .none }
        let intensity = beat.intensity
        let pulse = Double(max(frame.onset, frame.low * 0.5))
        var glitch = 0.0
        var glitchSeed = 0.0
        if let hit = timeline.recentOnset(at: time, within: glitchWindow) {
            glitch = min(1, Double(hit.strength) * intensity * exp(-hit.age / glitchDecay))
            glitchSeed = Double(hit.index % 4096)
        }
        return BeatModulation(
            brightness: min(0.06, 0.06 * intensity * pulse),
            zoom: min(0.015, 0.015 * intensity * Double(frame.energy) * pulse),
            rgbSplit: glitch,
            blockShift: glitch * 0.8,
            glitchSeed: glitchSeed)
    }
}
