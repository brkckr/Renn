import Foundation
import Testing
import RENNDomain
@testable import RENN

/// App-target checks that need the real bundle and build settings (07 P01/A01/C01/C07).
/// Pure rules and ViewModels are tested in Packages/RENNCore.
@MainActor
@Suite("App bundle and configuration")
struct AppBundleTests {
    @Test func bundleIdentityMatchesContract() {
        #expect(Bundle.main.bundleIdentifier == AppIdentity.bundleIdentifier)
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        #expect(displayName == AppIdentity.displayName)
    }

    @Test func englishAndTurkishLocalizationsAreBundled() {
        let localizations = Set(Bundle.main.localizations)
        #expect(localizations.isSuperset(of: ["en", "tr"]))
    }

    @Test func usageDescriptionsArePresent() {
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription"] {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
            #expect(value?.isEmpty == false, "\(key) missing")
        }
    }

    @Test func privacyManifestDeclaresNoTrackingAndRequiredReasons() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        let categories = (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(Set(categories) == ["NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryDiskSpace"])
    }

    @Test func firebaseCollectionIsOffUntilConsent() {
        for key in ["FIREBASE_ANALYTICS_COLLECTION_ENABLED", "FirebaseCrashlyticsCollectionEnabled",
                    "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS"] {
            #expect(Bundle.main.object(forInfoDictionaryKey: key) as? Bool == false, "\(key) must default to off")
        }
    }

    @Test func brandFontsAreBundledWithTheirLicenses() throws {
        FontRegistry.registerBundledFonts()
        for face in FontRegistry.report() {
            #expect(face.isAvailable, "\(face.postScriptName) must load (no silent system fallback)")
        }
        let url = try #require(Bundle.main.url(forResource: "FontLicenses", withExtension: "txt"))
        let notices = try String(contentsOf: url, encoding: .utf8)
        for required in ["Monoton", "Press Start 2P", "Roboto", "SIL OPEN FONT LICENSE Version 1.1"] {
            #expect(notices.contains(required))
        }
    }

    @Test func unconfiguredProvidersAreReportedAsPlaceholders() {
        let configuration = AppConfiguration.load()
        // No owner configuration is committed to the repository.
        #expect(configuration.revenueCatAPIKey == nil)
        #expect(!configuration.missingConfiguration.isEmpty)
    }

    @Test func bundledDevelopmentCatalogLoads() async throws {
        let catalog = try await BundledLookCatalogProvider().catalog()
        #expect(catalog.isDevelopmentFixture)
        #expect(!catalog.isLaunchReady)
        #expect(catalog.recommendedLook != nil)
    }

    @Test func languageChoiceSelectsLocalizedBundle() {
        let controller = LocalizationController(language: .turkish)
        #expect(controller.effectiveLocalization == "tr")
        #expect(controller.string("tab.home") == "Ana Sayfa")
        controller.apply(.english)
        #expect(controller.string("tab.home") == "Home")
    }

    @Test func unconfiguredPurchasesNeverGrantPro() async {
        let service = UnconfiguredPurchaseService()
        #expect(await service.currentAccess().effectiveTier == .free)
        #expect(await service.purchase(productID: "anything") == .failed(.notConfigured))
        #expect(await service.restore() == .failed(.notConfigured))
    }
}
