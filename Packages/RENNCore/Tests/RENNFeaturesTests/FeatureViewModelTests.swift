import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("Onboarding view model (01 P10)")
struct OnboardingViewModelTests {
    @Test func finishingPersistsAndRoutesOnce() {
        let store = InMemoryAppPreferencesStore()
        let log = CallLog()
        let viewModel = OnboardingViewModel(preferencesStore: store) { log.record("finished") }
        viewModel.next(); viewModel.next(); viewModel.next()
        #expect(viewModel.isLastPage)
        #expect(!store.stored.hasCompletedOnboarding)
        viewModel.next()
        viewModel.next()
        viewModel.skip()
        #expect(store.stored.hasCompletedOnboarding)
        #expect(log.entries == ["finished"])
    }

    @Test func skipDoesNotTouchOtherPreferences() {
        let store = InMemoryAppPreferencesStore(AppPreferences(language: .turkish, diagnosticsConsent: .declined))
        let viewModel = OnboardingViewModel(preferencesStore: store) {}
        viewModel.skip()
        #expect(store.stored == AppPreferences(hasCompletedOnboarding: true, language: .turkish, diagnosticsConsent: .declined))
    }
}

@MainActor
@Suite("Home view model (01 P03)")
struct HomeViewModelTests {
    @Test func showsAtMostThreeRecentProjectsAndFirstUsePrompt() async {
        let store = InMemoryProjectStore()
        let viewModel = HomeViewModel(
            projectStore: store,
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferencesStore: InMemoryLookPreferencesStore(),
            onSeeAll: {}, onInspectLook: { _ in }, onOpenProject: { _ in })
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }

        #expect(await eventually { viewModel.hasLoadedProjects })
        #expect(viewModel.showsFirstUsePrompt, "First use shows a create prompt without fake history")
        #expect(viewModel.recommendedLook?.id == "dev.diagnostic")
        #expect(viewModel.isCatalogDevelopmentFixture)

        for index in 0..<5 {
            await store.insert(makeProject("Tape \(index)", minutesAgo: Double(10 - index)))
        }
        #expect(await eventually { viewModel.recentProjects.map(\.name.value) == ["Tape 4", "Tape 3", "Tape 2"] })
        #expect(viewModel.recentProjects.count == 3)
        #expect(!viewModel.showsFirstUsePrompt)
    }

    @Test func recentLooksResolveAgainstCatalogAndSkipUnknownIDs() async throws {
        let catalog = try LookCatalog(
            catalogVersion: "t", isDevelopmentFixture: false, recommendedLookID: "b",
            looks: [makeLook("a"), makeLook("b"), makeLook("c")])
        let preferences = InMemoryLookPreferencesStore(LookPreferences(recentIDs: ["c", "retired", "a"]))
        let viewModel = HomeViewModel(
            projectStore: InMemoryProjectStore(),
            lookCatalog: StaticLookCatalogProvider(catalog),
            lookPreferencesStore: preferences,
            onSeeAll: {}, onInspectLook: { _ in }, onOpenProject: { _ in })
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }

        #expect(await eventually { viewModel.recentLooks.map(\.id) == ["c", "a"] })
        #expect(viewModel.recommendedLook?.id == "b")

        await preferences.recordUse(of: "b")
        #expect(await eventually { viewModel.recentLooks.map(\.id) == ["b", "c", "a"] })
    }

    @Test func showcaseOffersCatalogLooksUntilALookIsUsed() async throws {
        let catalog = try LookCatalog(
            catalogVersion: "t", isDevelopmentFixture: false, recommendedLookID: "b",
            looks: ["a", "b", "c", "d", "e", "f"].map { makeLook($0) })
        let preferences = InMemoryLookPreferencesStore()
        let viewModel = HomeViewModel(
            projectStore: InMemoryProjectStore(),
            lookCatalog: StaticLookCatalogProvider(catalog),
            lookPreferencesStore: preferences,
            onSeeAll: {}, onInspectLook: { _ in }, onOpenProject: { _ in })
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }

        // Catalog order, without the recommended Look, at most four; no fake history.
        #expect(await eventually { viewModel.showcaseLooks.map(\.id) == ["a", "c", "d", "e"] })
        #expect(viewModel.recentLooks.isEmpty)

        await preferences.recordUse(of: "f")
        #expect(await eventually { viewModel.recentLooks.map(\.id) == ["f"] })
        #expect(viewModel.showcaseLooks.isEmpty, "Real history replaces the showcase")
    }

    @Test func proBadgeOpensThePaywallOnlyForFreeUsers() async {
        let log = CallLog()
        let purchases = FakePurchaseService()
        let viewModel = HomeViewModel(
            projectStore: InMemoryProjectStore(),
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferencesStore: InMemoryLookPreferencesStore(),
            access: purchases,
            onShowPaywall: { log.record("paywall") },
            onSeeAll: {}, onInspectLook: { _ in }, onOpenProject: { _ in })
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }

        #expect(await eventually { viewModel.hasLoadedProjects })
        #expect(!viewModel.isPro)
        viewModel.showPaywall()
        #expect(log.entries == ["paywall"])

        _ = await purchases.purchase(productID: "dev.fixture.monthly")
        #expect(await eventually { viewModel.isPro })
        viewModel.showPaywall()
        #expect(log.entries == ["paywall"], "Pro sees a status badge, not an upsell")
    }

    @Test func catalogFailureIsReported() async {
        let viewModel = HomeViewModel(
            projectStore: InMemoryProjectStore(),
            lookCatalog: StaticLookCatalogProvider(failure: .emptyIdentifier),
            lookPreferencesStore: InMemoryLookPreferencesStore(),
            onSeeAll: {}, onInspectLook: { _ in }, onOpenProject: { _ in })
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await eventually { viewModel.catalogState == .failed })
        #expect(viewModel.recommendedLook == nil)
    }

    @Test func navigationIsDelegated() {
        let log = CallLog()
        let id = ProjectID()
        let viewModel = HomeViewModel(
            projectStore: InMemoryProjectStore(),
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferencesStore: InMemoryLookPreferencesStore(),
            onSeeAll: { log.record("seeAll") },
            onInspectLook: { log.record("inspect \($0)") },
            onOpenProject: { log.record("open \($0 == id)") })
        viewModel.seeAll()
        viewModel.inspect("dev.diagnostic")
        viewModel.open(id)
        #expect(log.entries == ["seeAll", "inspect dev.diagnostic", "open true"])
    }
}

