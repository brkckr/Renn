import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import ImageIO
import Metal
import RENNDomain

/// Shared recipe-driven renderer for preview and export (05 V04): frame + recipe + media time
/// → pixels. The same graph is built for both, so preview and export differ only in output
/// size. No wall-clock randomness: procedural effects derive from the project seed and a fixed
/// 60-ticks-per-second media clock.
///
/// Render version 1 Look graph: LUT (blended by `lutMix`) → saturation/contrast → warmth →
/// vignette → deterministic grain. Every strength comes from the recipe's snapshotted Look
/// parameters scaled by intensity, so intensity 0 is an exact passthrough and later catalog
/// edits never change an existing project. The only bundled Look is a DEV fixture (08 I01).
///
/// Thread safety: `CIContext` is documented as thread-safe and the engine holds no mutable
/// state, so one instance is shared across preview and export queues.
final class RenderEngine: @unchecked Sendable {
    static let noiseTicksPerSecond: Int64 = 60

    let context: CIContext
    let outputColorSpace: CGColorSpace
    /// Shared GPU device for preview drawables (04 A03 app-lifetime GPU context).
    let device: MTLDevice?
    let luts: LookLUTStore
    /// Creative LUTs are authored for gamma-encoded sRGB, not the linear working space.
    private let lutColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(luts: LookLUTStore = LookLUTStore()) {
        self.luts = luts
        let rec709 = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
        outputColorSpace = rec709
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) as Any,
            .outputColorSpace: rec709,
            .cacheIntermediates: false,
        ]
        device = MTLCreateSystemDefaultDevice()
        if let device {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    struct FrameRequest {
        /// Decoded frame in storage orientation.
        var source: CIImage
        var orientation: CGImagePropertyOrientation
        var recipe: Recipe
        /// Media time relative to the source start.
        var time: RationalTime
        var outputSize: CGSize
        /// Free watermark, already rendered at output scale; nil for Pro.
        var watermark: CIImage?
        var watermarkFrame: WatermarkLayout.Rect?
        /// Before/after bypass: disables creative Look and Beat, never the policy watermark (02 D05).
        var bypassCreative = false
        /// Bounded Beat modulation for this media time; `.none` when Beat is not effective.
        var beat: BeatModulation = .none
        /// Decorative indicators, already placed by `IndicatorLayout` (drawn once per size).
        var indicators: [IndicatorRenderer.Overlay] = []
        /// Persisted mirror choice for the main source (front camera in Dual-Cam).
        var mirrored = false
        /// Dual-Cam inset source; the main source fills the canvas (05 V03).
        var inset: Inset?
    }

    struct Inset {
        var source: CIImage
        var orientation: CGImagePropertyOrientation
        var mirrored: Bool
        var layout: DualInsetLayout
    }

    /// Builds the frame graph. Lazy: no GPU work happens until `render`.
    func image(for request: FrameRequest) -> CIImage {
        let bounds = CGRect(origin: .zero, size: request.outputSize)
        // Dual-Cam order: normalize each source → same Look/Beat on each → compose (05 V03).
        var image = creative(
            normalized(request.source, request.orientation, mirrored: request.mirrored, fill: request.outputSize,
                       exact: request.inset == nil),
            request)
        if let inset = request.inset {
            let frame = inset.layout.frame
            let size = CGSize(width: frame.width, height: frame.height)
            let insetImage = creative(normalized(inset.source, inset.orientation, mirrored: inset.mirrored, fill: size, exact: false), request)
            let ciY = Double(request.outputSize.height) - frame.y - frame.height
            let mask = roundedMask(size: size, radius: inset.layout.cornerRadius)
                .transformed(by: CGAffineTransform(translationX: frame.x, y: ciY))
            let placed = insetImage.transformed(by: CGAffineTransform(translationX: frame.x, y: ciY))
            let blend = CIFilter.blendWithAlphaMask()
            blend.inputImage = placed
            blend.backgroundImage = image
            blend.maskImage = mask
            image = blend.outputImage?.cropped(to: bounds) ?? image
        }
        // Order: effects → OSD → policy watermark (05 V03/V04). Neither is attenuated by intensity.
        for overlay in request.indicators {
            image = place(overlay.image, in: overlay.frame, outputHeight: request.outputSize.height).composited(over: image)
        }
        if let watermark = request.watermark, let frame = request.watermarkFrame {
            // Layout uses a top-left origin; Core Image uses bottom-left.
            let ciY = Double(request.outputSize.height) - frame.y - frame.height
            let placed = watermark
                .transformed(by: CGAffineTransform(
                    scaleX: frame.width / max(1, watermark.extent.width),
                    y: frame.height / max(1, watermark.extent.height)))
                .transformed(by: CGAffineTransform(translationX: frame.x, y: ciY))
            image = placed.composited(over: image)
        }
        return image.cropped(to: bounds)
    }

    /// Renders into a pixel buffer and returns after the GPU work completed (05 V04).
    func render(_ image: CIImage, to buffer: CVPixelBuffer) {
        context.render(
            image, to: buffer,
            bounds: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)),
            colorSpace: outputColorSpace)
    }

    // MARK: Graph pieces

    /// Upright, origin-anchored and sized. `exact` stretches to the size (single-source output
    /// already has the source aspect); otherwise aspect-fill with a centred crop.
    private func normalized(_ source: CIImage, _ orientation: CGImagePropertyOrientation, mirrored: Bool, fill size: CGSize, exact: Bool) -> CIImage {
        var image = source.oriented(orientation)
        if mirrored { image = image.oriented(.upMirrored) }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if exact { return scaled(image, to: size) }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(size.width / extent.width, size.height / extent.height)
        let fitted = CGSize(width: (extent.width * scale).rounded(), height: (extent.height * scale).rounded())
        let filled = scaled(image, to: fitted)
        let offset = CGAffineTransform(
            translationX: -((fitted.width - size.width) / 2).rounded(), y: -((fitted.height - size.height) / 2).rounded())
        return filled.transformed(by: offset).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Look then Beat, identical for every source of the request.
    private func creative(_ image: CIImage, _ request: FrameRequest) -> CIImage {
        var image = image
        if !request.bypassCreative, request.recipe.intensity.value > 0, request.recipe.lookID != nil {
            image = lookGraph(image, recipe: request.recipe, time: request.time)
        }
        // Beat is an independent modulation layer (05 V04), applied even at Look intensity 0.
        if !request.bypassCreative, request.beat != .none {
            image = beatModulated(image, request.beat)
        }
        return image
    }

    private func roundedMask(size: CGSize, radius: Double) -> CIImage {
        let filter = CIFilter.roundedRectangleGenerator()
        filter.extent = CGRect(origin: .zero, size: size)
        filter.radius = Float(radius)
        filter.color = .white
        return filter.outputImage ?? CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func scaled(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = size.height / extent.height
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = Float((size.width / extent.width) / scale)
        return filter.outputImage ?? image
    }

    private func place(_ overlay: CIImage, in frame: WatermarkLayout.Rect, outputHeight: CGFloat) -> CIImage {
        let ciY = Double(outputHeight) - frame.y - frame.height
        return overlay
            .transformed(by: CGAffineTransform(
                scaleX: frame.width / max(1, overlay.extent.width),
                y: frame.height / max(1, overlay.extent.height)))
            .transformed(by: CGAffineTransform(translationX: frame.x, y: ciY))
    }

    private func beatModulated(_ image: CIImage, _ beat: BeatModulation) -> CIImage {
        let extent = image.extent
        var result = image
        if beat.zoom > 0 {
            let scale = 1 + beat.zoom
            let transform = CGAffineTransform(translationX: extent.midX, y: extent.midY)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -extent.midX, y: -extent.midY)
            result = result.transformed(by: transform).cropped(to: extent)
        }
        if beat.brightness > 0 {
            let controls = CIFilter.colorControls()
            controls.inputImage = result
            controls.brightness = Float(beat.brightness)
            controls.saturation = 1
            controls.contrast = 1
            result = controls.outputImage ?? result
        }
        return result
    }

    private func lookGraph(_ image: CIImage, recipe: Recipe, time: RationalTime) -> CIImage {
        let extent = image.extent
        var result = image

        let lutMix = min(1, recipe.effectiveParameter(LookParameter.lutMix))
        if lutMix > 0, let lookID = recipe.lookID, let lut = luts.lut(for: lookID) {
            let cube = CIFilter.colorCubeWithColorSpace()
            cube.inputImage = result
            cube.cubeDimension = Float(lut.dimension)
            cube.cubeData = lut.data
            cube.colorSpace = lutColorSpace
            if let graded = cube.outputImage {
                let mix = CIFilter.dissolveTransition()
                mix.inputImage = result
                mix.targetImage = graded
                mix.time = Float(lutMix)
                result = mix.outputImage ?? graded
            }
        }

        let saturation = recipe.effectiveParameter(LookParameter.saturation)
        let contrast = recipe.effectiveParameter(LookParameter.contrast)
        if saturation != 0 || contrast != 0 {
            let color = CIFilter.colorControls()
            color.inputImage = result
            color.saturation = Float(max(0, 1 + saturation))
            color.contrast = Float(max(0, 1 + contrast))
            color.brightness = 0
            result = color.outputImage ?? result
        }

        let warmth = recipe.effectiveParameter(LookParameter.warmth)
        if warmth != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = result
            temperature.neutral = CIVector(x: 6500, y: 0)
            // Tint follows warmth slightly (≈12 at 1400 K) for a filmic magenta-warm cast.
            temperature.targetNeutral = CIVector(x: CGFloat(6500 - warmth), y: CGFloat(warmth * 12 / 1400))
            result = temperature.outputImage ?? result
        }

        let vignette = recipe.effectiveParameter(LookParameter.vignette)
        if vignette > 0 {
            let filter = CIFilter.vignette()
            filter.inputImage = result
            filter.intensity = Float(vignette)
            filter.radius = Float(max(extent.width, extent.height) / 900)
            result = filter.outputImage ?? result
        }

        return grain(
            over: result.cropped(to: extent), extent: extent,
            amount: Float(recipe.effectiveParameter(LookParameter.grain)),
            size: recipe.shapeParameter(LookParameter.grainSize, fallback: FilmGrain.defaultSize),
            chroma: recipe.shapeParameter(LookParameter.grainChroma, fallback: FilmGrain.defaultChroma),
            seed: recipe.seed, time: time)
    }

    /// Deterministic film grain: the infinite random field is offset by (seed, media tick), so the
    /// same recipe and media time reproduce the same pixels at any export frame rate. Cells are sized
    /// relative to the frame's short edge (`FilmGrain.cellScale`) and sampled linearly for soft clumps;
    /// `chroma` mixes in per-channel colour grain. The overlay blend keeps deep shadows and highlights
    /// cleaner than midtones, as film grain does.
    private func grain(
        over image: CIImage, extent: CGRect, amount: Float, size: Double, chroma: Double, seed: UInt64, time: RationalTime
    ) -> CIImage {
        guard amount > 0, let noise = CIFilter.randomGenerator().outputImage else { return image }
        let tick = Self.noiseTick(time)
        var mixer = seed &+ UInt64(bitPattern: tick) &* 0x9E37_79B9_7F4A_7C15
        mixer ^= mixer >> 31
        let offsetX = CGFloat(mixer % 4096)
        let offsetY = CGFloat((mixer >> 16) % 4096)
        let scale = CGFloat(FilmGrain.cellScale(shortEdge: Double(min(extent.width, extent.height)), grainSize: size))

        let colour = CIFilter.colorMatrix()
        colour.inputImage = noise
            .transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        // Noise around mid-grey (rows sum to 1), alpha = grain strength.
        let rows = FilmGrain.channelWeights(chroma: chroma).map { row in
            CIVector(x: CGFloat(row[0]), y: CGFloat(row[1]), z: CGFloat(row[2]), w: 0)
        }
        colour.rVector = rows[0]
        colour.gVector = rows[1]
        colour.bVector = rows[2]
        colour.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        colour.biasVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))

        guard let grainLayer = colour.outputImage?.cropped(to: extent) else { return image }
        let blend = CIFilter.overlayBlendMode()
        blend.inputImage = grainLayer
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    static func noiseTick(_ time: RationalTime) -> Int64 {
        // floor(time * 60) without floating point.
        let numerator = time.value.multipliedReportingOverflow(by: noiseTicksPerSecond)
        guard !numerator.overflow else { return Int64(time.approximateSeconds * Double(noiseTicksPerSecond)) }
        let result = numerator.partialValue / Int64(time.timescale)
        return numerator.partialValue < 0 && numerator.partialValue % Int64(time.timescale) != 0 ? result - 1 : result
    }

    /// EXIF-style orientation for an AV preferred transform (90° steps and mirrors).
    static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        case (-1, 0, 0, 1): .upMirrored
        case (1, 0, 0, -1): .downMirrored
        case (0, 1, 1, 0): .leftMirrored
        case (0, -1, -1, 0): .rightMirrored
        default: .up
        }
    }
}
