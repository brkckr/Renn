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
        var sources: ExportSourceFiles
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
        let plan = job.plan
        // Video is driven by the single source, or by the rear camera in Dual-Cam.
        let driver = plan.dual?.rear ?? plan.source
        guard let driverURL = job.sources.url(for: driver) else { throw ExportWorkerError.cannotRead }
        let driverAsset = AVURLAsset(url: driverURL)
        var companion: Companion?
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let audioAsset: AVAsset
        let transform: CGAffineTransform
        let duration: CMTime
        let origin: CMTime
        let audioOrigin: CMTime
        let audioFormat: CMFormatDescription?
        do {
            guard let video = try await driverAsset.loadTracks(withMediaType: .video).first else { throw ExportWorkerError.cannotRead }
            videoTrack = video
            transform = try await video.load(.preferredTransform)
            // One shared origin per file keeps its A/V offset (05 V02); Dual-Cam adds the
            // source's offset to the common interval (05 V03).
            origin = CMTimeAdd(try await video.load(.timeRange).start, Self.cmTime(plan.dual?.timing.rearOffset ?? .zero))
            duration = plan.dual == nil ? try await driverAsset.load(.duration) : Self.cmTime(plan.duration)

            if let dual = plan.dual {
                guard let frontURL = job.sources.url(for: dual.front) else { throw ExportWorkerError.cannotRead }
                let frontAsset = AVURLAsset(url: frontURL)
                guard let frontVideo = try await frontAsset.loadTracks(withMediaType: .video).first else { throw ExportWorkerError.cannotRead }
                companion = Companion(
                    asset: frontAsset, track: frontVideo, source: dual.front,
                    origin: CMTimeAdd(try await frontVideo.load(.timeRange).start, Self.cmTime(dual.timing.frontOffset)),
                    orientation: RenderEngine.orientation(for: try await frontVideo.load(.preferredTransform)))
            }
            // Audio comes from `plan.source`: the only source, or the declared Dual-Cam owner.
            if plan.source.role == driver.role {
                audioAsset = driverAsset
                audioOrigin = origin
            } else if let companion {
                audioAsset = companion.asset
                audioOrigin = companion.origin
            } else {
                throw ExportWorkerError.cannotRead
            }
            audioTrack = plan.includesAudio ? try await audioAsset.loadTracks(withMediaType: .audio).first : nil
            audioFormat = try await audioTrack?.load(.formatDescriptions).first
        } catch {
            throw ExportWorkerError.cannotRead
        }
        let pipeline = try makePipeline(
            asset: driverAsset, videoTrack: videoTrack, audioAsset: audioAsset, audioTrack: audioTrack,
            audioFormat: audioFormat, companion: companion,
            commonRange: plan.dual == nil ? nil : (origin, duration))

        let totalSeconds = duration.seconds
        let orientation = RenderEngine.orientation(for: transform)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.start(
                    pipeline, origin: origin, audioOrigin: audioOrigin, orientation: orientation,
                    companion: companion, totalSeconds: totalSeconds, progress: progress
                ) { result in
                    if case .failure = result {
                        try? FileManager.default.removeItem(at: self.job.outputURL)
                    }
                    continuation.resume(with: result)
                }
            }
        }
    }

    static func cmTime(_ time: RationalTime) -> CMTime {
        CMTime(value: time.value, timescale: time.timescale)
    }

    /// The Dual-Cam front source, read as a frame cursor alongside the rear driver.
    struct Companion: @unchecked Sendable {
        let asset: AVAsset
        let track: AVAssetTrack
        let source: SourceReference
        /// File time of composition time 0.
        let origin: CMTime
        let orientation: CGImagePropertyOrientation
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
        /// Dual-Cam: the front source's reader and video output (may also carry the audio output).
        let companionReader: AVAssetReader?
        let companionOutput: AVAssetReaderTrackOutput?

        init(
            reader: AVAssetReader, writer: AVAssetWriter, videoOutput: AVAssetReaderTrackOutput,
            audioOutput: AVAssetReaderTrackOutput?, videoInput: AVAssetWriterInput,
            audioInput: AVAssetWriterInput?, adaptor: AVAssetWriterInputPixelBufferAdaptor,
            companionReader: AVAssetReader? = nil, companionOutput: AVAssetReaderTrackOutput? = nil
        ) {
            self.companionReader = companionReader
            self.companionOutput = companionOutput
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
        asset: AVAsset, videoTrack: AVAssetTrack, audioAsset: AVAsset, audioTrack: AVAssetTrack?,
        audioFormat: CMFormatDescription?, companion: Companion?, commonRange: (start: CMTime, duration: CMTime)?
    ) throws -> Pipeline {
        let policy = job.plan.policy
        let width = policy.dimensions.width
        let height = policy.dimensions.height

        let reader: AVAssetReader
        let writer: AVAssetWriter
        var companionReader: AVAssetReader?
        do {
            reader = try AVAssetReader(asset: asset)
            if let companion {
                companionReader = try AVAssetReader(asset: companion.asset)
            }
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

        var companionOutput: AVAssetReaderTrackOutput?
        if let companion, let companionReader, let commonRange {
            let output = AVAssetReaderTrackOutput(track: companion.track, outputSettings: videoSettings)
            output.alwaysCopiesSampleData = false
            guard companionReader.canAdd(output) else { throw ExportWorkerError.cannotRead }
            companionReader.add(output)
            companionOutput = output
            // Both readers cover only the common interval, each on its own file clock.
            reader.timeRange = CMTimeRange(start: commonRange.start, duration: commonRange.duration)
            companionReader.timeRange = CMTimeRange(start: companion.origin, duration: commonRange.duration)
        }
        // The audio output lives on the reader of the file that owns the audio.
        let audioReader = (companion != nil && audioAsset === companion?.asset) ? companionReader ?? reader : reader

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
            if audioReader.canAdd(output), writer.canAdd(input) {
                audioReader.add(output)
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
            videoInput: videoInput, audioInput: audioInput, adaptor: adaptor,
            companionReader: companionReader, companionOutput: companionOutput)
    }

    /// Starts reading/writing. Video and audio drain on their own queues through
    /// `requestMediaDataWhenReady`, so a full audio buffer can never block video decoding (and
    /// vice versa) while the writer waits to interleave. Completion is called exactly once.
    private func start(
        _ pipeline: Pipeline, origin: CMTime, audioOrigin: CMTime, orientation: CGImagePropertyOrientation,
        companion: Companion?, totalSeconds: Double,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<RationalTime, any Error>) -> Void
    ) {
        guard pipeline.reader.startReading(), pipeline.companionReader?.startReading() ?? true,
              pipeline.writer.startWriting()
        else {
            pipeline.reader.cancelReading()
            pipeline.companionReader?.cancelReading()
            completion(.failure(ExportWorkerError.cannotRead))
            return
        }
        pipeline.writer.startSession(atSourceTime: .zero)

        let state = PumpState()
        let group = DispatchGroup()
        let outputSize = CGSize(width: job.plan.policy.dimensions.width, height: job.plan.policy.dimensions.height)
        let canvas = job.plan.policy.dimensions
        let insetLayout = job.plan.dual.map { DualInsetLayout(canvas: canvas, corner: $0.layout.insetCorner) }
        let watermarkFrame = job.watermark.map { _ in
            WatermarkLayout(
                output: canvas, aspectRatio: job.watermarkAspect,
                reservedBottomRight: insetLayout?.reservedBottomRight(canvas: canvas) ?? 0).frame
        }
        // Indicators avoid the watermark and inset reservations; laid out and drawn once per job.
        let indicatorLayout = IndicatorLayout.resolve(
            output: canvas, settings: job.plan.recipe.indicators,
            reserved: [watermarkFrame, insetLayout?.frame].compactMap { $0 })
        let inputs = RenderInputs(
            outputSize: outputSize, watermarkFrame: watermarkFrame,
            indicators: IndicatorRenderer.overlays(for: indicatorLayout, settings: job.plan.recipe.indicators))
        let cursor = pipeline.companionOutput.map { FrameCursor(output: $0, origin: companion?.origin ?? .zero) }
        // Beat timeline times are file times of the audio owner.
        let beatOffset = job.plan.dual.map { job.plan.source.role == .rearCamera ? $0.timing.rearOffset : $0.timing.frontOffset } ?? .zero

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
                guard relative >= .zero,
                      let buffer = CMSampleBufferGetImageBuffer(sample),
                      let mediaTime = try? RationalTime(value: relative.value, timescale: relative.timescale),
                      videoTrack.limiter.shouldKeep(presentationTime: mediaTime)
                else { continue }
                // Dual-Cam: the front frame shown at this composition time (latest at or before it).
                var frontBuffer: CVPixelBuffer?
                if let cursor {
                    frontBuffer = cursor.frame(at: relative)
                    if frontBuffer == nil {
                        state.fail(ExportWorkerError.cannotRead)
                        videoTrack.finish(pipeline.videoInput, group)
                        return
                    }
                }
                let appended: Bool = autoreleasepool {
                    guard let pool = pipeline.adaptor.pixelBufferPool else { return false }
                    var outputBuffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
                    guard let outputBuffer else { return false }
                    var request = RenderEngine.FrameRequest(
                        source: CIImage(cvPixelBuffer: buffer), orientation: orientation,
                        recipe: job.plan.recipe, time: mediaTime, outputSize: inputs.outputSize,
                        watermark: job.watermark, watermarkFrame: inputs.watermarkFrame,
                        beat: BeatModulation.at(
                            mediaTime + beatOffset, timeline: job.beatTimeline, beat: job.plan.recipe.beat,
                            audioMuted: job.plan.recipe.audioMuted),
                        indicators: inputs.indicators)
                    if let dual = job.plan.dual, let frontBuffer, let insetLayout, let companion {
                        // The persisted mirror choice is baked into the recorded pixels at capture
                        // (`SourceMetadata.isMirrored` is informational), so nothing is mirrored twice.
                        let rear = (image: request.source, orientation: orientation, mirrored: false)
                        let front = (image: CIImage(cvPixelBuffer: frontBuffer), orientation: companion.orientation,
                                     mirrored: false)
                        // Swap events are on the composition timeline (05 V03).
                        let (main, inset) = dual.layout.mainCamera(at: mediaTime) == .rear ? (rear, front) : (front, rear)
                        request.source = main.image
                        request.orientation = main.orientation
                        request.mirrored = main.mirrored
                        request.inset = RenderEngine.Inset(
                            source: inset.image, orientation: inset.orientation, mirrored: inset.mirrored, layout: insetLayout)
                    }
                    let image = job.engine.image(for: request)
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
                    let adjusted = Self.shifted(sample, by: audioOrigin) ?? sample
                    if !audioInput.append(adjusted) {
                        state.fail(ExportWorkerError.cannotWrite)
                        audioTrack.finish(audioInput, group)
                        return
                    }
                }
            }
        }

        group.notify(queue: queue) {
            pipeline.companionReader?.cancelReading()
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

    /// Dual-Cam front frames, pulled on the video queue: holds the latest frame at or before the
    /// requested composition time, plus one look-ahead sample. Bounded to two buffers.
    private final class FrameCursor: @unchecked Sendable {
        private let output: AVAssetReaderTrackOutput
        private let origin: CMTime
        private var current: CMSampleBuffer?
        private var next: CMSampleBuffer?
        private var exhausted = false

        init(output: AVAssetReaderTrackOutput, origin: CMTime) {
            self.output = output
            self.origin = origin
        }

        func frame(at time: CMTime) -> CVPixelBuffer? {
            while true {
                if next == nil, !exhausted {
                    next = output.copyNextSampleBuffer()
                    if next == nil { exhausted = true }
                }
                guard let candidate = next,
                      CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(candidate), origin) <= time
                else { break }
                current = candidate
                next = nil
            }
            // Before the first front frame (sub-frame start skew), show the first one.
            return (current ?? next).flatMap(CMSampleBufferGetImageBuffer)
        }
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
            let expected = plan.duration.approximateSeconds
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
