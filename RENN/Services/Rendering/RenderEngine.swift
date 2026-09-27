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
/// M02 ships one clearly labelled DIAGNOSTIC Look (development fixture, not an approved RENN
/// Look): mild desaturation/warmth, vignette and deterministic grain, scaled by intensity.
/// M03 replaces this with the versioned LUT/shader engine for the catalog.
///
/// Thread safety: `CIContext` is documented as thread-safe and the engine holds no mutable
/// state, so one instance is shared across preview and export queues.
final class RenderEngine: @unchecked Sendable {
    static let noiseTicksPerSecond: Int64 = 60

    let context: CIContext
    let outputColorSpace: CGColorSpace
    /// Shared GPU device for preview drawables (04 A03 app-lifetime GPU context).
    let device: MTLDevice?

    init() {
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
    }

    /// Builds the frame graph. Lazy: no GPU work happens until `render`.
    func image(for request: FrameRequest) -> CIImage {
        var image = request.source.oriented(request.orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        image = scaled(image, to: request.outputSize)

        let intensity = request.recipe.intensity.value
        if !request.bypassCreative, intensity > 0, request.recipe.lookID != nil {
            image = diagnosticLook(image, intensity: intensity, seed: request.recipe.seed, time: request.time)
        }
        // Beat is an independent modulation layer (05 V04), applied even at Look intensity 0.
        if !request.bypassCreative, request.beat != .none {
            image = beatModulated(image, request.beat)
        }

        let bounds = CGRect(origin: .zero, size: request.outputSize)
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

    private func diagnosticLook(_ image: CIImage, intensity: Double, seed: UInt64, time: RationalTime) -> CIImage {
        let extent = image.extent
        let amount = Float(intensity)

        let color = CIFilter.colorControls()
        color.inputImage = image
        color.saturation = 1 - 0.35 * amount
        color.contrast = 1 + 0.08 * amount
        color.brightness = 0

        let warmth = CIFilter.temperatureAndTint()
        warmth.inputImage = color.outputImage
        warmth.neutral = CIVector(x: 6500, y: 0)
        warmth.targetNeutral = CIVector(x: CGFloat(6500 - 1400 * intensity), y: CGFloat(12 * intensity))

        let vignette = CIFilter.vignette()
        vignette.inputImage = warmth.outputImage
        vignette.intensity = 0.7 * amount
        vignette.radius = Float(max(extent.width, extent.height) / 900)

        guard let graded = vignette.outputImage else { return image }
        return grain(over: graded, extent: extent, amount: 0.10 * amount, seed: seed, time: time)
    }

    /// Deterministic grain: the infinite random field is offset by (seed, media tick), so the
    /// same recipe and media time reproduce the same pixels at any export frame rate.
    private func grain(over image: CIImage, extent: CGRect, amount: Float, seed: UInt64, time: RationalTime) -> CIImage {
        guard amount > 0, let noise = CIFilter.randomGenerator().outputImage else { return image }
        let tick = Self.noiseTick(time)
        var mixer = seed &+ UInt64(bitPattern: tick) &* 0x9E37_79B9_7F4A_7C15
        mixer ^= mixer >> 31
        let offsetX = CGFloat(mixer % 4096)
        let offsetY = CGFloat((mixer >> 16) % 4096)

        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise.transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))
        // Luma-only noise around mid-grey, alpha = grain strength.
        let weight = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        mono.rVector = weight
        mono.gVector = weight
        mono.bVector = weight
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))

        guard let grainLayer = mono.outputImage?.cropped(to: extent) else { return image }
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
