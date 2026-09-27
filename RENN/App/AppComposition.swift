import Foundation
import RENNDomain
import RENNFakes
import RENNFeatures

/// The single composition root (04 A03). It constructs app-lifetime services once and
/// hands each ViewModel only the dependencies it needs. No feature code reaches back
/// into this object, and no service is exposed through a global or `.shared` accessor.
@MainActor
final class AppComposition {
    let configuration: AppConfiguration
    let router: AppRouter
    let localization: LocalizationController

    private let preferencesStore: any AppPreferencesStoring
    private let purchases: any Purchasing
    private let telemetry: any TelemetryRecording
    private let projectStore: any ProjectStoring
    private let lookCatalog: any LookCatalogProviding
    private let lookPreferencesStore: any LookPreferencesStoring

    init(
        configuration: AppConfiguration,
        preferencesStore: any AppPreferencesStoring,
        purchases: any Purchasing,
        telemetrySink: any TelemetrySink,
        projectStore: any ProjectStoring,
        lookCatalog: any LookCatalogProviding,
        lookPreferencesStore: any LookPreferencesStoring,
        captureCapabilities: any CaptureCapabilityProviding
    ) {
        self.configuration = configuration
        self.preferencesStore = preferencesStore
        self.purchases = purchases
        self.projectStore = projectStore
        self.lookCatalog = lookCatalog
        self.lookPreferencesStore = lookPreferencesStore
        router = AppRouter(captureCapabilities: captureCapabilities)
        localization = LocalizationController(language: preferencesStore.load().language)
        // Consent is read at send time, so turning diagnostics off stops the next event.
        telemetry = ConsentGatedTelemetry(
            isCollectionAllowed: { [preferencesStore] in
                await preferencesStore.load().diagnosticsConsent.allowsCollection
            },
            sink: telemetrySink)
    }

    /// Live composition for app launches.
    static func live() -> AppComposition {
        let configuration = AppConfiguration.load()
        let purchases: any Purchasing
        #if DEBUG
        if configuration.usesFakePurchases {
            // Explicit developer opt-in; fixture products are visibly marked "DEV".
            purchases = FakePurchaseService()
        } else {
            purchases = UnconfiguredPurchaseService()
        }
        #else
        // M06 replaces this with the RevenueCat adapter once the owner supplies configuration.
        purchases = UnconfiguredPurchaseService()
        #endif

        return AppComposition(
            configuration: configuration,
            preferencesStore: UserDefaultsAppPreferencesStore(),
            purchases: purchases,
            // M06: Firebase sink once GoogleService-Info.plist exists. Consent gate stays in front.
            telemetrySink: DiscardingTelemetrySink(),
            // M00-TEMPORARY: in-memory until the SwiftData project store lands in M01.
            projectStore: InMemoryProjectStore(),
            lookCatalog: BundledLookCatalogProvider(),
            // M00-TEMPORARY: in-memory until the SwiftData LookPreferences record lands in M01.
            lookPreferencesStore: InMemoryLookPreferencesStore(),
            captureCapabilities: DeviceCaptureCapabilities())
    }

    var hasCompletedOnboarding: Bool { preferencesStore.load().hasCompletedOnboarding }

    // MARK: ViewModel factories

    func makeOnboardingViewModel() -> OnboardingViewModel {
        OnboardingViewModel(preferencesStore: preferencesStore) { [router] in
            router.finishOnboarding()
        }
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            projectStore: projectStore,
            lookCatalog: lookCatalog,
            lookPreferencesStore: lookPreferencesStore,
            onSeeAll: { [router] in router.showAllProjects() },
            onInspectLook: { [router] in router.inspectLook($0) },
            onOpenProject: { [router] in router.openProject($0) })
    }

    func makeLooksViewModel() -> LooksViewModel {
        LooksViewModel(
            lookCatalog: lookCatalog,
            lookPreferencesStore: lookPreferencesStore,
            onInspect: { [router] in router.inspectLook($0) })
    }

    func makeLookInspectionViewModel(lookID: LookID) -> LookInspectionViewModel {
        LookInspectionViewModel(
            lookID: lookID,
            lookCatalog: lookCatalog,
            lookPreferencesStore: lookPreferencesStore,
            onCreate: { [router] in router.startCreation(withLook: $0) },
            onClose: { [router] in router.inspectedLookID = nil })
    }

    func makeProjectsViewModel() -> ProjectsViewModel {
        ProjectsViewModel(
            projectStore: projectStore,
            onOpenProject: { [router] in router.openProject($0) },
            onCreateFirst: { [router] in router.goHomeAndOpenCreation() })
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            purchases: purchases,
            preferencesStore: preferencesStore,
            onLanguageChange: { [localization] in localization.apply($0) },
            onShowPaywall: { [router] in router.showPaywall(.settings) })
    }

    func makePaywallViewModel(reason: PaywallReason) -> PaywallViewModel {
        PaywallViewModel(
            reason: reason,
            purchases: purchases,
            telemetry: telemetry,
            onClose: { [router] in router.dismissFlow() },
            // Export upgrade intent resumes in M02/M06; from Settings the sheet just closes.
            onGranted: { [router] in router.dismissFlow() })
    }
}
