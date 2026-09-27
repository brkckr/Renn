import AVFoundation
import CoreImage
import Foundation
import Testing
import UIKit
import RENNDomain
import RENNStorage
@testable import RENN

/// Media integration on the Simulator (07 test level 3): a synthesized fixture goes through the
/// real importer, project store, render engine, writer and validator, and the decoded output is
/// inspected. Simulator results do not replace device validation (camera, GPU speed, HDR).
// CI simulators render on the CPU (about a second per 1080×1920 frame), so fixtures stay short.
@Suite("Media pipeline (Simulator integration)", .serialized, .timeLimit(.minutes(5)))
struct MediaPipelineTests {
    struct Fixture {
        let directory: URL
        let url: URL
    }

    /// 1080×1920, 60 FPS, H.264, with a 1 kHz mono AAC tone when `audio` is true. Frames are a
    /// flat `color` (8-bit RGB), or a shade that changes every frame when nil.
    static func makeFixture(
        seconds: Double = 1, fps: Int32 = 60, audio: Bool = true, color: (UInt8, UInt8, UInt8)? = nil
    ) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("renn-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let width = 1080, height = 1920
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        let sampleRate = 48_000.0
        if audio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: sampleRate,
                AVEncoderBitRateKey: 96_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let frameCount = Int(seconds * Double(fps))
        let totalAudioFrames = audioInput == nil ? 0 : Int(seconds * sampleRate)
        let chunk = 1024
        var format: CMAudioFormatDescription?
        if audioInput != nil {
            var description = AudioStreamBasicDescription(
                mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                mBitsPerChannel: 16, mReserved: 0)
            CMAudioFormatDescriptionCreate(
                allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
                magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        }

        // Interleave by media time: AVAssetWriter stalls one track while waiting for the other.
        var videoIndex = 0
        var audioWritten = 0
        while videoIndex < frameCount || audioWritten < totalAudioFrames {
            let videoTime = Double(videoIndex) / Double(fps)
            let audioTime = Double(audioWritten) / sampleRate
            let writeVideo = videoIndex < frameCount && (audioWritten >= totalAudioFrames || videoTime <= audioTime)
            if writeVideo {
                guard videoInput.isReadyForMoreMediaData else {
                    try await Task.sleep(nanoseconds: 1_000_000)
                    continue
                }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
                let shade = UInt8((videoIndex % 60) * 255 / 60)
                Self.fill(buffer!, rgb: color ?? (shade, 102, 255 - shade))
                #expect(adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(videoIndex), timescale: fps)))
                videoIndex += 1
                if videoIndex == frameCount { videoInput.markAsFinished() }
            } else if let audioInput, let format {
                guard audioInput.isReadyForMoreMediaData else {
                    try await Task.sleep(nanoseconds: 1_000_000)
                    continue
                }
                let count = min(chunk, totalAudioFrames - audioWritten)
                var samples = (0..<count).map { offset -> Int16 in
                    Int16(sin(2 * .pi * 1000 * Double(audioWritten + offset) / sampleRate) * 8000)
                }
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(
                    allocator: nil, memoryBlock: nil, blockLength: count * 2, blockAllocator: nil,
                    customBlockSource: nil, offsetToData: 0, dataLength: count * 2, flags: 0, blockBufferOut: &block)
                samples.withUnsafeMutableBytes { bytes in
                    _ = CMBlockBufferReplaceDataBytes(
                        with: bytes.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: count * 2)
                }
                var sample: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: nil, dataBuffer: block!, formatDescription: format, sampleCount: count,
                    presentationTimeStamp: CMTime(value: CMTimeValue(audioWritten), timescale: CMTimeScale(sampleRate)),
                    packetDescriptions: nil, sampleBufferOut: &sample)
                #expect(audioInput.append(sample!))
                audioWritten += count
                if audioWritten >= totalAudioFrames { audioInput.markAsFinished() }
            }
        }
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return Fixture(directory: directory, url: url)
    }