@MainActor
@Suite("Looks view model (01 P04)")
struct LooksViewModelTests {
    @Test func filtersShowOnlyRealFamiliesAndFavorites() async throws {
        let catalog = try LookCatalog(
            catalogVersion: "t", isDevelopmentFixture: false, recommendedLookID: nil,
            looks: [makeLook("a", family: "vhs"), makeLook("b", family: "hi8"), makeLook("c", family: "vhs")])
        let preferences = InMemoryLookPreferencesStore(LookPreferences(favoriteIDs: ["b"]))
        let viewModel = LooksViewModel(
            lookCatalog: StaticLookCatalogProvider(catalog), lookPreferencesStore: preferences, onInspect: { _ in })
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }

        #expect(await eventually { viewModel.loadState == .loaded && viewModel.isFavorite("b") })
        #expect(viewModel.filters == [.all, .favorites, .family("vhs"), .family("hi8")])
        #expect(viewModel.visibleLooks.map(\.id) == ["a", "b", "c"])
        viewModel.filter = .favorites
        #expect(viewModel.visibleLooks.map(\.id) == ["b"])
        viewModel.filter = .family("vhs")
        #expect(viewModel.visibleLooks.map(\.id) == ["a", "c"])
        #expect(viewModel.isDevelopmentCatalog, "Three Looks is not the twelve-Look launch catalog")
    }

    @Test func inspectionFavoriteAndCreate() async {
        let preferences = InMemoryLookPreferencesStore()
        let log = CallLog()
        let viewModel = LookInspectionViewModel(
            lookID: "dev.diagnostic",
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferencesStore: preferences,
            onCreate: { log.record("create \($0)") },
            onClose: { log.record("close") })
        await viewModel.load()
        #expect(viewModel.look?.id == "dev.diagnostic")
        #expect(!viewModel.isFavorite)
        await viewModel.toggleFavorite()
        #expect(await preferences.load().isFavorite("dev.diagnostic"))
        viewModel.createWithThisLook()
        #expect(log.entries == ["create dev.diagnostic"])
        #expect(await preferences.load().recentIDs.isEmpty, "Browsing never records Look history")
    }

    @Test func unknownLookCannotStartCreation() async {
        let log = CallLog()
        let viewModel = LookInspectionViewModel(
            lookID: "missing",
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferencesStore: InMemoryLookPreferencesStore(),
            onCreate: { log.record("create \($0)") }, onClose: {})
        await viewModel.load()
        #expect(viewModel.loadFailed)
        viewModel.createWithThisLook()
        #expect(log.entries.isEmpty)
    }
}

