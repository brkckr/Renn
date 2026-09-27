import Foundation
import RENNDomain
import RENNFakes
import RENNFeatures
import RENNStorage

/// The single composition root (04 A03). It constructs app-lifetime services once and
/// hands each ViewModel only the dependencies it needs. No feature code reaches back
/// into this object, and no service is exposed through a global or `.shared` accessor.
@MainActor
final class AppComposition {
    let configuration: AppConfiguration
    let router: AppRouter
    let localization: LocalizationController
    /// App-lifetime GPU/Core Image context shared by preview and export (04 A03).
    let renderEngine: RenderEngine
    /// App-lifetime export owner: jobs survive sheet dismissal (04 A03).
    let exportCoordinator: ExportCoordinator
    /// Canonical Beat timelines shared by preview and export (05 V05).
    let beatTimelines: AVBeatTimelineProvider
    /// Processed-frame posters for VHS cases (01 P03).
    let posters: PosterProvider

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
        let telemetry = ConsentGatedTelemetry(
            isCollectionAllowed: { [preferencesStore] in
                await preferencesStore.load().diagnosticsConsent.allowsCollection
            },
            sink: telemetrySink)
        self.telemetry = telemetry
        let engine = RenderEngine()
        renderEngine = engine
        let timelines = AVBeatTimelineProvider()
        beatTimelines = timelines
        posters = PosterProvider(projects: projectStore, engine: engine)
        exportCoordinator = ExportCoordinator(
            projects: projectStore, access: purchases,
            renderer: AVExportRenderer(engine: engine, beatTimelines: timelines),
            photos: PhotoLibrarySaver(), lookPreferences: lookPreferencesStore, telemetry: telemetry)
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

        let storage = makeStorage()
        return AppComposition(
            configuration: configuration,
            preferencesStore: UserDefaultsAppPreferencesStore(),
            purchases: purchases,
            // M06: Firebase sink once GoogleService-Info.plist exists. Consent gate stays in front.
            telemetrySink: DiscardingTelemetrySink(),
            projectStore: storage.projects,
            lookCatalog: BundledLookCatalogProvider(),
            lookPreferencesStore: storage.lookPreferences,
            captureCapabilities: DeviceCaptureCapabilities())
    }

    /// SwiftData metadata + owned files under Application Support/RENN (05 V07).
    /// If the store cannot be opened (e.g. written by a newer version), projects report
    /// "unavailable" and nothing is deleted; the database is never wiped (05 V08).
    private static func makeStorage() -> (projects: ProjectLibrary, lookPreferences: any LookPreferencesStoring) {
        let files = FileSystemOwnedFileStore(
            rootURL: URL.applicationSupportDirectory.appendingPathComponent("RENN", isDirectory: true),
            temporaryURL: URL.temporaryDirectory.appendingPathComponent("RENN", isDirectory: true))
        let library: ProjectLibrary
        let lookPreferences: any LookPreferencesStoring
        do {
            let container = try PersistenceController.makeContainer(storeURL: try PersistenceController.defaultStoreURL())
            library = ProjectLibrary(metadata: SwiftDataProjectMetadataStore(modelContainer: container), files: files)
            lookPreferences = SwiftDataLookPreferencesStore(modelContainer: container)
        } catch {
            library = ProjectLibrary(metadata: UnavailableProjectMetadataStore(), files: files)
            // Favorites still work for this session, but are not saved.
            lookPreferences = InMemoryLookPreferencesStore()
        }
        // Reconcile interrupted commits/deletions at launch, before any feature asks.
        Task { await library.reconcile() }
        return (library, lookPreferences)
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
            posters: posters,
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
            posters: posters,
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
            onGranted: { [router] in router.dismissFlow() })
    }

    /// Paywall over a running flow: closing returns to that flow, which re-checks access
    /// and continues the user's original request once (06 C03).
    func makeNestedPaywallViewModel(reason: PaywallReason) -> PaywallViewModel {
        PaywallViewModel(
            reason: reason,
            purchases: purchases,
            telemetry: telemetry,
            onClose: { [router] in router.nestedPaywall = nil },
            onGranted: { [router] in router.nestedPaywall = nil })
    }

    func makeImportFlowViewModel(lookID: LookID?) -> ImportFlowViewModel {
        ImportFlowViewModel(
            lookID: lookID,
            importer: AVVideoImporter(projects: projectStore),
            projects: projectStore,
            access: purchases,
            lookCatalog: lookCatalog,
            lookPreferences: lookPreferencesStore,
            telemetry: telemetry,
            makeName: { [localization] date in
                ProjectNameGenerator(
                    prefix: localization.string("project.defaultNamePrefix"),
                    locale: localization.locale,
                    timeZone: .current
                ).defaultName(createdAt: date)
            },
            onShowPaywall: { [router] in router.showNestedPaywall(.freeDurationLimit) },
            onFinished: { [router] in router.replaceFlow(with: .projectPreview($0)) },
            onClose: { [router] in router.dismissFlow() })
    }

    /// One capture controller per camera flow (04 A03 camera-flow lifetime).
    func makeCameraParts(lookID: LookID?) -> CameraView.Parts {
        let controller = AVCaptureController()
        let viewModel = CaptureFlowViewModel(
            lookID: lookID,
            capture: controller,
            permissions: AVCapturePermissions(),
            projects: projectStore,
            access: purchases,
            lookCatalog: lookCatalog,
            lookPreferences: lookPreferencesStore,
            telemetry: telemetry,
            makeName: { [localization] date in
                ProjectNameGenerator(
                    prefix: localization.string("project.defaultNamePrefix"),
                    locale: localization.locale,
                    timeZone: .current
                ).defaultName(createdAt: date)
            },
            onFinished: { [router] in router.replaceFlow(with: .projectPreview($0)) },
            onImportInstead: { [router] in router.replaceFlow(with: .importVideo(lookID: lookID)) },
            onClose: { [router] in router.dismissFlow() })
        return CameraView.Parts(viewModel: viewModel, frames: controller.frames)
    }

    /// One multi-camera controller per Dual-Cam flow (04 A03 camera-flow lifetime).
    func makeDualCameraParts(lookID: LookID?) -> DualCameraView.Parts {
        let controller = AVDualCaptureController()
        let viewModel = DualCaptureFlowViewModel(
            lookID: lookID,
            capture: controller,
            permissions: AVCapturePermissions(),
            projects: projectStore,
            access: purchases,
            lookCatalog: lookCatalog,
            lookPreferences: lookPreferencesStore,
            telemetry: telemetry,
            makeName: { [localization] date in
                ProjectNameGenerator(
                    prefix: localization.string("project.defaultNamePrefix"),
                    locale: localization.locale,
                    timeZone: .current
                ).defaultName(createdAt: date)
            },
            onFinished: { [router] in router.replaceFlow(with: .projectPreview($0)) },
            onImportInstead: { [router] in router.replaceFlow(with: .importVideo(lookID: lookID)) },
            onClose: { [router] in router.dismissFlow() })
        return DualCameraView.Parts(
            viewModel: viewModel, rearFrames: controller.rearFrames, frontFrames: controller.frontFrames)
    }

    func makeProjectPreviewViewModel(projectID: ProjectID) -> ProjectPreviewViewModel {
        ProjectPreviewViewModel(
            projectID: projectID,
            projects: projectStore,
            access: purchases,
            exporter: exportCoordinator,
            telemetry: telemetry,
            beatTimelines: beatTimelines,
            onClose: { [router] in router.dismissFlow() },
            onShowPaywall: { [router] in router.showNestedPaywall(.exportUpgrade) })
    }
}
