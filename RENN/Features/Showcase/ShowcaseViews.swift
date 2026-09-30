import CoreImage
import CoreImage.CIFilterBuiltins
import MetalKit
import QuartzCore
import SwiftUI
import RENNDomain

extension EnvironmentValues {
    /// App-lifetime showcase media (Look posters, demo clips); nil in isolated previews.
    var showcase: ShowcaseMedia? {
        get { self[ShowcaseKey.self] }
        set { self[ShowcaseKey.self] = newValue }
    }

    /// False while the hosting tab is hidden or a full-screen flow covers it, so decorative
    /// playback stops (03 shared rules).
    var showcaseIsActive: Bool {
        get { self[ShowcaseActiveKey.self] }
        set { self[ShowcaseActiveKey.self] = newValue }
    }
}

private struct ShowcaseKey: EnvironmentKey {
    static var defaultValue: ShowcaseMedia? { nil }
}

private struct ShowcaseActiveKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

/// A catalog Look's poster: the Look's own render of the street demo frame (owner-approved),
/// the plain placeholder while it renders or if it cannot. Fills the frame its caller gives it.
struct LookPoster: View {
    let look: LookDefinition

    @Environment(\.showcase) private var showcase

    var body: some View {
        Color.clear
            .overlay {
                if let image = showcase?.poster(for: look) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    LookPosterPlaceholder(look: look)
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.2), value: showcase?.poster(for: look) != nil)
            .task(id: look.id) { await showcase?.loadPoster(for: look) }
            .accessibilityHidden(true)
    }
}

/// One-shot clean-to-Look sweep (03 M02 page 1): clean for `delay`, then a vertical edge moves
/// left to right over `duration` and the treated frame rests.
struct DemoReveal: Equatable {
    var delay: Double
    var duration: Double

    func progress(elapsed: Double) -> Double {
        guard duration > 0 else { return elapsed >= delay ? 1 : 0 }
        let x = min(1, max(0, (elapsed - delay) / duration))
        return Easing.cubicBezier(x, 0.45, 0, 0.2, 1)
    }
}

/// Plays a bundled demo clip through the shared RenderEngine (the same graph as preview and
/// export), aspect-filled into its frame. Decorative: hidden from accessibility, paused while
/// inactive.
struct DemoVideoView: UIViewRepresentable {
    let engine: RenderEngine
    let player: PreviewPlayer
    /// Nil renders the clip clean.
    let recipe: Recipe?
    var beatTimeline: BeatTimeline? = nil
    var reveal: DemoReveal? = nil
    var isActive = true

    func makeCoordinator() -> DemoVideoRenderer {
        DemoVideoRenderer(engine: engine)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: engine.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = false
        // Decorative scene: a 2x drawable is plenty and keeps the GPU cost low.
        view.contentScaleFactor = 2
        view.backgroundColor = .black
        view.isAccessibilityElement = false
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.source = player
        renderer.recipe = recipe
        renderer.beatTimeline = beatTimeline
        if renderer.reveal != reveal {
            renderer.reveal = reveal
            renderer.revealStart = nil
        }
        view.isPaused = !isActive
    }

    static func dismantleUIView(_ view: MTKView, coordinator: DemoVideoRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}

@MainActor
final class DemoVideoRenderer: NSObject, @preconcurrency MTKViewDelegate {
    let engine: RenderEngine
    private let commandQueue: MTLCommandQueue?
    weak var source: PreviewPlayer?
    var recipe: Recipe?
    var beatTimeline: BeatTimeline?
    var reveal: DemoReveal?
    /// Host time of the first drawn frame of the current reveal.
    var revealStart: CFTimeInterval?

    private var lastSource: CIImage?
    private var lastTime = RationalTime.zero
    /// A frame whose graph has not been drawn yet.
    private var hasNewFrame = false
    /// One frame in flight at a time; later ticks are dropped rather than queued.
    private let gate = RenderGate()
    /// Graph building, first-use kernel compilation and GPU encoding run here, never on the main
    /// thread, so taps and page transitions stay responsive (a new Look's first frame can take long).
    private let renderQueue = DispatchQueue(label: "tzlapp.studio.renn.demo-render", qos: .userInitiated)

    init(engine: RenderEngine) {
        self.engine = engine
        commandQueue = engine.device?.makeCommandQueue()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        hasNewFrame = true
    }

