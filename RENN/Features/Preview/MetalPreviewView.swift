import CoreImage
import MetalKit
import QuartzCore
import SwiftUI
import RENNDomain

/// Supplies frames to the Metal preview: a project's player or the live camera.
@MainActor
protocol PreviewFrameSource: AnyObject {
    /// A new frame if one is available since the last call; nil keeps the previous frame.
    func nextFrame() -> (image: CIImage, time: RationalTime)?
    var frameOrientation: CGImagePropertyOrientation { get }
}

/// A live Dual-Cam source: `nextFrame` delivers the main camera, `insetFrame` the other one.
@MainActor
protocol DualPreviewFrameSource: PreviewFrameSource {
    func insetFrame() -> CIImage?
    var insetCorner: DualCameraLayout.Corner { get }
}

/// Draws the live preview through the same RenderEngine graph as export (05 V04), aspect-fit
/// and letterboxed in the UI only; the output itself never inherits the bars (02 D05).
struct MetalPreviewView: UIViewRepresentable {
    let engine: RenderEngine
    let source: any PreviewFrameSource
    let recipe: Recipe?
    let sourceDimensions: PixelDimensions?
    let showsWatermark: Bool
    let bypassCreative: Bool
    /// Canonical Beat timeline (same as export); nil renders Look-only.
    var beatTimeline: BeatTimeline? = nil
    /// Composition time → Beat timeline time (Dual-Cam audio owner offset).
    var beatTimeOffset: RationalTime = .zero
    /// True while a sheet or flow fully covers this view: it stops pulling frames, so another
    /// preview of the same source (the Indicators panel) gets every frame, and the GPU is free.
    var isPaused = false

    func makeCoordinator() -> PreviewRenderer {
        PreviewRenderer(engine: engine)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: engine.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.backgroundColor = .black
        view.delegate = context.coordinator
        view.isAccessibilityElement = true
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.source = source
        renderer.recipe = recipe
        renderer.sourceDimensions = sourceDimensions
        renderer.showsWatermark = showsWatermark
        renderer.bypassCreative = bypassCreative
        renderer.beatTimeline = beatTimeline
        renderer.beatTimeOffset = beatTimeOffset
        view.isPaused = isPaused
    }

    static func dismantleUIView(_ view: MTKView, coordinator: PreviewRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}

@MainActor
final class PreviewRenderer: NSObject, @preconcurrency MTKViewDelegate {
    let engine: RenderEngine
    private let commandQueue: MTLCommandQueue?
    weak var source: (any PreviewFrameSource)?
    var recipe: Recipe?
    var sourceDimensions: PixelDimensions?
    var showsWatermark = true
    var bypassCreative = false
    var beatTimeline: BeatTimeline?
    var beatTimeOffset: RationalTime = .zero

    private var lastSource: CIImage?
    private var lastTime = RationalTime.zero
    private var watermarkCache: (width: Double, image: CIImage, aspect: Double)?
    private var indicatorCache: (key: String, overlays: [IndicatorRenderer.Overlay])?
    /// Graph building, first-use kernel compilation (e.g. a newly selected Look) and encoding run
    /// here, not on the main thread, so sheets and controls stay smooth; one frame in flight.
    private let renderQueue = DispatchQueue(label: "tzlapp.studio.renn.preview-render", qos: .userInteractive)
    private let gate = RenderGate()

    init(engine: RenderEngine) {
        self.engine = engine
        commandQueue = engine.device?.makeCommandQueue()
    }

    // MTKView calls its delegate on the main thread; @preconcurrency conformance keeps these
    // main-actor isolated with a runtime check.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let source, !gate.isBusy, let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        if let frame = source.nextFrame() {
            lastSource = frame.image
            lastTime = frame.time
        }

