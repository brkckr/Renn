import Foundation
import RENNDomain

/// Scripted importer for ViewModel tests.
public actor FakeVideoImporter: VideoImporting {
    public var result: Result<PreparedImport, MediaPreparationFailure>
    public private(set) var discarded: [URL] = []
    public private(set) var prepareCount = 0

    public init(result: Result<PreparedImport, MediaPreparationFailure>) {
        self.result = result
    }

    public func prepare(pickedFile: URL) async throws(MediaPreparationFailure) -> PreparedImport {
        prepareCount += 1
        return try result.get()
    }

    public func discard(_ prepared: PreparedImport) async {
        discarded.append(prepared.stagedFile)
    }

    public static func prepared(seconds: Int64, audio: Bool = true) -> PreparedImport {
        PreparedImport(
            stagedFile: URL(fileURLWithPath: "/staging/\(UUID().uuidString).mov"),
            fileExtension: "mov",
            profile: SourceMediaProfile(
                displayDimensions: try! PixelDimensions(width: 1080, height: 1920),
                frameRate: .fps(30), duration: .seconds(seconds), hasUsableAudio: audio),
            isHDR: false)
    }
}
