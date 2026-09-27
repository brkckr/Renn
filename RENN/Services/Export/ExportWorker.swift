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

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let written = try self.pump(
                        pipeline, origin: origin, orientation: RenderEngine.orientation(for: transform),
                        totalSeconds: duration.seconds, progress: progress)
                    pipeline.writer.finishWriting {
                        if pipeline.writer.status == .completed {
                            continuation.resume(returning: written)
                        } else {
                            continuation.resume(throwing: ExportWorkerError.cannotWrite)
                        }
                    }
                } catch {
                    pipeline.reader.cancelReading()
                    pipeline.writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.job.outputURL)
                    continuation.resume(throwing: error)
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

    /// Runs on `queue`. Interleaves video and audio so neither input starves the writer.
    private func pump(
        _ pipeline: Pipeline, origin: CMTime, orientation: CGImagePropertyOrientation, totalSeconds: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) throws -> RationalTime {
        guard pipeline.reader.startReading(), pipeline.writer.startWriting() else {
            throw ExportWorkerError.cannotRead
        }
        pipeline.writer.startSession(atSourceTime: .zero)

        let outputSize = CGSize(width: job.plan.policy.dimensions.width, height: job.plan.policy.dimensions.height)
        let watermarkFrame = job.watermark.map { _ in
            WatermarkLayout(output: job.plan.policy.dimensions, aspectRatio: job.watermarkAspect).frame
        }
        var limiter = CadenceLimiter(outputRate: job.plan.policy.frameRate)
        var videoDone = false
        var audioDone = pipeline.audioOutput == nil
        var lastWritten = CMTime.zero
        var lastReported = -1.0

        while !videoDone || !audioDone {
            if isCancelled { throw ExportWorkerError.cancelled }
            var progressed = false

            if !videoDone, pipeline.videoInput.isReadyForMoreMediaData {
                progressed = true
                if let sample = pipeline.videoOutput.copyNextSampleBuffer() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    let relative = CMTimeSubtract(pts, origin)
                    guard let buffer = CMSampleBufferGetImageBuffer(sample),
                          let mediaTime = try? RationalTime(value: relative.value, timescale: relative.timescale)
                    else { continue }
                    if limiter.shouldKeep(presentationTime: mediaTime) {
                        try autoreleasepool {
                            guard let pool = pipeline.adaptor.pixelBufferPool else { throw ExportWorkerError.renderFailed }
                            var outputBuffer: CVPixelBuffer?
                            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
                            guard let outputBuffer else { throw ExportWorkerError.renderFailed }
                            let image = job.engine.image(for: RenderEngine.FrameRequest(
                                source: CIImage(cvPixelBuffer: buffer), orientation: orientation,
                                recipe: job.plan.recipe, time: mediaTime, outputSize: outputSize,
                                watermark: job.watermark, watermarkFrame: watermarkFrame))
                            job.engine.render(image, to: outputBuffer)
                            // Source timestamps are kept; only frames above the cadence ceiling are skipped.
                            guard pipeline.adaptor.append(outputBuffer, withPresentationTime: relative) else {
                                throw ExportWorkerError.cannotWrite
                            }
                        }
                        lastWritten = relative
                        let seconds = relative.seconds
                        if seconds - lastReported >= 0.25 {
                            lastReported = seconds
                            progress(seconds)
                        }
                    }
                } else {
                    guard pipeline.reader.status != .failed else { throw ExportWorkerError.cannotRead }
                    pipeline.videoInput.markAsFinished()
                    videoDone = true
                }
            }

            if !audioDone, let audioOutput = pipeline.audioOutput, let audioInput = pipeline.audioInput,
               audioInput.isReadyForMoreMediaData {
                progressed = true
                if let sample = audioOutput.copyNextSampleBuffer() {
                    let adjusted = Self.shifted(sample, by: origin) ?? sample
                    guard audioInput.append(adjusted) else { throw ExportWorkerError.cannotWrite }
                } else {
                    audioInput.markAsFinished()
                    audioDone = true
                }
            }

            if !progressed {
                // Inputs are busy encoding; yield briefly (bounded, no unbounded queue growth).
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        progress(totalSeconds)
        return (try? RationalTime(value: lastWritten.value, timescale: lastWritten.timescale)) ?? .zero
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
