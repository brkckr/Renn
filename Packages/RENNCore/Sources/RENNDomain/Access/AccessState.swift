import Foundation

/// Effective commercial tier used by output policy. Creative tools never depend on it (01 P08).
public enum AccessTier: String, Sendable, Codable, CaseIterable {
    case free
    case pro
}

/// Single access-state source derived from the purchase service (04 A05, 06 C03).
/// ViewModels observe this; nothing stores an independent `isPro` copy.
public struct AccessState: Sendable, Equatable {
    public enum Level: String, Sendable, Codable {
        /// Customer information has not been loaded, or the provider is not configured.
        case unknown
        case free
        case pro
    }

    /// Where the level came from, so UI and diagnostics can be truthful about it.
    public enum Provenance: String, Sendable, Codable {
        /// No purchase provider is configured in this build (placeholder configuration).
        case providerNotConfigured
        /// The provider has not answered yet.
        case notLoaded
        /// Provider SDK cached customer information.
        case providerCache
        /// Provider answered during this session.
        case providerVerified
        /// Development fake; never used by production composition.
        case developmentFake
    }

    public var level: Level
    public var provenance: Provenance
    public var checkedAt: Date?

    public init(level: Level, provenance: Provenance, checkedAt: Date? = nil) {
        self.level = level
        self.provenance = provenance
        self.checkedAt = checkedAt
    }

    /// Unknown access runs the valid Free policy (05 V09).
    public var effectiveTier: AccessTier { level == .pro ? .pro : .free }

    public static let notConfigured = AccessState(level: .unknown, provenance: .providerNotConfigured)
    public static let notLoaded = AccessState(level: .unknown, provenance: .notLoaded)
}
