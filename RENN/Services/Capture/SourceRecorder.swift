import AVFoundation
import CoreImage
import os
import RENNDomain

/// Latest camera frame for the live preview. Written on the capture queue, read on main.
final class CaptureFrameBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<(CIImage, CMTime)?>(initialState: nil)

    func store(_ image: CIImage, time: CMTime) {
        lock.withLock { $0 = (image, time) }
    }

    func latest() -> (CIImage, CMTime)? {
        lock.withLock { $0 }
    }
}

/// Writes clean capture samples to a file (05 V02). Confined to the capture data queue: all
/// methods except `init` must be called there, which is why it is `@unchecked Sendable`.
///
/// - One accepted origin: the first video sample; earlier audio is dropped, later audio keeps
///   its offset. Video and audio are never zeroed independently.
/// - Free limit: samples at or after origin + limit are refused; `onLimitReached` fires once.
/// - The writer input is real-time; when it is not ready the sample is dropped and counted.
final class SourceRecorder: @unchecked Sendable {
    struct Take {
        let file: URL
        let duration: CMTime
        let width: Int
        let height: Int
        let frameRate: FrameRate
        let hasAudio: Bool
        let droppedFrames: Int
    }

    let file: URL
    let limit: CMTime?
    /// `AVCaptureAudioDataOutput.recommendedAudioSettingsForAssetWriter`; nil records silently.
    let audioSettings: [String: Any]?
    let frameRate: FrameRate
    let onDuration: @Sendable (CMTime) -> Void
    let onLimitReached: @Sendable () -> Void

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var origin: CMTime?
    private var lastVideoTime = CMTime.zero
    private var lastReported = CMTime.zero
    private var width = 0
    private var height = 0
    private var droppedFrames = 0
    private var limitSignalled = false
    private var isFinishing = false
    private var failed = false

    init(
        file: URL, limit: CMTime?, audioSettings: [String: Any]?, frameRate: FrameRate,
        onDuration: @escaping @Sendable (CMTime) -> Void, onLimitReached: @escaping @Sendable () -> Void
    ) {
        self.file = file
        self.limit = limit
        self.audioSettings = audioSettings
        self.frameRate = frameRate
        self.onDuration = onDuration
        self.onLimitReached = onLimitReached
    }

    func appendVideo(_ sample: CMSampleBuffer) {
        guard !isFinishing, !failed, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if writer == nil {
            guard startWriter(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), at: pts)
            else { return }
        }
        guard let origin, let videoInput else { return }
        if let limit, CMTimeCompare(CMTimeSubtract(pts, origin), limit) >= 0 {
            if !limitSignalled {
                limitSignalled = true
                onLimitReached()
            }
            return
        }
        if videoInput.isReadyForMoreMediaData {
            if videoInput.append(sample) {
                lastVideoTime = pts
            } else {
                failed = true
            }
        } else {
            droppedFrames += 1
        }
        let elapsed = CMTimeSubtract(pts, origin)
        if CMTimeSubtract(elapsed, lastReported).seconds >= 0.25 {
            lastReported = elapsed
            onDuration(elapsed)
        }
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        guard !isFinishing, !failed, let origin, let audioInput else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        guard CMTimeCompare(pts, origin) >= 0 else { return }
        if let limit, CMTimeCompare(CMTimeSubtract(pts, origin), limit) >= 0 { return }
        if audioInput.isReadyForMoreMediaData {
            audioInput.append(sample)
        }
    }

    /// Finalizes once; later calls receive the same outcome through their completion.
    func finish(completion: @escaping @Sendable (Result<Take, CaptureFailure>) -> Void) {
        guard !isFinishing else { return }
        isFinishing = true
        guard let writer, let origin, lastVideoTime > origin, writer.status == .writing else {
            self.writer?.cancelWriting()
            completion(.failure(.emptyRecording))
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let duration = CMTimeSubtract(lastVideoTime, origin)
        let result = Take(
            file: file, duration: duration, width: width, height: height,
            frameRate: frameRate, hasAudio: audioInput != nil, droppedFrames: droppedFrames)
        let writerRef = WriterRef(writer)
        writer.finishWriting {
            if writerRef.writer.status == .completed {
                completion(.success(result))
            } else {
                completion(.failure(.recordingFailed))
            }
        }
    }

    private func startWriter(width: Int, height: Int, at pts: CMTime) -> Bool {
        do {
            try? FileManager.default.removeItem(at: file)
            let writer = try AVAssetWriter(outputURL: file, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(6_000_000, width * height * 6),
                    AVVideoExpectedSourceFrameRateKey: Int(frameRate.approximateFPS.rounded()),
                ] as [String: Any],
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { return false }
            writer.add(input)
            // Inputs must exist before writing starts; audio is declared now if recorded.
            if let audioSettings {
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audio.expectsMediaDataInRealTime = true
                if writer.canAdd(audio) {
                    writer.add(audio)
                    audioInput = audio
                }
            }
            guard writer.startWriting() else {
                failed = true
                return false
            }
            writer.startSession(atSourceTime: pts)
            self.writer = writer
            videoInput = input
            origin = pts
            lastVideoTime = pts
            self.width = width
            self.height = height
            return true
        } catch {
            failed = true
            return false
        }
    }
}

/// Carries the writer into the finish callback (the writer is confined to the capture queue).
private final class WriterRef: @unchecked Sendable {
    let writer: AVAssetWriter
    init(_ writer: AVAssetWriter) { self.writer = writer }
}
