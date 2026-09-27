import AVFoundation
import CoreImage
import os
import RENNDomain

/// Errors surfaced by one render/encode run.
enum ExportWorkerError: Error, Equatable {
    case cannotRead
    case cannotWrite
    case cancelled
    case renderFailed
    case validationFailed(String)
}

/// One export render: AVAssetReader → RenderEngine → AVAssetWriter (05 V04/V09).
///
/// Concurrency: all reader/writer/pixel-buffer state is confined to `queue` (an explicit
/// serialized executor, 04 A05). The class is `@unchecked Sendable` only for that reason;
/// nothing is touched off the queue except the lock-protected cancellation flag.
/// Memory stays bounded: frames are pulled one at a time and rendered into the adaptor's pool.
final class ExportWorker: @unchecked Sendable {
    struct Job {
        var plan: ExportPlan
        var sourceURL: URL
        var outputURL: URL
        var engine: RenderEngine
        var watermark: CIImage?
        var watermarkAspect: Double
        var isHDRSource: Bool
        /// Canonical Beat timeline of the source (same one the preview uses).
        var beatTimeline: BeatTimeline?
    }

    private let job: Job
    private let queue = DispatchQueue(label: "renn.export.worker", qos: .userInitiated)
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    init(job: Job) {
        self.job = job
    }

    func cancel() {
        cancelled.withLock { $0 = true }
    }

    private var isCancelled: Bool { cancelled.withLock { $0 } }

    /// Runs the render; `progress` receives measured rendered seconds.
    func run(progress: @escaping @Sendable (Double) -> Void) async throws -> RationalTime {
        let asset = AVURLAsset(url: job.sourceURL)
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let transform: CGAffineTransform
        let duration: CMTime
        let origin: CMTime
        let audioFormat: CMFormatDescription?
        do {
            guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw ExportWorkerError.cannotRead }
            videoTrack = video
            audioTrack = job.plan.includesAudio ? try await asset.loadTracks(withMediaType: .audio).first : nil
            transform = try await video.load(.preferredTransform)
            // One shared origin for both tracks keeps the source A/V offset (05 V02).
            origin = try await video.load(.timeRange).start
            duration = try await asset.load(.duration)
            audioFormat = try await audioTrack?.load(.formatDescriptions).first
        } catch {
            throw ExportWorkerError.cannotRead
        }
        let pipeline = try makePipeline(
            asset: asset, videoTrack: videoTrack, audioTrack: audioTrack, audioFormat: audioFormat)

