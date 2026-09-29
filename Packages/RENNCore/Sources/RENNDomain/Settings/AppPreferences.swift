/// In-app language choice (02 D09, extended by the owner on 2026-09-30 from English and Turkish
/// to ten languages). System follows the device language with English fallback.
public enum AppLanguage: String, Sendable, Codable, CaseIterable {
    case system
    case english
    case turkish
    case spanish
    case portugueseBrazil
    case german
    case french
    case japanese
    case korean
    case chineseSimplified
    case russian

    /// Localization identifier for an explicit choice; nil means follow the system.
    public var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .turkish: "tr"
        case .spanish: "es"
        case .portugueseBrazil: "pt-BR"
        case .german: "de"
        case .french: "fr"
        case .japanese: "ja"
        case .korean: "ko"
        case .chineseSimplified: "zh-Hans"
        case .russian: "ru"
        }
    }

    /// The language's own name, shown in the picker in every app language; nil for System.
    public var nativeName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .turkish: "Türkçe"
        case .spanish: "Español"
        case .portugueseBrazil: "Português (Brasil)"
        case .german: "Deutsch"
        case .french: "Français"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .chineseSimplified: "简体中文"
        case .russian: "Русский"
        }
    }

    public static let supportedLocalizations = allCases.compactMap(\.localizationIdentifier)
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
