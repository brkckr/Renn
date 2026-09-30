import AVFoundation
import CoreImage
import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers
import RENNDomain

/// Bundled demo clips (owner-approved, provenance in docs/IMPLEMENTATION_LEDGER.md): the Pexels
/// street clip for Look posters, the Home hero and onboarding pages 1, 2 and 4; the Pexels dance
/// clip with RENN's own generated house beat (scripts/generate_demo_beat.py) for the Beat page.
enum DemoClip: String, CaseIterable, Sendable {
    case street = "renn_demo_street"
    case dance = "renn_demo_dance"

    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "mp4") }
}

/// Showcase media for Home and onboarding (owner-approved): catalog Look posters, catalog lookup
/// and the Beat demo timeline. Posters are real renders of each Look over one street frame
/// through the shared RenderEngine, never stand-in art; a failed render leaves the plain
/// placeholder. Nothing here creates or touches projects.
@MainActor
@Observable
final class ShowcaseMedia {
    /// Look used by the clean-to-Look scene and the tape on page 4.
    static let heroLookID: LookID = "renn.super8_pop"
    /// Three distinct moods for the Look cards scene (page 2).
    static let cardLookIDs: [LookID] = ["renn.sunday_polaroid", "renn.rainy_matinee", "renn.noir_grain"]
    /// Look over the Beat demo (page 3).
    static let beatLookID: LookID = "renn.late_night_vhs"

    let engine: RenderEngine

    /// Rendered posters by Look ID and version; observed so poster views update when ready.
    private(set) var posters: [String: UIImage] = [:]

    @ObservationIgnored private let lookCatalog: any LookCatalogProviding
    @ObservationIgnored private let beatTimelines: AVBeatTimelineProvider
    @ObservationIgnored private let renderer: LookPosterRenderer
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var catalogTask: Task<LookCatalog?, Never>?
    @ObservationIgnored private var danceTimelineTask: Task<BeatTimeline?, Never>?

    init(engine: RenderEngine, lookCatalog: any LookCatalogProviding, beatTimelines: AVBeatTimelineProvider) {
        self.engine = engine
        self.lookCatalog = lookCatalog
        self.beatTimelines = beatTimelines
        renderer = LookPosterRenderer(engine: engine)
    }

    func poster(for look: LookDefinition) -> UIImage? {
        posters[Self.key(look)]
    }

    /// Renders the Look's poster once per app run; later calls return immediately.
    func loadPoster(for look: LookDefinition) async {
        let key = Self.key(look)
        if posters[key] != nil { return }
        if let running = inFlight[key] {
            await running.value
            return
        }
        let renderer = renderer
        let task = Task { [weak self] in
            // Decoded off the main thread, so a grid of new posters never hitches a sheet.
            guard let data = await renderer.posterJPEG(for: look),
                  let image = await UIImage(data: data)?.byPreparingForDisplay()
            else { return }
            self?.posters[key] = image
        }
        inFlight[key] = task
        await task.value
        inFlight[key] = nil
    }

    func look(_ id: LookID) async -> LookDefinition? {
        await catalog()?.look(id)
    }

    func catalog() async -> LookCatalog? {
        if let catalogTask { return await catalogTask.value }
        let lookCatalog = lookCatalog
        let task = Task<LookCatalog?, Never> { try? await lookCatalog.catalog() }
        catalogTask = task
        return await task.value
    }

    /// Beat timeline of the dance demo's own audio, analysed once per run like any source (05 V05).
    func danceBeatTimeline() async -> BeatTimeline? {
        if let danceTimelineTask { return await danceTimelineTask.value }
        let beatTimelines = beatTimelines
        let task = Task<BeatTimeline?, Never> {
            guard let url = DemoClip.dance.url else { return nil }
            return try? await beatTimelines.bundledTimeline(for: url, key: "demo-\(DemoClip.dance.rawValue)")
        }
        danceTimelineTask = task
        return await task.value
    }

    /// Demo recipe: the Look at its catalog default intensity, optional Beat, indicators off.
    nonisolated static func recipe(for look: LookDefinition?, beatIntensity: Double? = nil) -> Recipe {
        var recipe = Recipe.initial(look: look, creationStamp: demoStamp, seed: 0x52454E4E)
        if let beatIntensity {
            recipe.beat = BeatSettings(isEnabled: true, intensity: beatIntensity)
        }
        return recipe
    }

    /// Fixed stamp for demo recipes; indicators are off, so it is never drawn.
    nonisolated private static let demoStamp: StampDate = (try? StampDate(year: 2026, month: 1, day: 1))!

    private static func key(_ look: LookDefinition) -> String {
        "\(look.id.rawValue)-\(look.version)"
    }
}

/// Renders catalog Look posters from one frame of the street demo (owner-approved), with the
/// same graph as preview and export at the Look's default intensity. Memory only: the frame is
/// decoded once and each poster is a small JPEG.
actor LookPosterRenderer {
    /// Frame time in the street clip: city, sky and street all in view.
    static let frameTime = RationalTime.seconds(2)

    private let engine: RenderEngine
    private let size = CGSize(width: 540, height: 960)
    private var frame: (image: CIImage, orientation: CGImagePropertyOrientation)?
    private var frameFailed = false

    init(engine: RenderEngine) {
        self.engine = engine
    }

    func posterJPEG(for look: LookDefinition) async -> Data? {
        guard let frame = await sourceFrame() else { return nil }
        let request = RenderEngine.FrameRequest(
            source: frame.image, orientation: frame.orientation,
            recipe: ShowcaseMedia.recipe(for: look), time: Self.frameTime,
            outputSize: size, watermark: nil, watermarkFrame: nil)
        guard let rendered = engine.context.createCGImage(
            engine.image(for: request), from: CGRect(origin: .zero, size: size),
            format: .RGBA8, colorSpace: engine.outputColorSpace)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, rendered, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func sourceFrame() async -> (image: CIImage, orientation: CGImagePropertyOrientation)? {
        if let frame { return frame }
        guard !frameFailed, let url = DemoClip.street.url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform)
        else {
            frameFailed = true
            return nil
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = false
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(value: Self.frameTime.value, timescale: Self.frameTime.timescale)
        guard let (cgImage, _) = try? await generator.image(at: time) else {
            frameFailed = true
            return nil
        }
        let decoded = (CIImage(cgImage: cgImage), RenderEngine.orientation(for: transform))
        frame = decoded
        return decoded
    }
}
