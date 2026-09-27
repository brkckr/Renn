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