@MainActor
@Suite("Projects view model (01 P03, 02 D08)")
struct ProjectsViewModelTests {
    @Test func emptyStateAndUpdates() async {
        let store = InMemoryProjectStore()
        let viewModel = ProjectsViewModel(projectStore: store, onOpenProject: { _ in }, onCreateFirst: {})
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await eventually { viewModel.isEmpty })
        await store.insert(makeProject("A", minutesAgo: 1))
        #expect(await eventually { viewModel.projects.count == 1 })
        #expect(!viewModel.isEmpty)
    }

    @Test func caseVariantIsDeterministic() {
        let id = ProjectID()
        let variant = ProjectsViewModel.caseVariant(for: id)
        for _ in 0..<10 { #expect(ProjectsViewModel.caseVariant(for: id) == variant) }
        #expect((0..<4).contains(variant))
        let spread = Set((0..<200).map { _ in ProjectsViewModel.caseVariant(for: ProjectID()) })
        #expect(spread.count == 4)
    }
}

@MainActor
@Suite("Settings view model (01 P10, 06 C03/C05)")
struct SettingsViewModelTests {
    @Test func storageShowsUsageAndClearsOnlyTheCache() async {
        let usage = FakeStorageUsage(StorageUsage(projectBytes: 5_000_000, cacheBytes: 120_000))
        let viewModel = SettingsViewModel(
            purchases: FakePurchaseService(), preferencesStore: InMemoryAppPreferencesStore(), storageUsage: usage,
            onLanguageChange: { _ in }, onShowPaywall: {})
        #expect(viewModel.storage == nil)
        await viewModel.refreshStorage()
        #expect(viewModel.storage == StorageUsage(projectBytes: 5_000_000, cacheBytes: 120_000))
        await viewModel.clearCache()
        #expect(viewModel.storage == StorageUsage(projectBytes: 5_000_000, cacheBytes: 0), "Projects are untouched")
        #expect(await usage.clearCount == 1)
        #expect(!viewModel.isClearingCache)
    }

    @Test func languageChoicePersistsAndNotifies() {
        let store = InMemoryAppPreferencesStore()
        let log = CallLog()
        let viewModel = SettingsViewModel(
            purchases: FakePurchaseService(), preferencesStore: store,
            onLanguageChange: { log.record("lang \($0.rawValue)") }, onShowPaywall: {})
        viewModel.setLanguage(.turkish)
        viewModel.setLanguage(.turkish)
        #expect(store.stored.language == .turkish)
        #expect(log.entries == ["lang turkish"])
    }

    @Test func diagnosticsDefaultOffAndExplicit() {
        let store = InMemoryAppPreferencesStore()
        let log = CallLog()
        let viewModel = SettingsViewModel(
            purchases: FakePurchaseService(), preferencesStore: store, onLanguageChange: { _ in },
            onDiagnosticsChange: { log.record("sdk \($0.rawValue)") }, onShowPaywall: {})
        #expect(!viewModel.diagnosticsConsent.allowsCollection)
        viewModel.setDiagnosticsEnabled(true)
        #expect(store.stored.diagnosticsConsent == .granted)
        viewModel.setDiagnosticsEnabled(true)
        viewModel.setDiagnosticsEnabled(false)
        #expect(store.stored.diagnosticsConsent == .declined)
        #expect(log.entries == ["sdk granted", "sdk declined"], "SDK collection follows each real change once")
    }

    @Test func restoreFailureIsTruthfulWhenNotConfigured() async {
        let purchases = FakePurchaseService()
        await purchases.script(products: .failure(.notConfigured))
        let viewModel = SettingsViewModel(
            purchases: UnconfiguredLikePurchases(), preferencesStore: InMemoryAppPreferencesStore(),
            onLanguageChange: { _ in }, onShowPaywall: {})
        await viewModel.restorePurchases()
        #expect(viewModel.restoreState == .failed(.notConfigured))
        #expect(!viewModel.isPro)
    }

    @Test func proHidesPaywallEntryAndObservesAccess() async {
        let purchases = FakePurchaseService()
        let log = CallLog()
        let viewModel = SettingsViewModel(
            purchases: purchases, preferencesStore: InMemoryAppPreferencesStore(),
            onLanguageChange: { _ in }, onShowPaywall: { log.record("paywall") })
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await eventually { viewModel.access.level == .free })
        viewModel.showPaywall()
        await purchases.setAccess(AccessState(level: .pro, provenance: .developmentFake))
        #expect(await eventually { viewModel.isPro })
        viewModel.showPaywall()
        #expect(log.entries == ["paywall"])
    }
}

