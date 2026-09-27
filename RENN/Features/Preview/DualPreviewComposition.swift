import AVFoundation
import CoreImage
import RENNDomain

/// Dual-Cam playback on one clock (05 V03/V06): both clean sources trimmed to their common
/// interval in one `AVComposition`, with the audio owner's track only. A custom compositor packs
/// the two upright frames side by side (rear left, front right); the preview splits them again
/// and renders main + inset through the shared RenderEngine, so the Look still applies per source.
struct DualPreviewComposition {
    let composition: AVComposition
    let videoComposition: AVVideoComposition
    /// Width of the upright rear frame inside the packed frame.
    let rearWidth: Double
    let packedSize: CGSize

    enum BuildError: Error {
        case missingTrack
    }

    @MainActor
    static func make(rearURL: URL, frontURL: URL, timing: DualSourceTiming, audioFromRear: Bool) async throws -> DualPreviewComposition {
        let rearAsset = AVURLAsset(url: rearURL)
        let frontAsset = AVURLAsset(url: frontURL)
        guard let rearVideo = try await rearAsset.loadTracks(withMediaType: .video).first,
              let frontVideo = try await frontAsset.loadTracks(withMediaType: .video).first
        else { throw BuildError.missingTrack }
        let duration = CMTime(value: timing.duration.value, timescale: timing.duration.timescale)
        let composition = AVMutableComposition()

        func insert(_ track: AVAssetTrack, offset: RationalTime) async throws -> (id: CMPersistentTrackID, upright: CGSize, orientation: CGImagePropertyOrientation) {
            guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw BuildError.missingTrack }
            let start = CMTimeAdd(try await track.load(.timeRange).start, CMTime(value: offset.value, timescale: offset.timescale))
            try target.insertTimeRange(CMTimeRange(start: start, duration: duration), of: track, at: .zero)
            let transform = try await track.load(.preferredTransform)
            let natural = try await track.load(.naturalSize)
            let upright = natural.applying(transform)
            return (target.trackID, CGSize(width: abs(upright.width), height: abs(upright.height)), RenderEngine.orientation(for: transform))
        }
        let rear = try await insert(rearVideo, offset: timing.rearOffset)
        let front = try await insert(frontVideo, offset: timing.frontOffset)

        let audioAsset = audioFromRear ? rearAsset : frontAsset
        let audioOffset = audioFromRear ? timing.rearOffset : timing.frontOffset
        if let audio = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            // Audio keeps its file's offset to that file's video (one origin per file, 05 V02).
            let videoStart = try await (audioFromRear ? rearVideo : frontVideo).load(.timeRange).start
            let start = CMTimeAdd(videoStart, CMTime(value: audioOffset.value, timescale: audioOffset.timescale))
            try? target.insertTimeRange(CMTimeRange(start: start, duration: duration), of: audio, at: .zero)
        }

        let packed = CGSize(width: rear.upright.width + front.upright.width, height: max(rear.upright.height, front.upright.height))
        let instruction = DualPackInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            rear: rear.id, front: front.id, rearOrientation: rear.orientation, frontOrientation: front.orientation,
            rearWidth: rear.upright.width)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = DualPackCompositor.self
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = packed
        videoComposition.instructions = [instruction]
        return DualPreviewComposition(
            composition: composition, videoComposition: videoComposition, rearWidth: rear.upright.width, packedSize: packed)
    }

    /// Splits a packed frame into upright rear and front images, both with origin at zero.
    static func split(_ packed: CIImage, rearWidth: Double) -> (rear: CIImage, front: CIImage) {
        let extent = packed.extent
        let rear = packed.cropped(to: CGRect(x: extent.minX, y: extent.minY, width: rearWidth, height: extent.height))
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let front = packed
            .cropped(to: CGRect(x: extent.minX + rearWidth, y: extent.minY, width: extent.width - rearWidth, height: extent.height))
            .transformed(by: CGAffineTransform(translationX: -(extent.minX + rearWidth), y: -extent.minY))
        return (rear, front)
    }
}

/// Instruction for `DualPackCompositor`: which tracks to pack and how to upright them.
final class DualPackInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let rear: CMPersistentTrackID
    let front: CMPersistentTrackID
    let rearOrientation: CGImagePropertyOrientation
    let frontOrientation: CGImagePropertyOrientation
    let rearWidth: Double

    init(
        timeRange: CMTimeRange, rear: CMPersistentTrackID, front: CMPersistentTrackID,
        rearOrientation: CGImagePropertyOrientation, frontOrientation: CGImagePropertyOrientation, rearWidth: Double
    ) {
        self.timeRange = timeRange
        self.rear = rear
        self.front = front
        self.rearOrientation = rearOrientation
        self.frontOrientation = frontOrientation
        self.rearWidth = rearWidth
        requiredSourceTrackIDs = [NSNumber(value: rear), NSNumber(value: front)]
    }
}

/// Packs the two source frames side by side. Stateless apart from its Core Image context, which
/// is thread-safe; AVFoundation calls `startRequest` on its own queue.
final class DualPackCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? DualPackInstruction,
              let rearBuffer = request.sourceFrame(byTrackID: instruction.rear),
              let frontBuffer = request.sourceFrame(byTrackID: instruction.front),
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: "RENN.DualPack", code: 1))
            return
        }
        func upright(_ buffer: CVPixelBuffer, _ orientation: CGImagePropertyOrientation) -> CIImage {
            let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
            return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        }
        let rear = upright(rearBuffer, instruction.rearOrientation)
        let front = upright(frontBuffer, instruction.frontOrientation)
            .transformed(by: CGAffineTransform(translationX: instruction.rearWidth, y: 0))
        let size = request.renderContext.size
        let packed = front.composited(over: rear)
            .composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size)))
        context.render(packed, to: output)
        request.finish(withComposedVideoFrame: output)
    }
}

/// Playback frames of a Dual-Cam project: splits the packed frame and hands the camera that is
/// main at that composition time to the renderer, the other as the inset (swap timeline replay).
@MainActor
final class DualPlaybackFrameSource: DualPreviewFrameSource {
    private let player: PreviewPlayer
    private let rearWidth: Double
    private let layout: DualCameraLayout
    private var inset: CIImage?

    init(player: PreviewPlayer, rearWidth: Double, layout: DualCameraLayout) {
        self.player = player
        self.rearWidth = rearWidth
        self.layout = layout
    }

    var frameOrientation: CGImagePropertyOrientation { .up }
    var insetCorner: DualCameraLayout.Corner { layout.insetCorner }

    func nextFrame() -> (image: CIImage, time: RationalTime)? {
        guard let frame = player.nextFrame() else { return nil }
        let parts = DualPreviewComposition.split(frame.image, rearWidth: rearWidth)
        let rearIsMain = layout.mainCamera(at: frame.time) == .rear
        inset = rearIsMain ? parts.front : parts.rear
        return (rearIsMain ? parts.rear : parts.front, frame.time)
    }

    func insetFrame() -> CIImage? {
        inset
    }
}
