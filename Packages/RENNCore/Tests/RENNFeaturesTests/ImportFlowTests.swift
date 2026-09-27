import Foundation
import Testing
import RENNDomain
import RENNFakes
@testable import RENNFeatures

@MainActor
@Suite("Import flow (01 P08, 05 V06)")
struct ImportFlowTests {
    private struct Harness {
        let viewModel: ImportFlowViewModel
        let importer: FakeVideoImporter
        let store: InMemoryProjectStore
        let purchases: FakePurchaseService
        let preferences: InMemoryLookPreferencesStore
        let log: CallLog
    }

    private func harness(
        seconds: Int64 = 12,
        access: AccessState = .notConfigured,
        failure: MediaPreparationFailure? = nil,
        lookID: LookID? = nil
    ) -> Harness {
        let importer = FakeVideoImporter(result: failure.map { .failure($0) } ?? .success(FakeVideoImporter.prepared(seconds: seconds)))
        let store = InMemoryProjectStore()
        let purchases = FakePurchaseService(access: access)
        let preferences = InMemoryLookPreferencesStore()
        let log = CallLog()
        let viewModel = ImportFlowViewModel(
            lookID: lookID, importer: importer, projects: store, access: purchases,
            lookCatalog: StaticLookCatalogProvider(StaticLookCatalogProvider.developmentCatalog),
            lookPreferences: preferences, telemetry: RecordingTelemetry(),
            makeName: { _ in try! ProjectName("Tape · test") },
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            timeZone: TimeZone(identifier: "Europe/Istanbul")!,
            onShowPaywall: { log.record("paywall") },
            onFinished: { log.record("finished \($0 == $0)") },
            onClose: { log.record("close") })
        return Harness(viewModel: viewModel, importer: importer, store: store, purchases: purchases, preferences: preferences, log: log)
    }

    @Test func shortFreeImportCreatesProjectAndRecordsLook() async throws {
        let h = harness(seconds: 12)
        await h.viewModel.didPick(URL(fileURLWithPath: "/picked.mov"))
        guard case .finished(let id) = h.viewModel.state else {
            Issue.record("Expected finished, got \(h.viewModel.state)"); return
        }
        let record = try await h.store.project(id)
        #expect(record.name.value == "Tape · test")
        #expect(record.sourceMode == .imported)
        #expect(record.recipe.lookID == "dev.diagnostic", "Falls back to the recommended Look")
        #expect(record.recipe.indicators.stampDate.text == "2026.09.21")
        #expect(record.sources.first?.relativePath.components.last == "source.mov")
        #expect(await h.preferences.load().recentIDs == ["dev.diagnostic"])
        #expect(h.log.entries == ["finished true"])
    }

    @Test func freeImportOverThirtySecondsOffersProAndNeverTrims() async throws {
        let h = harness(seconds: 31)
        await h.viewModel.didPick(URL(fileURLWithPath: "/picked.mov"))
        #expect(h.viewModel.state == .requiresPro(sourceDuration: .seconds(31)))
        #expect(try await h.store.projects().isEmpty, "No project, no automatic trim")
        h.viewModel.upgrade()
        #expect(h.log.entries == ["paywall"])

        // Still Free after the paywall: stays gated.
        await h.viewModel.accessMayHaveChanged()
        #expect(h.viewModel.state == .requiresPro(sourceDuration: .seconds(31)))

        // Pro granted: continues the same import once.
        await h.purchases.setAccess(AccessState(level: .pro, provenance: .developmentFake))
        await h.viewModel.accessMayHaveChanged()
        guard case .finished = h.viewModel.state else { Issue.record("Expected finished"); return }
        #expect(try await h.store.projects().count == 1)
        #expect(await h.importer.prepareCount == 1, "The staged copy is reused, not copied again")
    }

    @Test func chooseAnotherDiscardsTheStagedCopy() async throws {
        let h = harness(seconds: 45)
        await h.viewModel.didPick(URL(fileURLWithPath: "/picked.mov"))
        await h.viewModel.chooseAnother()
        #expect(h.viewModel.state == .picking)
        #expect(await h.importer.discarded.count == 1)
        #expect(try await h.store.projects().isEmpty)
    }

    @Test func cancelDiscardsAndCloses() async {
        let h = harness(seconds: 45)
        await h.viewModel.didPick(URL(fileURLWithPath: "/picked.mov"))
        await h.viewModel.cancel()
        #expect(await h.importer.discarded.count == 1)
        #expect(h.log.entries == ["close"])
    }

    @Test func proLongImportIsAccepted() async throws {
        let h = harness(seconds: 900, access: AccessState(level: .pro, provenance: .developmentFake))
        await h.viewModel.didPick(URL(fileURLWithPath: "/picked.mov"))
        guard case .finished = h.viewModel.state else { Issue.record("Expected finished"); return }
    }

    @Test func preparationFailuresAreTypedAndNothingIsRecorded() async throws {
        let h = harness(failure: .unsupportedFormat)
        await h.viewModel.didPick(URL(fileURLWithPath: "/picked.mov"))
        #expect(h.viewModel.state == .failed(.unsupported))
        #expect(try await h.store.projects().isEmpty)
        #expect(await h.preferences.load().recentIDs.isEmpty, "Failed imports never create history")
    }

    @Test func chosenLookIsUsed() async throws {
        let h = harness(lookID: "dev.diagnostic")
        await h.viewModel.didPick(URL(fileURLWithPath: "/picked.mov"))
        guard case .finished(let id) = h.viewModel.state else { Issue.record("Expected finished"); return }
        #expect(try await h.store.project(id).recipe.lookID == "dev.diagnostic")
    }

    @Test func durationBuckets() {
        #expect(TelemetryEvent.DurationBucket.bucket(.seconds(30)) == .upTo30s)
        #expect(TelemetryEvent.DurationBucket.bucket(.seconds(31)) == .upTo60s)
        #expect(TelemetryEvent.DurationBucket.bucket(.seconds(3600)) == .over10m)
    }
}
