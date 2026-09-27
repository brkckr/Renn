import CoreImage
import MetalKit
import QuartzCore
import SwiftUI
import RENNDomain

/// Draws the live preview through the same RenderEngine graph as export (05 V04), aspect-fit
/// and letterboxed in the UI only; the output itself never inherits the bars (02 D05).
struct MetalPreviewView: UIViewRepresentable {
    let engine: RenderEngine
    let player: PreviewPlayer
    let recipe: Recipe?
    let sourceDimensions: PixelDimensions?
    let showsWatermark: Bool
    let bypassCreative: Bool

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
        renderer.player = player
        renderer.recipe = recipe
        renderer.sourceDimensions = sourceDimensions
        renderer.showsWatermark = showsWatermark
        renderer.bypassCreative = bypassCreative
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
    weak var player: PreviewPlayer?
    var recipe: Recipe?
    var sourceDimensions: PixelDimensions?
    var showsWatermark = true
    var bypassCreative = false

    private var lastSource: CIImage?
    private var lastTime = RationalTime.zero
    private var watermarkCache: (width: Double, image: CIImage, aspect: Double)?

    init(engine: RenderEngine) {
        self.engine = engine
        commandQueue = engine.device?.makeCommandQueue()
    }

    // MTKView calls its delegate on the main thread; @preconcurrency conformance keeps these
    // main-actor isolated with a runtime check.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let player, let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        let itemTime = player.output.itemTime(forHostTime: CACurrentMediaTime())
        if player.output.hasNewPixelBuffer(forItemTime: itemTime),
           let buffer = player.output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            lastSource = CIImage(cvPixelBuffer: buffer)
            if itemTime.isNumeric, let time = try? RationalTime(value: itemTime.value, timescale: itemTime.timescale) {
                lastTime = time
            }
        }

        let drawableSize = view.drawableSize
        let bounds = CGRect(origin: .zero, size: drawableSize)
        var frame = CIImage(color: .black).cropped(to: bounds)
        if let source = lastSource, let recipe, let dimensions = sourceDimensions {
            let fit = Self.aspectFit(dimensions, in: drawableSize)
            var watermark: CIImage?
            var watermarkFrame: WatermarkLayout.Rect?
            if showsWatermark, let fitDimensions = try? PixelDimensions(width: Int(fit.width), height: Int(fit.height)) {
                let rendered = watermarkImage(forShortEdge: Double(fitDimensions.shortEdge))
                watermark = rendered?.image
                watermarkFrame = rendered.map { WatermarkLayout(output: fitDimensions, aspectRatio: $0.aspect).frame }
            }
            let image = engine.image(for: RenderEngine.FrameRequest(
                source: source, orientation: player.orientation, recipe: recipe, time: lastTime,
                outputSize: CGSize(width: Int(fit.width), height: Int(fit.height)),
                watermark: watermark, watermarkFrame: watermarkFrame, bypassCreative: bypassCreative))
            let offset = CGAffineTransform(
                translationX: ((drawableSize.width - fit.width) / 2).rounded(),
                y: ((drawableSize.height - fit.height) / 2).rounded())
            frame = image.transformed(by: offset).composited(over: frame)
        }
        engine.context.render(
            frame, to: drawable.texture, commandBuffer: commandBuffer, bounds: bounds,
            colorSpace: engine.outputColorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
