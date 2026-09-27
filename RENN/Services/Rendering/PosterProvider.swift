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
        guard let record = try? await projects.project(projectID), record.readiness == .ready,
              let source = record.sources.first(where: { $0.role == .primary }) ?? record.sources.first
        else { return nil }
        let key = PosterPolicy.cacheKey(
            project: projectID, recipeRevision: record.recipeRevision, renderVersion: record.recipe.renderVersion)
        let file = cacheDirectory.appendingPathComponent("\(key).jpg")
        if let cached = try? Data(contentsOf: file) { return cached }

        let url = await projects.fileURL(source.relativePath)
        guard let data = await Self.render(
            url: url, source: source, recipe: record.recipe, engine: engine, maximumPixelSize: maximumPixelSize)
        else { return nil }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }

    private static func render(
        url: URL, source: SourceReference, recipe: Recipe, engine: RenderEngine, maximumPixelSize: Int
    ) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        let time = PosterPolicy.representativeTime(duration: source.metadata.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        // Orientation is applied by the render graph, exactly as in preview/export.
        generator.appliesPreferredTrackTransform = false
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        guard let (cgImage, _) = try? await generator.image(at: CMTime(value: time.value, timescale: time.timescale))
        else { return nil }

        let display = source.metadata.displayDimensions
        let scale = min(1, Double(maximumPixelSize) / Double(display.longEdge))
        let size = CGSize(
            width: max(2, (Double(display.width) * scale).rounded()),
            height: max(2, (Double(display.height) * scale).rounded()))
        let image = engine.image(for: RenderEngine.FrameRequest(
            source: CIImage(cgImage: cgImage), orientation: RenderEngine.orientation(for: transform),
            recipe: recipe, time: time, outputSize: size, watermark: nil, watermarkFrame: nil))
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
