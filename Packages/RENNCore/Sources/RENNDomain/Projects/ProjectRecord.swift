import Foundation

/// Media facts about one stored source that playback, policy and rendering need.
/// M02 extends this with color and transform details (new optional fields decode as nil).
public struct SourceMetadata: Sendable, Equatable, Codable {
    public var duration: RationalTime
    /// Offset of this source relative to the project's common timebase (Dual-Cam alignment).
    public var startOffset: RationalTime
    public var displayDimensions: PixelDimensions
    public var frameRate: FrameRate
    public var hasUsableAudio: Bool
    public var isMirrored: Bool
    /// Exactly one source owns the shared microphone track in Dual-Cam (05 V03).
    public var ownsSharedAudio: Bool

    public init(
        duration: RationalTime,
        startOffset: RationalTime = .zero,
        displayDimensions: PixelDimensions,
        frameRate: FrameRate,
        hasUsableAudio: Bool,
        isMirrored: Bool = false,
        ownsSharedAudio: Bool
    ) {
        self.duration = duration
        self.startOffset = startOffset
        self.displayDimensions = displayDimensions
        self.frameRate = frameRate
        self.hasUsableAudio = hasUsableAudio
        self.isMirrored = isMirrored
        self.ownsSharedAudio = ownsSharedAudio
    }
}

public enum SourceRole: String, Sendable, Codable, CaseIterable {
    /// Single-camera recording or imported video.
    case primary
    case rearCamera
    case frontCamera
}

/// A source file owned by a project.
public struct SourceReference: Sendable, Equatable, Codable {
    public var role: SourceRole
    public var relativePath: OwnedRelativePath
    public var fingerprint: FileFingerprint
    public var metadata: SourceMetadata

    public init(role: SourceRole, relativePath: OwnedRelativePath, fingerprint: FileFingerprint, metadata: SourceMetadata) {
        self.role = role
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.metadata = metadata
    }
}

/// Complete project metadata as stored by the metadata authority (SwiftData in the app).
/// Immutable snapshot; never a SwiftData model (04 A05).
public struct ProjectRecord: Sendable, Equatable, Codable, Identifiable {
    public static let currentSchemaVersion = 1

    public let id: ProjectID
    public var schemaVersion: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var name: ProjectName
    public var sourceMode: ProjectSummary.SourceMode
    public var readiness: ProjectSummary.Readiness
    public var sources: [SourceReference]
    /// Increments on every committed recipe change; export jobs snapshot a revision.
    public var recipeRevision: Int
    public var recipe: Recipe
    public var lastOutputID: OutputID?

    public init(
        id: ProjectID,
        schemaVersion: Int = ProjectRecord.currentSchemaVersion,
        createdAt: Date,
        updatedAt: Date,
        name: ProjectName,
        sourceMode: ProjectSummary.SourceMode,
        readiness: ProjectSummary.Readiness,
        sources: [SourceReference],
        recipeRevision: Int,
        recipe: Recipe,
        lastOutputID: OutputID? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.sourceMode = sourceMode
        self.readiness = readiness
        self.sources = sources
        self.recipeRevision = recipeRevision
        self.recipe = recipe
        self.lastOutputID = lastOutputID
    }

    public var summary: ProjectSummary {
        ProjectSummary(
            id: id, name: name, createdAt: createdAt, updatedAt: updatedAt,
            sourceMode: sourceMode, readiness: readiness, lookID: recipe.lookID)
    }

    /// Visible in project lists: everything except projects being deleted.
    public var isListed: Bool { readiness != .deleting }
}

/// A source file already copied into app-owned staging, ready to be adopted by a project.
public struct StagedSource: Sendable {
    public var role: SourceRole
    /// Temporary file on the same volume as the project store; moved, never copied, on commit.
    public var stagedFile: URL
    /// File name inside the project's `sources/` directory.
    public var fileName: String
    public var metadata: SourceMetadata

    public init(role: SourceRole, stagedFile: URL, fileName: String, metadata: SourceMetadata) {
        self.role = role
        self.stagedFile = stagedFile
        self.fileName = fileName
        self.metadata = metadata
    }
}

/// Everything needed to create a project in one commit (05 V08).
public struct NewProjectDraft: Sendable {
    public var id: ProjectID
    public var createdAt: Date
    public var name: ProjectName
    public var sourceMode: ProjectSummary.SourceMode
    public var sources: [StagedSource]
    public var recipe: Recipe

    public init(
        id: ProjectID = ProjectID(),
        createdAt: Date,
        name: ProjectName,
        sourceMode: ProjectSummary.SourceMode,
        sources: [StagedSource],
        recipe: Recipe
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.sourceMode = sourceMode
        self.sources = sources
        self.recipe = recipe
    }
}
