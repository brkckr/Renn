import AVFoundation
import CoreImage
import Foundation
import Testing
import RENNDomain
import RENNStorage
@testable import RENN

/// Media integration on the Simulator (07 test level 3): a synthesized fixture goes through the
/// real importer, project store, render engine, writer and validator, and the decoded output is
/// inspected. Simulator results do not replace device validation (camera, GPU speed, HDR).
@Suite("Media pipeline (Simulator integration)", .serialized, .timeLimit(.minutes(2)))
struct MediaPipelineTests {
    struct Fixture {
        let directory: URL
        let url: URL
    }

    /// 1080×1920, 60 FPS, H.264, with a 1 kHz mono AAC tone when `audio` is true.
    static func makeFixture(seconds: Double = 2, fps: Int32 = 60, audio: Bool = true) async throws -> Fixture {
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
        let context = CIContext()
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
                let shade = CGFloat(videoIndex % 60) / 60
                let image = CIImage(color: CIColor(red: shade, green: 0.4, blue: 1 - shade))
                    .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
                context.render(image, to: buffer!)
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
        #expect(abs(metadata.duration.approximateSeconds - 2) < 0.05)
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
        #expect(abs(duration.approximateSeconds - 2) < 0.1, "Duration within one or two frames")
        let frames = try await Self.frameCount(output)
        #expect(abs(frames - 60) <= 1, "60 FPS input becomes 30 FPS without retiming (got \(frames))")
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
        let fixture = try await Self.makeFixture(seconds: 1)
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
        #expect(abs(frames - 60) <= 1, "Pro keeps 60 FPS (got \(frames))")
    }

    @Test func renderIsDeterministicForTheSameRecipeAndTime() throws {
        let engine = RenderEngine()
        let source = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let recipe = Recipe.initial(
            look: LookDefinition(
                id: "dev.diagnostic", version: 1, family: "diagnostic", nameKey: "n", descriptionKey: "d",
                defaultIntensity: LookIntensity(1)!, renderVersion: 1, isDevelopmentFixture: true),
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
}
