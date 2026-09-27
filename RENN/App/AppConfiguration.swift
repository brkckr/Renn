import Foundation

/// Build-time configuration read from Info.plist values that the xcconfig files inject
/// (Config/*.xcconfig). Missing provider values are reported as placeholders; the app
/// never invents credentials, products or account setup.
struct AppConfiguration: Sendable {
    enum Environment: String, Sendable {
        case development
        case production
    }

    let environment: Environment
    /// RevenueCat public SDK key. Nil until the owner provides it (08 I04).
    let revenueCatAPIKey: String?
    /// Firebase is configured by GoogleService-Info.plist in M06. Detected, not assumed.
    let hasFirebaseConfiguration: Bool
    let supportURL: URL?
    let privacyURL: URL?
    let termsURL: URL?
    /// DEBUG-only opt-in to the fake purchase service for UI work (`-RENNUseFakePurchases YES`).
    let usesFakePurchases: Bool
    let marketingVersion: String
    let buildNumber: String

    static func load(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> AppConfiguration {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Unresolved build settings and empty strings are placeholders, not values.
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
            return trimmed
        }

        func url(_ key: String) -> URL? {
            value(key).flatMap(URL.init(string:))
        }

        #if DEBUG
        let fakePurchases = UserDefaults.standard.bool(forKey: "RENNUseFakePurchases")
            || arguments.contains("-RENNUseFakePurchases")
        #else
        let fakePurchases = false
        #endif

        return AppConfiguration(
            environment: value("RENNEnvironment").flatMap(Environment.init(rawValue:)) ?? .development,
            revenueCatAPIKey: value("RENNRevenueCatAPIKey"),
            hasFirebaseConfiguration: bundle.url(forResource: "GoogleService-Info", withExtension: "plist") != nil,
            supportURL: url("RENNSupportURL"),
            privacyURL: url("RENNPrivacyURL"),
            termsURL: url("RENNTermsURL"),
            usesFakePurchases: fakePurchases,
            marketingVersion: value("CFBundleShortVersionString") ?? "0",
            buildNumber: value("CFBundleVersion") ?? "0")
    }

    /// Human-readable list of configuration placeholders for the developer section.
    var missingConfiguration: [String] {
        var missing: [String] = []
        if revenueCatAPIKey == nil { missing.append("RevenueCat API key (RENN_REVENUECAT_API_KEY)") }
        if !hasFirebaseConfiguration { missing.append("Firebase GoogleService-Info.plist") }
        if supportURL == nil { missing.append("Support URL (RENN_SUPPORT_URL)") }
        if privacyURL == nil { missing.append("Privacy URL (RENN_PRIVACY_URL)") }
        if termsURL == nil { missing.append("Terms URL (RENN_TERMS_URL)") }
        return missing
    }
}
