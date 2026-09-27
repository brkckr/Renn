/// In-app language choice (02 D09). System follows device language with English fallback.
public enum AppLanguage: String, Sendable, Codable, CaseIterable {
    case system
    case english
    case turkish

    /// Localization identifier for an explicit choice; nil means follow the system.
    public var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .turkish: "tr"
        }
    }

    public static let supportedLocalizations = ["en", "tr"]
    public static let fallbackLocalization = "en"
}

/// Optional diagnostics consent (06 C05). Collection is off until explicitly granted.
public enum DiagnosticsConsent: String, Sendable, Codable {
    case notAsked
    case granted
    case declined

    public var allowsCollection: Bool { self == .granted }
}

/// Small app-wide preferences. Never used for purchase unlocks (06 C03).
public struct AppPreferences: Sendable, Equatable, Codable {
    public var hasCompletedOnboarding: Bool
    public var language: AppLanguage
    public var diagnosticsConsent: DiagnosticsConsent

    public init(
        hasCompletedOnboarding: Bool = false,
        language: AppLanguage = .system,
        diagnosticsConsent: DiagnosticsConsent = .notAsked
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.language = language
        self.diagnosticsConsent = diagnosticsConsent
    }
}