        let totalSeconds = duration.seconds
        let orientation = RenderEngine.orientation(for: transform)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.start(
                    pipeline, origin: origin, orientation: orientation, totalSeconds: totalSeconds,
                    progress: progress
                ) { result in
                    if case .failure = result {
                        try? FileManager.default.removeItem(at: self.job.outputURL)
                    }
                    continuation.resume(with: result)
                }
            }
        }
    }

    // MARK: Pipeline

    /// Reader/writer graph, confined to `queue` after creation.
    private final class Pipeline: @unchecked Sendable {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let videoOutput: AVAssetReaderTrackOutput
        let audioOutput: AVAssetReaderTrackOutput?
        let videoInput: AVAssetWriterInput
        let audioInput: AVAssetWriterInput?
        let adaptor: AVAssetWriterInputPixelBufferAdaptor

        init(
            reader: AVAssetReader, writer: AVAssetWriter, videoOutput: AVAssetReaderTrackOutput,
            audioOutput: AVAssetReaderTrackOutput?, videoInput: AVAssetWriterInput,
            audioInput: AVAssetWriterInput?, adaptor: AVAssetWriterInputPixelBufferAdaptor
        ) {
            self.reader = reader
            self.writer = writer
            self.videoOutput = videoOutput
            self.audioOutput = audioOutput
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.adaptor = adaptor
        }
    }

    private func makePipeline(
        asset: AVAsset, videoTrack: AVAssetTrack, audioTrack: AVAssetTrack?, audioFormat: CMFormatDescription?
    ) throws -> Pipeline {
        let policy = job.plan.policy
        let width = policy.dimensions.width
        let height = policy.dimensions.height

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            try? FileManager.default.removeItem(at: job.outputURL)
            writer = try AVAssetWriter(outputURL: job.outputURL, fileType: .mp4)
        } catch {
            throw ExportWorkerError.cannotWrite
        }

        var videoSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        if job.isHDRSource {
            // Request an SDR Rec.709 conversion from the decoder. Tone-mapping quality of this
            // route is an M02 device-validation item (05 V01); the summary discloses HDR → SDR.
            videoSettings[AVVideoColorPropertiesKey] = Self.rec709
        }
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoSettings)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ExportWorkerError.cannotRead }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack {
            let basic = audioFormat.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            let channels = max(1, min(2, Int(basic?.mChannelsPerFrame ?? 2)))
            let sampleRate = basic.map { $0.mSampleRate > 0 ? $0.mSampleRate : 48_000 } ?? 48_000
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sampleRate,
            ])
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sampleRate,
                AVEncoderBitRateKey: channels == 1 ? 96_000 : 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioOutput = output
                audioInput = input
            }
        }

        let useHEVC = width * height > 1920 * 1080 || policy.frameRate.approximateFPS > 31
        let pixelsPerSecond = Double(width * height) * policy.frameRate.approximateFPS
        let bitRate = Int(pixelsPerSecond * (useHEVC ? 0.07 : 0.11))
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: Self.rec709,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(1_000_000, bitRate),
                AVVideoExpectedSourceFrameRateKey: Int(policy.frameRate.approximateFPS.rounded()),
                AVVideoAllowFrameReorderingKey: true,
            ] as [String: Any],
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ExportWorkerError.cannotWrite }
        writer.add(videoInput)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ])
        return Pipeline(
            reader: reader, writer: writer, videoOutput: videoOutput, audioOutput: audioOutput,
            videoInput: videoInput, audioInput: audioInput, adaptor: adaptor)
    }

    /// Starts reading/writing. Video and audio drain on their own queues through
    /// `requestMediaDataWhenReady`, so a full audio buffer can never block video decoding (and
    /// vice versa) while the writer waits to interleave. Completion is called exactly once.
    private func start(
        _ pipeline: Pipeline, origin: CMTime, orientation: CGImagePropertyOrientation, totalSeconds: Double,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<RationalTime, any Error>) -> Void
    ) {
        guard pipeline.reader.startReading(), pipeline.writer.startWriting() else {
            pipeline.reader.cancelReading()
            completion(.failure(ExportWorkerError.cannotRead))
            return
        }
        pipeline.writer.startSession(atSourceTime: .zero)

        let state = PumpState()
        let group = DispatchGroup()
        let outputSize = CGSize(width: job.plan.policy.dimensions.width, height: job.plan.policy.dimensions.height)
        let watermarkFrame = job.watermark.map { _ in
            WatermarkLayout(output: job.plan.policy.dimensions, aspectRatio: job.watermarkAspect).frame
        }
        // Indicators avoid the watermark reservation; laid out and drawn once per job.
        let indicatorLayout = IndicatorLayout.resolve(
            output: job.plan.policy.dimensions, settings: job.plan.recipe.indicators,
            reserved: watermarkFrame.map { [$0] } ?? [])
        let inputs = RenderInputs(
            outputSize: outputSize, watermarkFrame: watermarkFrame,
            indicators: IndicatorRenderer.overlays(for: indicatorLayout, settings: job.plan.recipe.indicators))

        let videoQueue = DispatchQueue(label: "renn.export.video", qos: .userInitiated)
        let audioQueue = DispatchQueue(label: "renn.export.audio", qos: .userInitiated)
        let videoTrack = VideoPumpState(limiter: CadenceLimiter(outputRate: job.plan.policy.frameRate))

        group.enter()
        pipeline.videoInput.requestMediaDataWhenReady(on: videoQueue) { [self] in
            while pipeline.videoInput.isReadyForMoreMediaData, !videoTrack.done {
                if isCancelled || state.hasFailed {
                    state.fail(isCancelled ? ExportWorkerError.cancelled : ExportWorkerError.cannotWrite)
                    videoTrack.finish(pipeline.videoInput, group)
                    return
                }
                guard let sample = pipeline.videoOutput.copyNextSampleBuffer() else {
                    if pipeline.reader.status == .failed { state.fail(ExportWorkerError.cannotRead) }
                    videoTrack.finish(pipeline.videoInput, group)
                    return
                }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let relative = CMTimeSubtract(pts, origin)
                guard let buffer = CMSampleBufferGetImageBuffer(sample),
                      let mediaTime = try? RationalTime(value: relative.value, timescale: relative.timescale),
                      videoTrack.limiter.shouldKeep(presentationTime: mediaTime)
                else { continue }
                let appended: Bool = autoreleasepool {
                    guard let pool = pipeline.adaptor.pixelBufferPool else { return false }
                    var outputBuffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
                    guard let outputBuffer else { return false }
                    let image = job.engine.image(for: RenderEngine.FrameRequest(
                        source: CIImage(cvPixelBuffer: buffer), orientation: orientation,
                        recipe: job.plan.recipe, time: mediaTime, outputSize: inputs.outputSize,
                        watermark: job.watermark, watermarkFrame: inputs.watermarkFrame,
                        beat: BeatModulation.at(
                            mediaTime, timeline: job.beatTimeline, beat: job.plan.recipe.beat,
                            audioMuted: job.plan.recipe.audioMuted),
                        indicators: inputs.indicators))
                    job.engine.render(image, to: outputBuffer)
                    // Source timestamps are kept; only frames above the cadence ceiling are skipped.
                    return pipeline.adaptor.append(outputBuffer, withPresentationTime: relative)
                }
                guard appended else {
                    state.fail(ExportWorkerError.renderFailed)
                    videoTrack.finish(pipeline.videoInput, group)
                    return
                }
                videoTrack.lastWritten = relative
                let seconds = relative.seconds
                if seconds - videoTrack.lastReported >= 0.25 {
                    videoTrack.lastReported = seconds
                    progress(seconds)
                }
            }
        }

        if let audioOutput = pipeline.audioOutput, let audioInput = pipeline.audioInput {
            let audioTrack = AudioPumpState()
            group.enter()
            audioInput.requestMediaDataWhenReady(on: audioQueue) { [self] in
                while audioInput.isReadyForMoreMediaData, !audioTrack.done {
                    if isCancelled || state.hasFailed {
                        audioTrack.finish(audioInput, group)
                        return
                    }
                    guard let sample = audioOutput.copyNextSampleBuffer() else {
                        audioTrack.finish(audioInput, group)
                        return
                    }
                    let adjusted = Self.shifted(sample, by: origin) ?? sample
                    if !audioInput.append(adjusted) {
                        state.fail(ExportWorkerError.cannotWrite)
                        audioTrack.finish(audioInput, group)
                        return
                    }
                }
            }
        }

        group.notify(queue: queue) {
            if let error = state.error {
                pipeline.reader.cancelReading()
                pipeline.writer.cancelWriting()
                completion(.failure(error))
                return
            }
            progress(totalSeconds)
            let written = (try? RationalTime(value: videoTrack.lastWritten.value, timescale: videoTrack.lastWritten.timescale)) ?? .zero
            pipeline.writer.finishWriting {
                if pipeline.writer.status == .completed {
                    completion(.success(written))
                } else {
                    completion(.failure(ExportWorkerError.cannotWrite))
                }
            }
        }
    }

    /// Shifts audio timing by the video origin so both tracks share a zero-based timeline.
    private static func shifted(_ sample: CMSampleBuffer, by origin: CMTime) -> CMSampleBuffer? {
        guard origin != .zero else { return sample }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, origin)
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, origin)
            }
        }
        var result: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: count,
            sampleTimingArray: &timing, sampleBufferOut: &result)
        return result
    }

    /// Per-job render inputs, created once and only read on the video queue.
    private final class RenderInputs: @unchecked Sendable {
        let outputSize: CGSize
        let watermarkFrame: WatermarkLayout.Rect?
        let indicators: [IndicatorRenderer.Overlay]
        init(outputSize: CGSize, watermarkFrame: WatermarkLayout.Rect?, indicators: [IndicatorRenderer.Overlay]) {
            self.outputSize = outputSize
            self.watermarkFrame = watermarkFrame
            self.indicators = indicators
        }
    }

    /// First error wins; read after both tracks finished.
    private final class PumpState: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)
        var error: (any Error)? { lock.withLock { $0 } }
        var hasFailed: Bool { error != nil }
        func fail(_ error: any Error) { lock.withLock { if $0 == nil { $0 = error } } }
    }

    /// Video pump state, touched only on the video queue.
    private final class VideoPumpState: @unchecked Sendable {
        var limiter: CadenceLimiter
        var lastWritten = CMTime.zero
        var lastReported = -1.0
        private(set) var done = false
        init(limiter: CadenceLimiter) { self.limiter = limiter }
        func finish(_ input: AVAssetWriterInput, _ group: DispatchGroup) {
            guard !done else { return }
            done = true
            input.markAsFinished()
            group.leave()
        }
    }

    /// Audio pump state, touched only on the audio queue.
    private final class AudioPumpState: @unchecked Sendable {
        private(set) var done = false
        func finish(_ input: AVAssetWriterInput, _ group: DispatchGroup) {
            guard !done else { return }
            done = true
            input.markAsFinished()
            group.leave()
        }
    }

    private static var rec709: [String: Any] {
        [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
    }
}

