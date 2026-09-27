/// A path relative to the app's controlled storage root (05 V07). Only this type is
/// persisted; absolute paths and picker URLs never are. Traversal is rejected on creation
/// and on decode.
public struct OwnedRelativePath: Sendable, Hashable, Codable, CustomStringConvertible {
    public let components: [String]

    public enum ValidationError: Error, Equatable, Sendable {
        case empty
        case invalidComponent(String)
    }

    public init(_ components: [String]) throws(ValidationError) {
        guard !components.isEmpty else { throw .empty }
        for component in components where !OwnedRelativePath.isValid(component) {
            throw .invalidComponent(component)
        }
        self.components = components
    }

    public init(string: String) throws(ValidationError) {
        try self.init(string.split(separator: "/", omittingEmptySubsequences: false).map(String.init))
    }

    public var string: String { components.joined(separator: "/") }
    public var description: String { string }

    /// Letters, digits, dot, dash and underscore; never empty, "." or "..", max 128 chars.
    static func isValid(_ component: String) -> Bool {
        guard !component.isEmpty, component.count <= 128, component != ".", component != ".." else { return false }
        return component.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": true
            default: false
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(string: try container.decode(String.self))
        } catch is ValidationError {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid owned relative path")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// App-owned storage layout (05 V07): `Projects/<UUID>/sources/`, `Projects/<UUID>/outputs/`.
public enum ProjectFileLayout {
    public static let projectsDirectory = "Projects"

    public enum Area: String, Sendable, CaseIterable {
        case sources
        case outputs
    }

    public static func projectDirectory(_ id: ProjectID) -> OwnedRelativePath {
        try! OwnedRelativePath([projectsDirectory, id.rawValue.uuidString])
    }

    public static func file(_ fileName: String, in area: Area, of id: ProjectID) throws(OwnedRelativePath.ValidationError) -> OwnedRelativePath {
        try OwnedRelativePath([projectsDirectory, id.rawValue.uuidString, area.rawValue, fileName])
    }

    /// The project a path belongs to, if it is inside a project directory.
    public static func projectID(of path: OwnedRelativePath) -> ProjectID? {
        guard path.components.count >= 2, path.components[0] == projectsDirectory else { return nil }
        return UUIDParsing.uuid(path.components[1]).map(ProjectID.init)
    }
}

/// Change-detection fingerprint of an owned file: byte size plus a hash of sampled chunks.
/// Not a security hash; detects replaced, truncated or missing sources (05 V07).
public struct FileFingerprint: Sendable, Hashable, Codable {
    public let byteCount: Int64
    public let sampleHash: UInt64

    public init(byteCount: Int64, sampleHash: UInt64) {
        self.byteCount = byteCount
        self.sampleHash = sampleHash
    }
}