    func draw(in view: MTKView) {
        guard let source else { return }
        if let frame = source.nextFrame() {
            lastSource = frame.image
            lastTime = frame.time
            hasNewFrame = true
        }
        let size = CGSize(width: view.drawableSize.width.rounded(), height: view.drawableSize.height.rounded())
        guard !gate.isBusy, let image = lastSource, size.width >= 2, size.height >= 2 else { return }
        if reveal != nil, revealStart == nil { revealStart = CACurrentMediaTime() }
        let progress = reveal.flatMap { reveal in revealStart.map { reveal.progress(elapsed: CACurrentMediaTime() - $0) } }
        let isRevealing = progress.map { $0 < 1 } ?? false
        // Nothing changed since the last drawn frame: keep it on screen.
        guard hasNewFrame || isRevealing else { return }
        guard let drawable = view.currentDrawable, let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        hasNewFrame = false
        let recipe = recipe ?? ShowcaseMedia.recipe(for: nil)
        let job = DemoRenderJob(
            engine: engine, drawable: drawable, commandBuffer: commandBuffer, size: size,
            request: RenderEngine.FrameRequest(
                source: Self.fillCrop(image, orientation: source.frameOrientation, aspect: size.width / size.height),
                orientation: source.frameOrientation, recipe: recipe, time: lastTime, outputSize: size,
                watermark: nil, watermarkFrame: nil,
                beat: BeatModulation.at(lastTime, timeline: beatTimeline, beat: recipe.beat, audioMuted: recipe.audioMuted)),
            revealProgress: isRevealing ? progress : nil)
        let gate = gate
        guard gate.enter() else { return }
        renderQueue.async {
            job.run()
            gate.leave()
        }
    }

    /// Centre crop of the stored frame to the target (upright) aspect, so the graph renders only
    /// visible pixels and its exact scale never distorts.
    nonisolated static func fillCrop(_ image: CIImage, orientation: CGImagePropertyOrientation, aspect: CGFloat) -> CIImage {
        let rotated: Set<CGImagePropertyOrientation> = [.left, .right, .leftMirrored, .rightMirrored]
        let target = rotated.contains(orientation) ? 1 / aspect : aspect
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, target > 0 else { return image }
        var rect = extent
        if extent.width / extent.height > target {
            rect.size.width = (extent.height * target).rounded()
            rect.origin.x = (extent.midX - rect.width / 2).rounded()
        } else {
            rect.size.height = (extent.width / target).rounded()
            rect.origin.y = (extent.midY - rect.height / 2).rounded()
        }
        return image.cropped(to: rect)
    }
}

/// Lock-protected in-flight flag shared by the main thread and the render queue.
private final class RenderGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    var isBusy: Bool { lock.withLock { busy } }

    func enter() -> Bool {
        lock.withLock {
            guard !busy else { return false }
            busy = true
            return true
        }
    }

    func leave() {
        lock.withLock { busy = false }
    }
}

/// One demo frame rendered off the main thread: the shared graph, the optional clean-to-Look
/// sweep, then encode, present and commit. Core Image contexts and the engine are thread-safe;
/// the drawable and command buffer are used only by this job.
private struct DemoRenderJob: @unchecked Sendable {
    let engine: RenderEngine
    let drawable: CAMetalDrawable
    let commandBuffer: MTLCommandBuffer
    let size: CGSize
    let request: RenderEngine.FrameRequest
    /// Sweep progress while the reveal runs; nil renders the treated frame only.
    let revealProgress: Double?

    func run() {
        let bounds = CGRect(origin: .zero, size: size)
        var frame = engine.image(for: request)
        if let progress = revealProgress {
            var cleanRequest = request
            cleanRequest.bypassCreative = true
            let edge = (size.width * progress).rounded()
            let blend = CIFilter.blendWithMask()
            blend.inputImage = frame
            blend.backgroundImage = engine.image(for: cleanRequest)
            blend.maskImage = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: edge, height: size.height))
            frame = blend.outputImage ?? frame
            if progress > 0 {
                let line = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.85))
                    .cropped(to: CGRect(x: edge - 2, y: 0, width: 4, height: size.height))
                frame = line.composited(over: frame)
            }
        }
        engine.context.render(
            frame.cropped(to: bounds), to: drawable.texture, commandBuffer: commandBuffer, bounds: bounds,
            colorSpace: engine.outputColorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// Owns one looping, muted demo player for a scene: loads the bundled clip, plays while active,
/// and tears down when the scene goes away so no audio or decoding keeps running (03 shared rules).
@MainActor
@Observable
final class DemoPlayback {
    let player = PreviewPlayer()
    private(set) var isReady = false
    private(set) var isMuted = true
    @ObservationIgnored private var loadedClip: DemoClip?

    func start(_ clip: DemoClip) async {
        if loadedClip != clip {
            guard let url = clip.url else { return }
            loadedClip = clip
            await player.load(url: url)
            player.isLooping = true
            player.setMuted(isMuted)
            isReady = !player.failed
        }
        if isReady { player.play() }
    }

    func setActive(_ active: Bool) {
        guard isReady else { return }
        active ? player.play() : player.pause()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player.setMuted(muted)
    }

    func stop() {
        player.tearDown()
        isReady = false
        loadedClip = nil
    }
}
