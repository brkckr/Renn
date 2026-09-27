import Foundation
import Testing
@testable import RENNDomain

@Suite("Beat analysis v1 (05 V05)")
struct BeatAnalysisTests {
    private let rate = 48_000.0

    private func sine(_ frequency: Double, seconds: Double, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    /// Short decaying noise bursts at `times` over near-silence.
    private func clicks(at times: [Double], seconds: Double) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        var generator = SystemRandomNumberGenerator()
        for time in times {
            let start = Int(time * rate)
            for offset in 0..<Int(0.02 * rate) where start + offset < samples.count {
                let decay = Float(exp(-Double(offset) / (0.004 * rate)))
                samples[start + offset] = decay * Float.random(in: -0.8...0.8, using: &generator)
            }
        }
        return samples
    }

    @Test func fftFindsTheToneBin() {
        let fft = RealFFT(size: 1024)
        let bin = 64 // 64 * 48000/1024 = 3000 Hz
        let tone = (0..<1024).map { Float(sin(2 * .pi * Double(bin) * Double($0) / 1024)) }
        let magnitudes = fft.magnitudes(tone)
        #expect(magnitudes.firstIndex(of: magnitudes.max()!) == bin)
        #expect(abs(magnitudes[bin] - 1) < 0.01)
    }

    @Test func silenceProducesNoOnsetsAndZeroEnergy() {
        let timeline = BeatAnalyzer.timeline(samples: [Float](repeating: 0, count: Int(3 * rate)))
        #expect(!timeline.frames.isEmpty)
        #expect(timeline.frames.allSatisfy { $0.onset == 0 && $0.energy == 0 && $0.low == 0 })
    }

    @Test func lowLevelNoiseBelowTheGateIsNotAmplifiedIntoBeats() {
        var generator = SystemRandomNumberGenerator()
        let quiet = (0..<Int(3 * rate)).map { _ in Float.random(in: -0.0005...0.0005, using: &generator) }
        let timeline = BeatAnalyzer.timeline(samples: quiet)
        #expect(timeline.frames.allSatisfy { $0.onset == 0 })
    }

    @Test func clickTrainOnsetsLandNearTheClicks() {
        let clickTimes = stride(from: 0.5, to: 4.0, by: 0.5).map { $0 }
        let timeline = BeatAnalyzer.timeline(samples: clicks(at: clickTimes, seconds: 4.2))
        let onsetTimes = timeline.frames.filter { $0.onset > 0 }.map { timeline.time(of: $0) }
        #expect(onsetTimes.count >= clickTimes.count - 1 && onsetTimes.count <= clickTimes.count)
        let windowSeconds = 1024 / rate
        for onset in onsetTimes {
            // The window containing the click ends at most one window after it.
            #expect(clickTimes.contains { onset >= $0 && onset <= $0 + windowSeconds + 512 / rate })
        }
    }

    @Test func refractoryPeriodSuppressesDoubleTriggers() {
        let timeline = BeatAnalyzer.timeline(samples: clicks(at: [0.5, 0.56, 1.5], seconds: 2))
        let onsets = timeline.frames.filter { $0.onset > 0 }.map { timeline.time(of: $0) }
        for (a, b) in zip(onsets, onsets.dropFirst()) {
            #expect(b - a >= 0.160 - 1e-9)
        }
    }

    @Test func steadyToneDoesNotKeepFiring() {
        let timeline = BeatAnalyzer.timeline(samples: sine(440, seconds: 4))
        let lateOnsets = timeline.frames.filter { $0.onset > 0 && timeline.time(of: $0) > 0.5 }
        #expect(lateOnsets.isEmpty)
        #expect((timeline.frames.last?.energy ?? 0) > 0.5, "Sustained energy is tracked")
    }

    @Test func bandsSeparateLowAndHighContent() {
        let low = BeatAnalyzer.timeline(samples: sine(100, seconds: 1)).frames.last!
        let high = BeatAnalyzer.timeline(samples: sine(6000, seconds: 1)).frames.last!
        #expect(low.low > 0.5 && low.high < 0.2)
        #expect(high.high > 0.5 && high.low < 0.2)
    }

    @Test func chunkingNeverChangesTheResult() {
        let samples = clicks(at: [0.3, 0.9, 1.4], seconds: 2).enumerated().map { $0.element + 0.1 * Float(sin(Double($0.offset) / 20)) }
        let whole = BeatAnalyzer.timeline(samples: samples).frames
        var analyzer = BeatAnalyzer()
        var chunked: [BeatFrame] = []
        var index = 0
        let sizes = [1, 700, 5, 4096, 333, 1023, 2048]
        var sizeIndex = 0
        while index < samples.count {
            let size = sizes[sizeIndex % sizes.count]
            sizeIndex += 1
            let end = min(samples.count, index + size)
            chunked += analyzer.process(Array(samples[index..<end]))
            index = end
        }
        #expect(chunked == whole)
    }

    @Test func outputsAreFiniteAndClampedEvenForBadInput() {
        var samples = sine(200, seconds: 1, amplitude: 1)
        samples[1000] = .nan
        samples[2000] = .infinity
        let frames = BeatAnalyzer.timeline(samples: samples).frames
        for frame in frames {
            for value in [frame.energy, frame.onset, frame.low, frame.mid, frame.high] {
                #expect(value.isFinite && value >= 0 && value <= 1)
            }
        }
    }

    @Test func timestampsAreWindowEndsPlusSourceOffset() throws {
        let timeline = BeatAnalyzer.timeline(
            samples: sine(440, seconds: 0.1), startOffset: try RationalTime(value: 1, timescale: 2))
        let first = try #require(timeline.frames.first)
        #expect(first.endSample == 1023)
        #expect(abs(timeline.time(of: first) - (0.5 + 1023 / rate)) < 1e-9)
        #expect(timeline.frame(at: .zero) == nil, "Nothing before the audio starts")
        #expect(timeline.frame(at: .seconds(10)) == timeline.frames.last)
    }

    @Test func configurationIsVersioned() {
        #expect(BeatAnalysisConfiguration.v1.version == 1)
        var changed = BeatAnalysisConfiguration.v1
        changed.onsetStandardDeviations = 2
        #expect(changed != .v1, "Changed constants make a different cache key")
    }
}
