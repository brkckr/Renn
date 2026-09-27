import AVFoundation
import CoreMedia
import RENNDomain

/// Reads the facts output policy and rendering need from a local video file (05 V01/V06).
/// Aspect is measured after the preferred transform; cadence uses the minimum frame duration
/// (actual timestamps) rather than `nominalFrameRate` alone.
enum AVMediaInspector {
    struct Inspection: Sendable {
        var profile: SourceMediaProfile
        var isHDR: Bool
    }

    static func inspect(_ url: URL) async throws(MediaPreparationFailure) -> Inspection {
        let asset = AVURLAsset(url: url)
        do {
            let (duration, isPlayable) = try await asset.load(.duration, .isPlayable)
            guard isPlayable else { throw MediaPreparationFailure.unsupportedFormat }
            guard let video = try await asset.loadTracks(withMediaType: .video).first else {
                throw MediaPreparationFailure.noVideoTrack
            }
            let (naturalSize, transform) = try await video.load(.naturalSize, .preferredTransform)
            let (nominalRate, minFrameDuration, formats) = try await video.load(
                .nominalFrameRate, .minFrameDuration, .formatDescriptions)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            let displayRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let dimensions = try PixelDimensions(
                width: Int(abs(displayRect.width).rounded()),
                height: Int(abs(displayRect.height).rounded()))
            guard duration.isNumeric, duration.timescale > 0, duration.value > 0 else {
                throw MediaPreparationFailure.unreadable
            }
            return Inspection(
                profile: SourceMediaProfile(
                    displayDimensions: dimensions,
                    frameRate: frameRate(minFrameDuration: minFrameDuration, nominal: nominalRate),
                    duration: try RationalTime(value: duration.value, timescale: duration.timescale),
                    hasUsableAudio: !audioTracks.isEmpty),
                isHDR: formats.contains(where: isHDR))
        } catch let failure as MediaPreparationFailure {
            throw failure
        } catch {
            throw .unreadable
        }
    }

    /// Rational cadence ceiling. 1001/30000 s → 30000/1001 (29.97).
    static func frameRate(minFrameDuration: CMTime, nominal: Float) -> FrameRate {
        if minFrameDuration.isNumeric, minFrameDuration.value > 0, minFrameDuration.timescale > 0,
           minFrameDuration.value <= Int64(Int32.max),
           let rate = try? FrameRate(frames: minFrameDuration.timescale, perSeconds: Int32(minFrameDuration.value)),
           rate.approximateFPS <= 480 {
            return rate
        }
        let known: [FrameRate] = [.ntsc23_976, .fps(24), .fps(25), .ntsc29_97, .fps(30), .fps(50), .ntsc59_94, .fps(60)]
        if let match = known.first(where: { abs($0.approximateFPS - Double(nominal)) < 0.01 }) {
            return match
        }
        return .fps(Int32(max(1, Double(nominal).rounded())))
    }

    private static func isHDR(_ format: CMFormatDescription) -> Bool {
        guard let transfer = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        else { return false }
        return transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
            || transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
    }
}

/// `VideoImporting` over the project store's staging area (05 V06): moves the picker's copy
/// into this launch's staging directory, then inspects it.
struct AVVideoImporter: VideoImporting {
    let projects: any ProjectStoring

    func prepare(pickedFile: URL) async throws(MediaPreparationFailure) -> PreparedImport {
        let fileExtension = Self.normalizedExtension(pickedFile.pathExtension)
        let staged: URL
        do {
            staged = try await projects.makeStagingFileURL(fileExtension: fileExtension)
        } catch {
            throw .insufficientStorage
        }
        do {
            try FileManager.default.moveItem(at: pickedFile, to: staged)
        } catch {
            throw Self.isOutOfSpace(error) ? .insufficientStorage : .unreadable
        }
        do {
            let inspection = try await AVMediaInspector.inspect(staged)
            return PreparedImport(
                stagedFile: staged, fileExtension: fileExtension, profile: inspection.profile, isHDR: inspection.isHDR)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    func discard(_ prepared: PreparedImport) async {
        try? FileManager.default.removeItem(at: prepared.stagedFile)
    }

    static func normalizedExtension(_ raw: String) -> String {
        let lowered = raw.lowercased()
        return ["mov", "mp4", "m4v"].contains(lowered) ? lowered : "mov"
    }

    private static func isOutOfSpace(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC))
    }
}
