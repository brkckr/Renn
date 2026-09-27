/// One catalog Look definition. All Looks are free; there is deliberately no tier field (05 V04).
/// M03/M08 extend this with LUT/shader/grain references and the versioned parameter mapping.
public struct LookDefinition: Sendable, Hashable, Codable, Identifiable {
    public let id: LookID
    public let version: Int
    /// Actual family identifier; chips show only nonempty families.
    public let family: String
    /// String-catalog keys, so names/descriptions are localized in English and Turkish.
    public let nameKey: String
    public let descriptionKey: String
    public let defaultIntensity: LookIntensity
    public let renderVersion: Int
    /// True for development fixtures that must never be presented as final approved Looks.
    public let isDevelopmentFixture: Bool

    public init(
        id: LookID,
        version: Int,
        family: String,
        nameKey: String,
        descriptionKey: String,
        defaultIntensity: LookIntensity,
        renderVersion: Int,
        isDevelopmentFixture: Bool
    ) {
        self.id = id
        self.version = version
        self.family = family
        self.nameKey = nameKey
        self.descriptionKey = descriptionKey
        self.defaultIntensity = defaultIntensity
        self.renderVersion = renderVersion
        self.isDevelopmentFixture = isDevelopmentFixture
    }
}

/// Validated catalog manifest (08 I01). Decoded from the bundled JSON manifest.
public struct LookCatalog: Sendable, Equatable, Codable {
    /// The settled launch scope: twelve Looks, all free (01 P04).
    public static let requiredLaunchLookCount = 12
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let catalogVersion: String
    public let isDevelopmentFixture: Bool
    public let recommendedLookID: LookID?
    public let looks: [LookDefinition]

    public enum ValidationError: Error, Equatable, Sendable {
        case unsupportedSchemaVersion(Int)
        case duplicateLookID(LookID)
        case emptyIdentifier
        case invalidVersion(LookID)
        case unknownRecommendedLook(LookID)
    }

    public init(
        schemaVersion: Int = LookCatalog.supportedSchemaVersion,
        catalogVersion: String,
        isDevelopmentFixture: Bool,
        recommendedLookID: LookID?,
        looks: [LookDefinition]
    ) throws(ValidationError) {
        self.schemaVersion = schemaVersion
        self.catalogVersion = catalogVersion
        self.isDevelopmentFixture = isDevelopmentFixture
        self.recommendedLookID = recommendedLookID
        self.looks = looks
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        catalogVersion = try container.decode(String.self, forKey: .catalogVersion)
        isDevelopmentFixture = try container.decode(Bool.self, forKey: .isDevelopmentFixture)
        recommendedLookID = try container.decodeIfPresent(LookID.self, forKey: .recommendedLookID)
        looks = try container.decode([LookDefinition].self, forKey: .looks)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, catalogVersion, isDevelopmentFixture, recommendedLookID, looks
    }

    private func validate() throws(ValidationError) {
        guard schemaVersion == LookCatalog.supportedSchemaVersion else {
            throw .unsupportedSchemaVersion(schemaVersion)
        }
        var seen = Set<LookID>()
        for look in looks {
            guard !look.id.rawValue.isEmpty else { throw .emptyIdentifier }
            guard look.version > 0, look.renderVersion > 0 else { throw .invalidVersion(look.id) }
            guard seen.insert(look.id).inserted else { throw .duplicateLookID(look.id) }
        }
        if let recommendedLookID, !seen.contains(recommendedLookID) {
            throw .unknownRecommendedLook(recommendedLookID)
        }
    }

    public func look(_ id: LookID) -> LookDefinition? {
        looks.first { $0.id == id }
    }

    public var recommendedLook: LookDefinition? {
        recommendedLookID.flatMap(look) ?? looks.first
    }

    /// Only real, nonempty families, in catalog order.
    public var families: [String] {
        var result: [String] = []
        for look in looks where !result.contains(look.family) {
            result.append(look.family)
        }
        return result
    }

    /// True only for the reviewed twelve-Look production catalog. A development catalog
    /// can never satisfy this, which keeps the launch scope visible (07 M08).
    public var isLaunchReady: Bool {
        !isDevelopmentFixture
            && looks.count == LookCatalog.requiredLaunchLookCount
            && !looks.contains { $0.isDevelopmentFixture }
    }
}