/// Verifies a finished file before it can be called a result (05 V09): readable video track
/// with the policy dimensions, duration within one output frame (plus one source frame of
/// encoder alignment), audio present when expected.
enum OutputValidator {
    static func validate(_ url: URL, plan: ExportPlan) async throws -> RationalTime {
        let asset = AVURLAsset(url: url)
        do {
            guard let video = try await asset.loadTracks(withMediaType: .video).first else {
                throw ExportWorkerError.validationFailed("no video track")
            }
            let size = try await video.load(.naturalSize)
            guard Int(size.width.rounded()) == plan.policy.dimensions.width,
                  Int(size.height.rounded()) == plan.policy.dimensions.height
            else { throw ExportWorkerError.validationFailed("dimensions \(size)") }
            let audio = try await asset.loadTracks(withMediaType: .audio)
            guard audio.isEmpty != plan.includesAudio else {
                throw ExportWorkerError.validationFailed("audio presence")
            }
            let duration = try await asset.load(.duration)
            let expected = plan.source.metadata.duration.approximateSeconds
            let tolerance = 1 / plan.policy.frameRate.approximateFPS + 1 / plan.source.metadata.frameRate.approximateFPS + 0.05
            guard abs(duration.seconds - expected) <= tolerance else {
                throw ExportWorkerError.validationFailed("duration \(duration.seconds) vs \(expected)")
            }
            return try RationalTime(value: duration.value, timescale: duration.timescale)
        } catch let error as ExportWorkerError {
            throw error
        } catch {
            throw ExportWorkerError.validationFailed("unreadable")
        }
    }
}
