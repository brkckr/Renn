/// In-app language choice (02 D09, extended by the owner on 2026-09-30 from English and Turkish
/// to thirteen languages). System follows the device language with English fallback.
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
    case thai
    case vietnamese
    case indonesian

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
        case .thai: "th"
        case .vietnamese: "vi"
        case .indonesian: "id"
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
        case .thai: "ไทย"
        case .vietnamese: "Tiếng Việt"
        case .indonesian: "Bahasa Indonesia"
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

/// Screens with a one-time coach-mark tour (owner-approved 2026-09-30). Settings has none.
public enum CoachTour: String, Sendable, Codable, CaseIterable {
    case home
    case looks
    case projects
    case preview
}

/// Small app-wide preferences. Never used for purchase unlocks (06 C03).
public struct AppPreferences: Sendable, Equatable, Codable {
    public var hasCompletedOnboarding: Bool
    public var language: AppLanguage
    public var diagnosticsConsent: DiagnosticsConsent
    /// Tours finished once; they never show again unless the user asks in Settings.
    public var seenCoachTours: Set<CoachTour>
    /// Skip on any tour turns every remaining tour off.
    public var coachMarksSkipped: Bool

    public init(
        hasCompletedOnboarding: Bool = false,
        language: AppLanguage = .system,
        diagnosticsConsent: DiagnosticsConsent = .notAsked,
        seenCoachTours: Set<CoachTour> = [],
        coachMarksSkipped: Bool = false
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.language = language
        self.diagnosticsConsent = diagnosticsConsent
        self.seenCoachTours = seenCoachTours
        self.coachMarksSkipped = coachMarksSkipped
    }

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding, language, diagnosticsConsent, seenCoachTours, coachMarksSkipped
    }

    /// Preferences saved before coach marks existed decode with none seen; unknown tour names
    /// (from a newer version) are ignored instead of failing the whole record.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
        language = try container.decode(AppLanguage.self, forKey: .language)
        diagnosticsConsent = try container.decode(DiagnosticsConsent.self, forKey: .diagnosticsConsent)
        let tours = try container.decodeIfPresent([String].self, forKey: .seenCoachTours) ?? []
        seenCoachTours = Set(tours.compactMap(CoachTour.init(rawValue:)))
        coachMarksSkipped = try container.decodeIfPresent(Bool.self, forKey: .coachMarksSkipped) ?? false
    }
}
