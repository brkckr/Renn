import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation
import RENNDomain

/// Firebase Analytics + Crashlytics (06 C05), configured only when the owner's
/// GoogleService-Info.plist is bundled. Collection is off by Info.plist default and follows the
/// Settings diagnostics consent: nothing (automatic events or crash reports) is collected before
/// the user opts in, and declining never changes features. The app links FirebaseAnalyticsCore
/// (GoogleAppMeasurementCore): no advertising identifier and no ads conversion SDK.
enum FirebaseDiagnostics {
    /// Configures Firebase and applies the stored consent. Returns false when not configured.
    @MainActor
    static func configureIfAvailable(consent: DiagnosticsConsent) -> Bool {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return false }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        apply(consent)
        return true
    }

    /// Turns SDK collection on or off to match the user's choice.
    @MainActor
    static func apply(_ consent: DiagnosticsConsent) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.setAnalyticsCollectionEnabled(consent.allowsCollection)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(consent.allowsCollection)
    }
}

/// Sends allowlisted, consent-gated events (the gate sits in front, `ConsentGatedTelemetry`).
/// Parameters are already flat, low-cardinality strings; nothing is added here.
struct FirebaseAnalyticsSink: TelemetrySink {
    func send(name: String, parameters: [String: String]) async {
        Analytics.logEvent(name, parameters: parameters.isEmpty ? nil : parameters)
    }
}