/// Mirrors the app's UnconfiguredPurchaseService contract for package-level tests.
private struct UnconfiguredLikePurchases: Purchasing {
    func currentAccess() async -> AccessState { .notConfigured }
    func accessUpdates() async -> AsyncStream<AccessState> {
        AsyncStream { $0.yield(.notConfigured); $0.finish() }
    }
    func products() async throws(PurchaseFailure) -> [PurchaseProduct] { throw .notConfigured }
    func purchase(productID: String) async -> PurchaseOutcome { .failed(.notConfigured) }
    func restore() async -> RestoreOutcome { .failed(.notConfigured) }
}

@MainActor
@Suite("Paywall view model (03 M04, 06 C03/C04)")
struct PaywallViewModelTests {
    private func makeViewModel(
        _ purchases: FakePurchaseService,
        telemetry: RecordingTelemetry = RecordingTelemetry(),
        log: CallLog = CallLog()
    ) -> PaywallViewModel {
        PaywallViewModel(
            reason: .settings, purchases: purchases, telemetry: telemetry,
            onClose: { log.record("close") }, onGranted: { log.record("granted") })
    }

    @Test func defaultsToAnnualAndOrdersPlans() async {
        let viewModel = makeViewModel(FakePurchaseService())
        await viewModel.load()
        #expect(viewModel.products.map(\.plan) == [.monthly, .annual, .lifetime])
        #expect(viewModel.selectedProduct?.plan == .annual)
    }

    @Test func unavailableProductsNeverShowHardcodedPrices() async {
        let purchases = FakePurchaseService(products: .failure(.notConfigured))
        let viewModel = makeViewModel(purchases)
        await viewModel.load()
        #expect(viewModel.loadState == .unavailable(.notConfigured))
        #expect(viewModel.products.isEmpty)
        #expect(!viewModel.canPurchase)
    }

    @Test func rapidSelectionsLastWinsAndPurchasedProductMatches() async {
        let purchases = FakePurchaseService()
        let log = CallLog()
        let viewModel = makeViewModel(purchases, log: log)
        await viewModel.load()
        let ids = viewModel.products.map(\.id)
        for index in 0..<10 { viewModel.select(ids[index % ids.count]) }
        let expected = ids[9 % ids.count]
        #expect(viewModel.selectedProductID == expected)
        await viewModel.purchase()
        #expect(await purchases.purchaseRequests == [expected])
        #expect(viewModel.purchaseState == .granted)
        #expect(log.entries == ["granted"])
    }

    @Test func pendingAndCancelledDoNotUnlock() async {
        for outcome in [PurchaseOutcome.pending, .cancelled, .failed(.store)] {
            let purchases = FakePurchaseService(purchaseOutcome: outcome)
            let log = CallLog()
            let viewModel = makeViewModel(purchases, log: log)
            await viewModel.load()
            await viewModel.purchase()
            #expect(log.entries.isEmpty)
            #expect(await purchases.currentAccess().effectiveTier == .free)
            #expect(viewModel.purchaseState != .granted)
        }
    }

    @Test func existingProCannotBuyAgain() async {
        let purchases = FakePurchaseService(access: AccessState(level: .pro, provenance: .developmentFake))
        let viewModel = makeViewModel(purchases)
        await viewModel.load()
        #expect(viewModel.isAlreadyPro)
        await viewModel.purchase()
        #expect(await purchases.purchaseRequests.isEmpty)
    }

    @Test func telemetryRecordsPlacementAndOutcome() async {
        let telemetry = RecordingTelemetry()
        let viewModel = makeViewModel(FakePurchaseService(purchaseOutcome: .cancelled), telemetry: telemetry)
        await viewModel.load()
        await viewModel.purchase()
        #expect(await telemetry.events == [
            .paywallShown(placement: .settings),
            .purchaseStarted(plan: .annual),
            .purchaseFinished(plan: .annual, result: .cancelled),
        ])
    }
}

@MainActor
@Suite("Projects rename and delete (01 P03)")
struct ProjectsActionsTests {
    private func makeViewModel(_ store: InMemoryProjectStore) -> ProjectsViewModel {
        ProjectsViewModel(projectStore: store, onOpenProject: { _ in }, onCreateFirst: {})
    }

