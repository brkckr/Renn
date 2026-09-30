import AVFoundation
import Foundation
import RENNDomain

/// Decodes a stored source's own audio track and builds the canonical Beat timeline (05 V05).
/// Never listens to the live microphone or other apps. Timelines are cached in
/// `Caches/RENN/Beat/<key>.json` (recomputable, excluded from backup by the system).
actor AVBeatTimelineProvider: BeatTimelineProviding {
    private let configuration: BeatAnalysisConfiguration
    private let cacheDirectory: URL
    private var inFlight: [String: Task<BeatTimeline?, any Error>] = [:]

    init(configuration: BeatAnalysisConfiguration = .v1,
         cacheDirectory: URL = URL.cachesDirectory.appendingPathComponent("RENN/Beat", isDirectory: true)) {
        self.configuration = configuration
        self.cacheDirectory = cacheDirectory
    }

    func timeline(for source: SourceReference, fileURL: URL) async throws -> BeatTimeline? {
        guard source.metadata.hasUsableAudio else { return nil }
        let key = BeatTimeline.cacheKey(for: source, configuration: configuration)
        if let cached = loadCached(key) { return cached }
        if let running = inFlight[key] { return try await running.value }
        let configuration = configuration
        let offset = source.metadata.startOffset
        let task = Task<BeatTimeline?, any Error>.detached(priority: .utility) {
            try await Self.analyze(fileURL, configuration: configuration, startOffset: offset)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let timeline = try await task.value
        if let timeline { store(timeline, key: key) }
        return timeline
    }

    /// Timeline of a bundled demo clip's own audio (owner-approved onboarding Beat scene), cached
    /// like a source's under `key` and the analysis version. Never a project and never the microphone.
    func bundledTimeline(for url: URL, key: String) async throws -> BeatTimeline? {
        let cacheKey = "\(key)-v\(configuration.version)"
        if let cached = loadCached(cacheKey) { return cached }
        if let running = inFlight[cacheKey] { return try await running.value }
        let configuration = configuration
        let task = Task<BeatTimeline?, any Error>.detached(priority: .utility) {
            try await Self.analyze(url, configuration: configuration, startOffset: .zero)
        }
        inFlight[cacheKey] = task
        defer { inFlight[cacheKey] = nil }
        let timeline = try await task.value
        if let timeline { store(timeline, key: cacheKey) }
        return timeline
    }

    private static func analyze(
        _ url: URL, configuration: BeatAnalysisConfiguration, startOffset: RationalTime
    ) async throws -> BeatTimeline? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        // Mono Float32 downmix at the analysis rate; the original audio is left untouched.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: configuration.sampleRate,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }

        var analyzer = BeatAnalyzer(configuration: configuration)
        var frames: [BeatFrame] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            floats.withUnsafeMutableBytes { bytes in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            frames += analyzer.process(floats)
        }
        guard reader.status == .completed else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        return BeatTimeline(configuration: configuration, startOffset: startOffset, frames: frames)
    }

    private func loadCached(_ key: String) -> BeatTimeline? {
        let url = cacheDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BeatTimeline.self, from: data)
    }

    private func store(_ timeline: BeatTimeline, key: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(timeline) else { return }
        try? data.write(to: cacheDirectory.appendingPathComponent("\(key).json"), options: .atomic)
    }
}
