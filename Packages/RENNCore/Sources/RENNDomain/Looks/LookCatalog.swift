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
    /// Bundled `.cube` resource name (without extension), if the Look uses a LUT.
    public let lut: String?
    /// Effect strengths at intensity 1 (see `LookParameter`); intensity scales them linearly.
    public let parameters: [String: Double]

    public init(
        id: LookID,
        version: Int,
        family: String,
        nameKey: String,
        descriptionKey: String,
        defaultIntensity: LookIntensity,
        renderVersion: Int,
        isDevelopmentFixture: Bool,
        lut: String? = nil,
        parameters: [String: Double] = [:]
    ) {
        self.id = id
        self.version = version
        self.family = family
        self.nameKey = nameKey
        self.descriptionKey = descriptionKey
        self.defaultIntensity = defaultIntensity
        self.renderVersion = renderVersion
        self.isDevelopmentFixture = isDevelopmentFixture
        self.lut = lut
        self.parameters = parameters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(LookID.self, forKey: .id)
        version = try container.decode(Int.self, forKey: .version)
        family = try container.decode(String.self, forKey: .family)
        nameKey = try container.decode(String.self, forKey: .nameKey)
        descriptionKey = try container.decode(String.self, forKey: .descriptionKey)
        defaultIntensity = try container.decode(LookIntensity.self, forKey: .defaultIntensity)
        renderVersion = try container.decode(Int.self, forKey: .renderVersion)
        isDevelopmentFixture = try container.decode(Bool.self, forKey: .isDevelopmentFixture)
        lut = try container.decodeIfPresent(String.self, forKey: .lut)
        parameters = try container.decodeIfPresent([String: Double].self, forKey: .parameters) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, family, nameKey, descriptionKey, defaultIntensity, renderVersion, isDevelopmentFixture
        case lut, parameters
    }
}

/// Parameter keys understood by render version 1. Values are strengths at intensity 1.
public enum LookParameter {
    /// 0...1 blend of the LUT result over the graded image.
    public static let lutMix = "lutMix"
    /// Saturation change, e.g. -0.35 desaturates by 35%.
    public static let saturation = "saturation"
    /// Contrast change, e.g. 0.08.
    public static let contrast = "contrast"
    /// Warmth in kelvin of neutral shift (positive = warmer).
    public static let warmth = "warmth"
    /// Vignette strength 0...2.
    public static let vignette = "vignette"
    /// Grain overlay strength 0...0.3.
    public static let grain = "grain"
    /// Grain cell size in pixels at a 1080-pixel short edge, 0.5...4 (see `FilmGrain`).
    public static let grainSize = "grainSize"
    /// Share of independent per-channel (colour) grain, 0 = monochrome ... 1 = fully colour.
    public static let grainChroma = "grainChroma"

    /// Tape artefacts (`TapeArtifacts`), each 0...1: colour trailing to the right, horizontal
    /// softness, scanlines, sideways line wobble and a rolling tracking band.
    public static let chromaBleed = "chromaBleed"
    public static let tapeSoftness = "tapeSoftness"
    public static let scanlines = "scanlines"
    public static let lineJitter = "lineJitter"
    public static let tracking = "tracking"

    public static let all: Set<String> = [
        lutMix, saturation, contrast, warmth, vignette, grain, grainSize, grainChroma,
        chromaBleed, tapeSoftness, scanlines, lineJitter, tracking,
    ]
    /// Shape parameters describe how an effect looks, not how strong it is: intensity does not scale
    /// them (`Recipe.shapeParameter`).
    public static let unscaled: Set<String> = [grainSize, grainChroma]
    /// Per-key limits so a malformed manifest cannot produce unbounded effects.
    public static let limits: [String: ClosedRange<Double>] = [
        lutMix: 0...1, saturation: -1...1, contrast: -0.5...0.5, warmth: -4000...4000, vignette: 0...2, grain: 0...0.3,
        grainSize: 0.5...4, grainChroma: 0...1,
        chromaBleed: 0...1, tapeSoftness: 0...1, scanlines: 0...1, lineJitter: 0...1, tracking: 0...1,
    ]
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
        case invalidParameter(LookID, String)
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
            for (key, value) in look.parameters {
                guard let range = LookParameter.limits[key], value.isFinite, range.contains(value) else {
                    throw .invalidParameter(look.id, key)
                }
            }
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
