import AVFoundation
import CoreImage
import Observation
import QuartzCore
import RENNDomain

/// AVPlayer owns the canonical playback/audio clock; `AVPlayerItemVideoOutput` hands frames to
/// the shared RenderEngine (05 V06). Seeking, loop and pause never change the recipe duration.
@MainActor
@Observable
final class PreviewPlayer {
    let player = AVPlayer()
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])

    private(set) var currentSeconds: Double = 0
    private(set) var durationSeconds: Double = 0
    private(set) var isPlaying = false
    private(set) var orientation: CGImagePropertyOrientation = .up
    private(set) var failed = false
    var isLooping = true

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                failed = true
                return
            }
            orientation = RenderEngine.orientation(for: try await track.load(.preferredTransform))
            durationSeconds = try await asset.load(.duration).seconds
        } catch {
            failed = true
            return
        }
        attach(AVPlayerItem(asset: asset))
    }

    /// Dual-Cam: one composition clock; frames arrive packed (rear | front), upright.
    func load(dual: DualPreviewComposition) {
        orientation = .up
        durationSeconds = dual.composition.duration.seconds
        let item = AVPlayerItem(asset: dual.composition)
        item.videoComposition = dual.videoComposition
        attach(item)
    }

    private func attach(_ item: AVPlayerItem) {
        item.add(output)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.currentSeconds = time.seconds }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnd() }
        }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, min(seconds, durationSeconds)), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentSeconds = time.seconds
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    /// Stops playback so no audio keeps playing behind a closed or failed preview (05 V06).
    func tearDown() {
        player.pause()
        isPlaying = false
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    private func handleEnd() {
        if isLooping {
            player.seek(to: .zero)
            player.play()
        } else {
            isPlaying = false
        }
    }
}

extension PreviewPlayer: PreviewFrameSource {
    var frameOrientation: CGImagePropertyOrientation { orientation }

    func nextFrame() -> (image: CIImage, time: RationalTime)? {
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
              itemTime.isNumeric,
              let time = try? RationalTime(value: itemTime.value, timescale: itemTime.timescale)
        else { return nil }
        return (CIImage(cvPixelBuffer: buffer), time)
    }
}
