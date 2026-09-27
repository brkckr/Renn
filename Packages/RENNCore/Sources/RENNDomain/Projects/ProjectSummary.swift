import Foundation

/// Immutable project snapshot passed across boundaries (never a SwiftData model).
/// M01 extends this with source, recipe revision and output references.
public struct ProjectSummary: Sendable, Hashable, Identifiable {
    public enum Readiness: String, Sendable, Codable {
        case preparing
        case ready
        case interrupted
        case sourceMissing
        case deleting
    }

    public enum SourceMode: String, Sendable, Codable {
        case camera
        case dualCamera
        case imported
    }

    public let id: ProjectID
    public var name: ProjectName
    public var createdAt: Date
    public var updatedAt: Date
    public var sourceMode: SourceMode
    public var readiness: Readiness
    public var lookID: LookID?

    public init(
        id: ProjectID,
        name: ProjectName,
        createdAt: Date,
        updatedAt: Date,
        sourceMode: SourceMode,
        readiness: Readiness,
        lookID: LookID?
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceMode = sourceMode
        self.readiness = readiness
        self.lookID = lookID
    }
}