    @Test func renameValidatesInput() async throws {
        let project = makeProject("Tape", minutesAgo: 1)
        let store = InMemoryProjectStore(projects: [project])
        let viewModel = makeViewModel(store)
        await #expect(throws: ProjectsViewModel.RenameError.empty) { try await viewModel.rename(project.id, to: "  ") }
        await #expect(throws: ProjectsViewModel.RenameError.multiline) { try await viewModel.rename(project.id, to: "a\nb") }
        await #expect(throws: ProjectsViewModel.RenameError.tooLong(maximum: 80)) {
            try await viewModel.rename(project.id, to: String(repeating: "x", count: 81))
        }
        #expect(await viewModel.renameResult(project.id, to: "") == .empty)
        #expect(await viewModel.renameResult(project.id, to: "  Beach day ") == nil)
        #expect(try await store.project(project.id).name.value == "Beach day")
    }

    @Test func deleteRequiresConfirmationAndRunsOnce() async throws {
        let project = makeProject("Tape", minutesAgo: 1)
        let store = InMemoryProjectStore(projects: [project])
        let viewModel = makeViewModel(store)
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await eventually { viewModel.projects.count == 1 })

        viewModel.requestDelete(project.id)
        #expect(viewModel.pendingDeletion?.id == project.id)
        #expect(try await store.projects().count == 1, "Nothing is deleted before confirmation")
        viewModel.cancelDelete()
        #expect(viewModel.pendingDeletion == nil)

        viewModel.requestDelete(project.id)
        async let first: Void = viewModel.confirmDelete()
        async let second: Void = viewModel.confirmDelete()
        _ = await (first, second)
        #expect(viewModel.actionError == nil, "The repeated confirmation is ignored, not reported as a failure")
        #expect(try await store.projects().isEmpty)
        #expect(await eventually { viewModel.isEmpty })
    }

    @Test func leasedProjectReportsInUse() async throws {
        let project = makeProject("Tape", minutesAgo: 1)
        let store = InMemoryProjectStore(projects: [project])
        let viewModel = makeViewModel(store)
        let task = Task { await viewModel.observe() }
        defer { task.cancel() }
        #expect(await eventually { viewModel.projects.count == 1 })
        let lease = try await store.acquireLease(project.id, purpose: .export)
        viewModel.requestDelete(project.id)
        await viewModel.confirmDelete()
        #expect(viewModel.actionError == .projectInUse)
        #expect(try await store.projects().count == 1)
        await store.releaseLease(lease)
    }

    @Test func unavailableMetadataIsReported() async {
        let viewModel = ProjectsViewModel(
            projectStore: UnavailableProjectStore(), onOpenProject: { _ in }, onCreateFirst: {})
        await viewModel.observe()
        #expect(viewModel.loadState == .unavailable)
    }
}

/// Store whose metadata cannot be opened.
private struct UnavailableProjectStore: ProjectStoring {
    func projects() async throws(ProjectStoreError) -> [ProjectSummary] { throw .metadataUnavailable }
    func projectUpdates() async -> AsyncStream<[ProjectSummary]> { AsyncStream { $0.finish() } }
    func project(_ id: ProjectID) async throws(ProjectStoreError) -> ProjectRecord { throw .metadataUnavailable }
    func createProject(_ draft: NewProjectDraft) async throws(ProjectStoreError) -> ProjectRecord { throw .metadataUnavailable }
    func updateRecipe(_ id: ProjectID, expectedRevision: Int, recipe: Recipe) async throws(ProjectStoreError) -> ProjectRecord {
        throw .metadataUnavailable
    }
    func rename(_ id: ProjectID, to name: ProjectName) async throws(ProjectStoreError) { throw .metadataUnavailable }
    func delete(_ id: ProjectID) async throws(ProjectStoreError) { throw .metadataUnavailable }
    func acquireLease(_ id: ProjectID, purpose: ProjectLease.Purpose) async throws(ProjectStoreError) -> ProjectLease {
        throw .metadataUnavailable
    }
    func releaseLease(_ lease: ProjectLease) async {}
    func makeJobFileURL(fileExtension: String) async throws(ProjectStoreError) -> URL { throw .metadataUnavailable }
    func makeStagingFileURL(fileExtension: String) async throws(ProjectStoreError) -> URL { throw .metadataUnavailable }
    func commitOutput(_ output: FinishedOutput, to id: ProjectID) async throws(ProjectStoreError) -> OutputRecord {
        throw .metadataUnavailable
    }
    func updatePhotosSave(
        _ state: PhotosSaveState, localIdentifier: String?, output: OutputID, project id: ProjectID
    ) async throws(ProjectStoreError) { throw .metadataUnavailable }
    func fileURL(_ path: OwnedRelativePath) async -> URL { URL(fileURLWithPath: "/dev/null") }
}
