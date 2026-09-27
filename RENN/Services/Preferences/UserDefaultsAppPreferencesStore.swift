import Foundation
import RENNDomain

/// Stores onboarding completion, language choice and diagnostics consent. It never
/// stores purchase or unlock state (06 C03).
@MainActor
final class UserDefaultsAppPreferencesStore: AppPreferencesStoring {
    private static let key = "renn.appPreferences.v1"
    private static let appleLanguagesKey = "AppleLanguages"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else { return AppPreferences() }
        return preferences
    }

    func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
        // Mirror an explicit language into the per-app preferred languages, so system-owned
        // strings (permission prompts from InfoPlist.xcstrings) follow it after relaunch.
        if let identifier = preferences.language.localizationIdentifier {
            defaults.set([identifier], forKey: Self.appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        }
    }
}
