import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import RENNDomain

/// Renders a project's own processed frame for its VHS case (01 P03, 05 V07): the source
/// frame at `PosterPolicy.representativeTime`, through the shared RenderEngine with the
/// project's current recipe (no watermark), cached as JPEG in `Caches/RENN/Posters`.
/// Missing or failing sources return nil; no unrelated image is ever substituted.
actor PosterProvider: PosterProviding {
    private let projects: any ProjectStoring
    private let engine: RenderEngine
    private let cacheDirectory: URL
    private let maximumPixelSize: Int

    init(
        projects: any ProjectStoring,
        engine: RenderEngine,
        cacheDirectory: URL = URL.cachesDirectory.appendingPathComponent("RENN/Posters", isDirectory: true),
        maximumPixelSize: Int = 480
    ) {
        self.projects = projects
        self.engine = engine
        self.cacheDirectory = cacheDirectory
        self.maximumPixelSize = maximumPixelSize
    }

    func posterJPEG(for projectID: ProjectID) async -> Data? {
        guard let record = try? await projects.project(projectID), record.readiness == .ready else { return nil }
        let key = PosterPolicy.cacheKey(
            project: projectID, recipeRevision: record.recipeRevision, renderVersion: record.recipe.renderVersion)
        let file = cacheDirectory.appendingPathComponent("\(key).jpg")
        if let cached = try? Data(contentsOf: file) { return cached }

        guard let data = await render(record) else { return nil }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// Single source, or the Dual-Cam composite (main + inset at the same composition time).
    private func render(_ record: ProjectRecord) async -> Data? {
        let rear = record.sources.first { $0.role == .rearCamera }
        let front = record.sources.first { $0.role == .frontCamera }
        if let rear, let front, let layout = record.recipe.dualLayout {
            guard let timing = try? DualSourceTiming(
                rearStart: rear.metadata.startOffset, rearDuration: rear.metadata.duration,
                frontStart: front.metadata.startOffset, frontDuration: front.metadata.duration)
            else { return nil }
            let time = PosterPolicy.representativeTime(duration: timing.duration)
            guard let rearFrame = await frame(await projects.fileURL(rear.relativePath), at: time + timing.rearOffset),
                  let frontFrame = await frame(await projects.fileURL(front.relativePath), at: time + timing.frontOffset)
            else { return nil }
            let (main, inset) = layout.mainCamera(at: time) == .rear ? (rearFrame, frontFrame) : (frontFrame, rearFrame)
            let size = outputSize(rear.metadata.displayDimensions)
            var request = RenderEngine.FrameRequest(
                source: main.image, orientation: main.orientation, recipe: record.recipe, time: time,
                outputSize: size, watermark: nil, watermarkFrame: nil)
            if let canvas = try? PixelDimensions(width: Int(size.width), height: Int(size.height)) {
                request.inset = RenderEngine.Inset(
                    source: inset.image, orientation: inset.orientation, mirrored: false,
                    layout: DualInsetLayout(canvas: canvas, corner: layout.insetCorner))
            }
            return encode(engine.image(for: request), size: size)
        }
        guard let source = record.sources.first(where: { $0.role == .primary }) ?? record.sources.first else { return nil }
        let time = PosterPolicy.representativeTime(duration: source.metadata.duration)
        guard let single = await frame(await projects.fileURL(source.relativePath), at: time) else { return nil }
        let size = outputSize(source.metadata.displayDimensions)
        return encode(engine.image(for: RenderEngine.FrameRequest(
            source: single.image, orientation: single.orientation, recipe: record.recipe, time: time,
            outputSize: size, watermark: nil, watermarkFrame: nil)), size: size)
    }

    private func outputSize(_ display: PixelDimensions) -> CGSize {
        let scale = min(1, Double(maximumPixelSize) / Double(display.longEdge))
        return CGSize(
            width: max(2, (Double(display.width) * scale).rounded()),
            height: max(2, (Double(display.height) * scale).rounded()))
    }

    /// Decoded source frame in storage orientation; the render graph applies orientation, as in
    /// preview/export.
    private func frame(_ url: URL, at time: RationalTime) async -> (image: CIImage, orientation: CGImagePropertyOrientation)? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = false
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        guard let (cgImage, _) = try? await generator.image(at: CMTime(value: time.value, timescale: time.timescale))
        else { return nil }
        return (CIImage(cgImage: cgImage), RenderEngine.orientation(for: transform))
    }

    private func encode(_ image: CIImage, size: CGSize) -> Data? {
        guard let rendered = engine.context.createCGImage(
            image, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: engine.outputColorSpace)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, rendered, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