    /// Fills a BGRA buffer with one colour directly in memory (no GPU/Core Image on the Simulator).
    static func fill(_ buffer: CVPixelBuffer, rgb: (UInt8, UInt8, UInt8)) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for x in 0..<width {
            base[x * 4] = rgb.2
            base[x * 4 + 1] = rgb.1
            base[x * 4 + 2] = rgb.0
            base[x * 4 + 3] = 255
        }
        for y in 1..<height {
            (base + y * rowBytes).update(from: base, count: width * 4)
        }
    }

    /// Counts decoded video frames of a file.
    static func frameCount(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 { count += 1 }
        }
        return count
    }

    private func makeLibrary(_ directory: URL) throws -> ProjectLibrary {
        ProjectLibrary(
            metadata: SwiftDataProjectMetadataStore(modelContainer: try PersistenceController.makeInMemoryContainer()),
            files: FileSystemOwnedFileStore(
                rootURL: directory.appendingPathComponent("RENN"), temporaryURL: directory.appendingPathComponent("tmp")))
    }

    private func importAndCreate(_ fixture: Fixture, library: ProjectLibrary) async throws -> ProjectRecord {
        let picked = fixture.directory.appendingPathComponent("picked.mov")
        try FileManager.default.copyItem(at: fixture.url, to: picked)
        let prepared = try await AVVideoImporter(projects: library).prepare(pickedFile: picked)
        return try await library.createProject(NewProjectDraft(
            createdAt: Date(), name: try ProjectName("Fixture"), sourceMode: .imported,
            sources: [StagedSource(
                role: .primary, stagedFile: prepared.stagedFile, fileName: "source.mov",
                metadata: SourceMetadata(
                    duration: prepared.profile.duration, displayDimensions: prepared.profile.displayDimensions,
                    frameRate: prepared.profile.frameRate, hasUsableAudio: prepared.profile.hasUsableAudio,
                    ownsSharedAudio: prepared.profile.hasUsableAudio, isHDR: prepared.isHDR))],
            recipe: Recipe.initial(
                look: LookDefinition(
                    id: "dev.diagnostic", version: 1, family: "diagnostic", nameKey: "n", descriptionKey: "d",
                    defaultIntensity: LookIntensity(0.7)!, renderVersion: 1, isDevelopmentFixture: true),
                creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 7)))
    }

    @Test func importInspectsDisplayDimensionsCadenceAndAudio() async throws {
        let fixture = try await Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let library = try makeLibrary(fixture.directory)
        let record = try await importAndCreate(fixture, library: library)
        let metadata = try #require(record.sources.first?.metadata)
        #expect(metadata.displayDimensions == (try PixelDimensions(width: 1080, height: 1920)))
        #expect(abs(metadata.frameRate.approximateFPS - 60) < 0.5)
        #expect(abs(metadata.duration.approximateSeconds - 1) < 0.05)
        #expect(metadata.hasUsableAudio)
        #expect(metadata.isHDR == false)
        #expect(record.readiness == .ready)
    }

    @Test func freeExportIs720pThirtyFPSWithAudioAndSameDuration() async throws {
        let fixture = try await Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let library = try makeLibrary(fixture.directory)
        let record = try await importAndCreate(fixture, library: library)
        let plan = try ExportPlan.make(record: record, access: .notConfigured)
        #expect(plan.policy.dimensions == (try PixelDimensions(width: 720, height: 1280)))
        #expect(plan.policy.frameRate == .fps(30))

        let output = try await library.makeJobFileURL(fileExtension: "mp4")
        let duration = try await AVExportRenderer(engine: RenderEngine()).render(
            plan: plan, sourceURL: await library.fileURL(plan.source.relativePath), outputURL: output) { _ in }

        let asset = AVURLAsset(url: output)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await video.load(.naturalSize)
        #expect(Int(size.width) == 720 && Int(size.height) == 1280)
        #expect(!(try await asset.loadTracks(withMediaType: .audio)).isEmpty, "Source audio is kept")
        #expect(abs(duration.approximateSeconds - 1) < 0.1, "Duration within one or two frames")
        let frames = try await Self.frameCount(output)
        #expect(abs(frames - 30) <= 1, "60 FPS input becomes 30 FPS without retiming (got \(frames))")
    }

    @Test func mutedProjectExportsWithoutAudioTrack() async throws {
        let fixture = try await Self.makeFixture(seconds: 1)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let library = try makeLibrary(fixture.directory)
        var record = try await importAndCreate(fixture, library: library)
        var recipe = record.recipe
        recipe.audioMuted = true
        record = try await library.updateRecipe(record.id, expectedRevision: record.recipeRevision, recipe: recipe)
        let plan = try ExportPlan.make(record: record, access: .notConfigured)
        #expect(!plan.includesAudio)
        let output = try await library.makeJobFileURL(fileExtension: "mp4")
        _ = try await AVExportRenderer(engine: RenderEngine()).render(
            plan: plan, sourceURL: await library.fileURL(plan.source.relativePath), outputURL: output) { _ in }
        #expect((try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)).isEmpty)
    }

    @Test func proExportKeepsSourceDimensionsAndCadence() async throws {
        let fixture = try await Self.makeFixture(seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let library = try makeLibrary(fixture.directory)
        let record = try await importAndCreate(fixture, library: library)
        let plan = try ExportPlan.make(record: record, access: AccessState(level: .pro, provenance: .developmentFake))
        #expect(!plan.policy.requiresWatermark)
        let output = try await library.makeJobFileURL(fileExtension: "mp4")
        _ = try await AVExportRenderer(engine: RenderEngine()).render(
            plan: plan, sourceURL: await library.fileURL(plan.source.relativePath), outputURL: output) { _ in }
        let size = try await #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).first).load(.naturalSize)
        #expect(Int(size.width) == 1080 && Int(size.height) == 1920)
        let frames = try await Self.frameCount(output)
        #expect(abs(frames - 30) <= 1, "Pro keeps 60 FPS: 0.5 s → 30 frames (got \(frames))")
    }

    @Test func renderIsDeterministicForTheSameRecipeAndTime() throws {
        let engine = RenderEngine()
        let source = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let recipe = Recipe.initial(
            look: LookDefinition(
                id: "dev.diagnostic", version: 1, family: "diagnostic", nameKey: "n", descriptionKey: "d",
                defaultIntensity: LookIntensity(1)!, renderVersion: 1, isDevelopmentFixture: true,
                parameters: [LookParameter.saturation: -0.35, LookParameter.grain: 0.1]),
            creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 99)
        func pixels(at time: RationalTime) -> [UInt8] {
            let image = engine.image(for: RenderEngine.FrameRequest(
                source: source, orientation: .up, recipe: recipe, time: time,
                outputSize: CGSize(width: 64, height: 64), watermark: nil, watermarkFrame: nil))
            var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
            engine.context.render(
                image, toBitmap: &bytes, rowBytes: 64 * 4, bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
                format: .RGBA8, colorSpace: engine.outputColorSpace)
            return bytes
        }
        let first = pixels(at: .seconds(1))
        #expect(pixels(at: .seconds(1)) == first, "Same recipe and media time reproduce the same pixels")
        #expect(pixels(at: try RationalTime(value: 61, timescale: 60)) != first, "Grain advances with media time")
    }

    /// RGBA bytes of a region of the frame at `seconds`, for before/after comparisons.
    static func regionBytes(_ url: URL, at seconds: Double, region: CGRect) async throws -> [UInt8] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        let width = Int(region.width), height = Int(region.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // CGContext has a bottom-left origin; draw the image offset so `region` (top-left) lands at 0,0.
        context.draw(image, in: CGRect(
            x: -region.minX, y: -(CGFloat(image.height) - region.maxY),
            width: CGFloat(image.width), height: CGFloat(image.height)))
        return bytes
    }

    @Test func dateIndicatorIsDrawnIntoTheExport() async throws {
        let fixture = try await Self.makeFixture(seconds: 0.5, audio: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let library = try makeLibrary(fixture.directory)
        var record = try await importAndCreate(fixture, library: library)
        // Free 720p keeps the two renders cheap; the watermark sits clear of the date (IndicatorLayout).
        let access = AccessState.notConfigured

        let plain = try await library.makeJobFileURL(fileExtension: "mp4")
        let plainPlan = try ExportPlan.make(record: record, access: access)
        _ = try await AVExportRenderer(engine: RenderEngine()).render(
            plan: plainPlan, sourceURL: await library.fileURL(plainPlan.source.relativePath), outputURL: plain) { _ in }

        var recipe = record.recipe
        recipe.indicators.showsDate = true
        record = try await library.updateRecipe(record.id, expectedRevision: record.recipeRevision, recipe: recipe)
        let dated = try await library.makeJobFileURL(fileExtension: "mp4")
        let datedPlan = try ExportPlan.make(record: record, access: access)
        _ = try await AVExportRenderer(engine: RenderEngine()).render(
            plan: datedPlan, sourceURL: await library.fileURL(datedPlan.source.relativePath), outputURL: dated) { _ in }

        // Same reservation as the export: the date moves above the Free watermark.
        let dimensions = datedPlan.policy.dimensions
        let watermark = try #require(WatermarkRenderer.render(
            width: Double(dimensions.shortEdge) * WatermarkLayout.maximumWidthFraction))
        let watermarkFrame = WatermarkLayout(output: dimensions, aspectRatio: watermark.aspectRatio).frame
        let layout = IndicatorLayout.resolve(output: dimensions, settings: recipe.indicators, reserved: [watermarkFrame])
        let frame = try #require(layout.indicators.first?.frame)
        let region = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        let before = try await Self.regionBytes(plain, at: 0.25, region: region)
        let after = try await Self.regionBytes(dated, at: 0.25, region: region)
        let changed = zip(before, after).filter { abs(Int($0) - Int($1)) > 24 }.count
        #expect(changed > before.count / 50, "Date glyphs change the bottom-right region (changed bytes: \(changed))")
    }

    @Test func posterIsTheProjectsOwnProcessedFrameAndIsCached() async throws {
        let fixture = try await Self.makeFixture(seconds: 1, audio: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let library = try makeLibrary(fixture.directory)
        let record = try await importAndCreate(fixture, library: library)
        let cache = fixture.directory.appendingPathComponent("Posters")
        let provider = PosterProvider(projects: library, engine: RenderEngine(), cacheDirectory: cache)
        let data = try #require(await provider.posterJPEG(for: record.id))
        let image = try #require(UIImage(data: data))
        #expect(Int(image.size.height) == 480 && Int(image.size.width) == 270, "Portrait ratio kept, long edge 480")
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        #expect(files.count == 1)
        #expect(await provider.posterJPEG(for: record.id) == data, "Second call is served from the cache")
        #expect(await provider.posterJPEG(for: ProjectID()) == nil, "Unknown project: no substitute image")
    }

    /// Mean RGB of a small region at `seconds`.
    static func meanColor(_ url: URL, at seconds: Double, centre: (x: Double, y: Double)) async throws -> (r: Int, g: Int, b: Int) {
        let bytes = try await regionBytes(url, at: seconds, region: CGRect(x: centre.x - 4, y: centre.y - 4, width: 8, height: 8))
        var sums = (0, 0, 0)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            sums.0 += Int(bytes[index]); sums.1 += Int(bytes[index + 1]); sums.2 += Int(bytes[index + 2])
        }
        let count = bytes.count / 4
        return (sums.0 / count, sums.1 / count, sums.2 / count)
    }

    @Test func dualCamExportComposesBothSourcesAndReplaysTheSwap() async throws {
        // Rear = red with the shared audio, front = green starting 0.1 s later on the shared clock.
        let rearFixture = try await Self.makeFixture(seconds: 1, fps: 30, audio: true, color: (220, 40, 40))
        let frontFixture = try await Self.makeFixture(seconds: 1, fps: 30, audio: false, color: (40, 200, 60))
        defer {
            try? FileManager.default.removeItem(at: rearFixture.directory)
            try? FileManager.default.removeItem(at: frontFixture.directory)
        }
        let library = try makeLibrary(rearFixture.directory)
        func staged(_ fixture: Fixture, role: SourceRole, start: RationalTime, audio: Bool) async throws -> StagedSource {
            let url = try await library.makeStagingFileURL(fileExtension: "mov")
            try FileManager.default.copyItem(at: fixture.url, to: url)
            return StagedSource(
                role: role, stagedFile: url, fileName: "\(role.rawValue).mov",
                metadata: SourceMetadata(
                    duration: .seconds(1), startOffset: start,
                    displayDimensions: try PixelDimensions(width: 1080, height: 1920), frameRate: .fps(30),
                    hasUsableAudio: audio, isMirrored: role == .frontCamera, ownsSharedAudio: audio))
        }
        var recipe = Recipe.initial(look: nil, creationStamp: try StampDate(year: 2026, month: 9, day: 27), seed: 3)
        var layout = DualCameraLayout()
        #expect(layout.recordSwap(at: try RationalTime(value: 1, timescale: 2)))
        recipe.dualLayout = layout
        let record = try await library.createProject(NewProjectDraft(
            createdAt: Date(), name: try ProjectName("Dual"), sourceMode: .dualCamera,
            sources: [
                try await staged(rearFixture, role: .rearCamera, start: .zero, audio: true),
                try await staged(frontFixture, role: .frontCamera, start: try RationalTime(value: 1, timescale: 10), audio: false),
            ],
            recipe: recipe))

        let plan = try ExportPlan.make(record: record, access: .notConfigured)
        let dual = try #require(plan.dual)
        #expect(dual.timing.duration == (try RationalTime(value: 9, timescale: 10)))
        var files: [SourceRole: URL] = [:]
        for source in plan.sources { files[source.role] = await library.fileURL(source.relativePath) }
        let output = try await library.makeJobFileURL(fileExtension: "mp4")
        let duration = try await AVExportRenderer(engine: RenderEngine()).render(
            plan: plan, sources: ExportSourceFiles(files), outputURL: output) { _ in }
        #expect(abs(duration.approximateSeconds - 0.9) < 0.1, "Common interval, not either file (got \(duration))")
        #expect(!(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)).isEmpty, "One shared audio track")

        let inset = DualInsetLayout(canvas: plan.policy.dimensions, corner: .topRight).frame
        let insetCentre = (x: inset.x + inset.width / 2, y: inset.y + inset.height / 2)
        let canvasCentre = (x: Double(plan.policy.dimensions.width) / 2, y: Double(plan.policy.dimensions.height) / 2)
        func isRed(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > c.g + 60 }
        func isGreen(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.g > c.r + 60 }
        let beforeMain = try await Self.meanColor(output, at: 0.2, centre: canvasCentre)
        let beforeInset = try await Self.meanColor(output, at: 0.2, centre: insetCentre)
        let afterMain = try await Self.meanColor(output, at: 0.75, centre: canvasCentre)
        let afterInset = try await Self.meanColor(output, at: 0.75, centre: insetCentre)
        #expect(isRed(beforeMain) && isGreen(beforeInset), "Rear main, front inset before the swap: \(beforeMain) \(beforeInset)")
        #expect(isGreen(afterMain) && isRed(afterInset), "Swap at 0.5 s replayed: \(afterMain) \(afterInset)")
    }
}
