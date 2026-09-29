import Foundation
import Observation
import RENNDomain

/// Applies the language choice (System or one of `AppLanguage`'s ten languages) to app-owned
/// strings (02 D09, 06 C07).
/// SwiftUI `Text` resolves catalog keys through the `locale` environment value set at the
/// root; `string(_:)` covers the few places that need a plain `String`.
/// The choice never affects Store currency: prices always come from the Store.
@MainActor
@Observable
final class LocalizationController {
    private(set) var language: AppLanguage
    private(set) var locale: Locale
    private(set) var bundle: Bundle

    private let mainBundle: Bundle

    init(language: AppLanguage, mainBundle: Bundle = .main) {
        self.mainBundle = mainBundle
        self.language = language
        let resolved = Self.resolve(language, mainBundle: mainBundle)
        self.locale = resolved.locale
        self.bundle = resolved.bundle
    }

    func apply(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        let resolved = Self.resolve(newLanguage, mainBundle: mainBundle)
        locale = resolved.locale
        bundle = resolved.bundle
    }

    func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// The effective localization in use, e.g. "en", "tr" or "zh-Hans".
    var effectiveLocalization: String {
        Self.localizationIdentifier(for: language, mainBundle: mainBundle)
    }

    private static func resolve(_ language: AppLanguage, mainBundle: Bundle) -> (locale: Locale, bundle: Bundle) {
        let identifier = localizationIdentifier(for: language, mainBundle: mainBundle)
        let bundle = mainBundle.path(forResource: identifier, ofType: "lproj").flatMap(Bundle.init(path:)) ?? mainBundle
        let locale: Locale
        if language == .system {
            // Keep regional formatting from the device while following its language.
            locale = Locale.autoupdatingCurrent
        } else {
            locale = Locale(identifier: identifier)
        }
        return (locale, bundle)
    }

    private static func localizationIdentifier(for language: AppLanguage, mainBundle: Bundle) -> String {
        if let explicit = language.localizationIdentifier { return explicit }
        // System: first supported device language, English fallback.
        let preferred = Bundle.preferredLocalizations(
            from: AppLanguage.supportedLocalizations, forPreferences: Locale.preferredLanguages)
        return preferred.first ?? AppLanguage.fallbackLocalization
    }
}