        let drawableSize = view.drawableSize
        var job = PreviewRenderJob(
            engine: engine, drawable: drawable, commandBuffer: commandBuffer, drawableSize: drawableSize)
        if let sourceImage = lastSource, let recipe, let dimensions = sourceDimensions {
            let fit = Self.aspectFit(dimensions, in: drawableSize)
            let fitDimensions = try? PixelDimensions(width: Int(fit.width), height: Int(fit.height))
            // Dual-Cam: same inset reservations as export, so overlays never cover the inset.
            let dual = source as? any DualPreviewFrameSource
            let insetLayout = fitDimensions.flatMap { canvas in dual.map { DualInsetLayout(canvas: canvas, corner: $0.insetCorner) } }
            var watermark: CIImage?
            var watermarkFrame: WatermarkLayout.Rect?
            if showsWatermark, let fitDimensions {
                let rendered = watermarkImage(forShortEdge: Double(fitDimensions.shortEdge))
                watermark = rendered?.image
                watermarkFrame = rendered.map {
                    WatermarkLayout(
                        output: fitDimensions, aspectRatio: $0.aspect,
                        reservedBottomRight: insetLayout?.reservedBottomRight(canvas: fitDimensions) ?? 0).frame
                }
            }
            var indicators: [IndicatorRenderer.Overlay] = []
            if let fitDimensions {
                indicators = indicatorOverlays(
                    recipe.indicators, output: fitDimensions,
                    reserved: [watermarkFrame, insetLayout?.frame].compactMap { $0 })
            }
            var request = RenderEngine.FrameRequest(
                source: sourceImage, orientation: source.frameOrientation, recipe: recipe, time: lastTime,
                outputSize: CGSize(width: Int(fit.width), height: Int(fit.height)),
                watermark: watermark, watermarkFrame: watermarkFrame, bypassCreative: bypassCreative,
                beat: BeatModulation.at(
                    lastTime + beatTimeOffset, timeline: beatTimeline, beat: recipe.beat, audioMuted: recipe.audioMuted),
                indicators: indicators)
            if let dual, let insetLayout, let insetImage = dual.insetFrame() {
                request.inset = RenderEngine.Inset(
                    source: insetImage, orientation: dual.frameOrientation, mirrored: false, layout: insetLayout)
            }
            job.request = request
            job.offset = CGAffineTransform(
                translationX: ((drawableSize.width - fit.width) / 2).rounded(),
                y: ((drawableSize.height - fit.height) / 2).rounded())
        }
        let gate = gate
        let frameJob = job
        guard gate.enter() else { return }
        renderQueue.async {
            frameJob.run()
            gate.leave()
        }
    }

    /// Preview shows the same effective indicator placement as export (02 D07).
    private func indicatorOverlays(
        _ settings: IndicatorSettings, output: PixelDimensions, reserved: [WatermarkLayout.Rect]
    ) -> [IndicatorRenderer.Overlay] {
        // Dragged positions change the frames, so they are part of the key (free placement).
        let positions = settings.positions.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.x),\($0.value.y)" }
        let key = "\(output)-\(settings.showsRec)\(settings.showsPlay)\(settings.showsBattery)\(settings.showsDate)-\(settings.stampDate.text)-\(reserved)-\(positions)"
        if let cached = indicatorCache, cached.key == key { return cached.overlays }
        let layout = IndicatorLayout.resolve(output: output, settings: settings, reserved: reserved)
        let overlays = IndicatorRenderer.overlays(for: layout, settings: settings)
        indicatorCache = (key, overlays)
        return overlays
    }

    private func watermarkImage(forShortEdge shortEdge: Double) -> (image: CIImage, aspect: Double)? {
        let width = (shortEdge * WatermarkLayout.maximumWidthFraction).rounded()
        if let cached = watermarkCache, cached.width == width { return (cached.image, cached.aspect) }
        guard let rendered = WatermarkRenderer.render(width: width) else { return nil }
        watermarkCache = (width, rendered.image, rendered.aspectRatio)
        return (rendered.image, rendered.aspectRatio)
    }

    static func aspectFit(_ dimensions: PixelDimensions, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / CGFloat(dimensions.width), size.height / CGFloat(dimensions.height))
        return CGSize(
            width: max(2, (CGFloat(dimensions.width) * scale).rounded(.down)),
            height: max(2, (CGFloat(dimensions.height) * scale).rounded(.down)))
    }
}

/// One preview frame rendered off the main thread: the shared graph (built from a request made on
/// the main thread), letterboxed on black, then encode, present and commit. The engine and its
/// Core Image context are thread-safe; the drawable and command buffer belong to this job only.
private struct PreviewRenderJob: @unchecked Sendable {
    let engine: RenderEngine
    let drawable: CAMetalDrawable
    let commandBuffer: MTLCommandBuffer
    let drawableSize: CGSize
    var request: RenderEngine.FrameRequest?
    var offset = CGAffineTransform.identity

    func run() {
        let bounds = CGRect(origin: .zero, size: drawableSize)
        var frame = CIImage(color: .black).cropped(to: bounds)
        if let request {
            frame = engine.image(for: request).transformed(by: offset).composited(over: frame)
        }
        engine.context.render(
            frame, to: drawable.texture, commandBuffer: commandBuffer, bounds: bounds,
            colorSpace: engine.outputColorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
