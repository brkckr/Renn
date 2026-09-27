import Foundation

/// Photos save state of one output (05 V09). Saving is separate from rendering success.
public enum PhotosSaveState: String, Sendable, Codable, Equatable {
    case notAttempted
    case inFlight
    case saved
    case failed
    case permissionDenied
    /// The process ended after submission but before confirmation. Never auto-resubmitted;
    /// an explicit retry explains the duplicate risk.
    case uncertain
}

/// A validated local export result owned by a project (05 V07).
public struct OutputRecord: Sendable, Equatable, Codable, Identifiable {
    public let id: OutputID
    public var relativePath: OwnedRelativePath
    public var fingerprint: FileFingerprint
    /// Recipe revision the output was rendered from.
    public var recipeRevision: Int
    public var policy: OutputPolicy
    public var duration: RationalTime
    public var hasAudio: Bool
    public var completedAt: Date
    public var photosSave: PhotosSaveState
    /// PhotoKit local identifier when the save is confirmed.
    public var photosLocalIdentifier: String?

    public init(
        id: OutputID,
        relativePath: OwnedRelativePath,
        fingerprint: FileFingerprint,
        recipeRevision: Int,
        policy: OutputPolicy,
        duration: RationalTime,
        hasAudio: Bool,
        completedAt: Date,
        photosSave: PhotosSaveState = .notAttempted,
        photosLocalIdentifier: String? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.recipeRevision = recipeRevision
        self.policy = policy
        self.duration = duration
        self.hasAudio = hasAudio
        self.completedAt = completedAt
        self.photosSave = photosSave
        self.photosLocalIdentifier = photosLocalIdentifier
    }

    /// A saved output is never submitted again; uncertain requires an explicit retry.
    public var allowsAutomaticSave: Bool { photosSave == .notAttempted }
}

/// A validated output file waiting in the job area to be committed to its project.
public struct FinishedOutput: Sendable {
    public var file: URL
    public var fileName: String
    public var recipeRevision: Int
    public var policy: OutputPolicy
    public var duration: RationalTime
    public var hasAudio: Bool

    public init(file: URL, fileName: String, recipeRevision: Int, policy: OutputPolicy, duration: RationalTime, hasAudio: Bool) {
        self.file = file
        self.fileName = fileName
        self.recipeRevision = recipeRevision
        self.policy = policy
        self.duration = duration
        self.hasAudio = hasAudio
    }
}
