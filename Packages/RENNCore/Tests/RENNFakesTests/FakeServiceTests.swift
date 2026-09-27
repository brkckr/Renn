import Foundation
import Testing
import RENNDomain
@testable import RENNFakes

@Suite("In-memory project store")
struct InMemoryProjectStoreTests {
    private func project(_ name: String, minutesAgo: Double) -> ProjectSummary {
        let date = Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60)
        return ProjectSummary(
            id: ProjectID(), name: try! ProjectName(name), createdAt: date, updatedAt: date,
            sourceMode: .imported, readiness: .ready, lookID: nil)
    }

    @Test func listsNewestFirst() async throws {
        let older = project("Older", minutesAgo: 10)
        let newer = project("Newer", minutesAgo: 1)
        let store = InMemoryProjectStore(projects: [older, newer])
        #expect(try await store.projects().map(\.name.value) == ["Newer", "Older"])
    }

    @Test func renameAndDeletePublishUpdates() async throws {
        let item = project("Tape", minutesAgo: 1)
        let store = InMemoryProjectStore(projects: [item])
        let updates = await store.projectUpdates()
        var iterator = updates.makeAsyncIterator()
        #expect(await iterator.next()?.first?.name.value == "Tape")

        try await store.rename(item.id, to: ProjectName("Renamed"))
        #expect(await iterator.next()?.first?.name.value == "Renamed")

        try await store.delete(item.id)
        #expect(await iterator.next()?.isEmpty == true)
    }

    @Test func leasedProjectCannotBeDeleted() async throws {
        let item = project("Tape", minutesAgo: 1)
        let store = InMemoryProjectStore(projects: [item])
        let lease = try await store.acquireLease(item.id, purpose: .share)
        await #expect(throws: ProjectStoreError.leased(item.id)) { try await store.delete(item.id) }
        #expect(try await store.projects().count == 1)
        await store.releaseLease(lease)
        try await store.delete(item.id)
    }

    @Test func missingProjectErrors() async {
        let store = InMemoryProjectStore()
        let id = ProjectID()
        await #expect(throws: ProjectStoreError.notFound(id)) { try await store.delete(id) }
    }

    @Test func cancelledSubscriberIsRemoved() async throws {
        let store = InMemoryProjectStore()
        let task = Task {
            for await _ in await store.projectUpdates() {}
        }
        // Wait until the subscription is registered.
        for _ in 0..<100 where await store.subscriberCount == 0 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(await store.subscriberCount == 1)
        task.cancel()
        for _ in 0..<100 where await store.subscriberCount > 0 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(await store.subscriberCount == 0)
    }
}

@Suite("Fake purchase service")
struct FakePurchaseServiceTests {
    @Test func grantedPurchaseUpdatesAccessStream() async {
        let service = FakePurchaseService()
        let updates = await service.accessUpdates()
        var iterator = updates.makeAsyncIterator()
        #expect(await iterator.next()?.level == .free)

        let outcome = await service.purchase(productID: "dev.fixture.annual")
        #expect(outcome == .granted(AccessState(level: .pro, provenance: .developmentFake)))
        #expect(await iterator.next()?.level == .pro)
        #expect(await service.purchaseRequests == ["dev.fixture.annual"])
    }

    @Test func pendingPurchaseDoesNotUnlock() async {
        let service = FakePurchaseService(purchaseOutcome: .pending)
        _ = await service.purchase(productID: "dev.fixture.monthly")
        #expect(await service.currentAccess().effectiveTier == .free)
    }

    @Test func fixturePricesAreVisiblyMarked() {
        #expect(FakePurchaseService.fixtureProducts.allSatisfy { $0.localizedPrice.hasPrefix("DEV") })
        #expect(Set(FakePurchaseService.fixtureProducts.map(\.plan)) == Set(PurchasePlan.allCases))
    }
}

@Suite("Look preference store")
struct LookPreferenceStoreTests {
    @Test func recordUseUpdatesStream() async {
        let store = InMemoryLookPreferencesStore()
        let updates = await store.updates()
        var iterator = updates.makeAsyncIterator()
        #expect(await iterator.next()?.recentIDs == [])
        await store.recordUse(of: "a")
        #expect(await iterator.next()?.recentIDs == ["a"])
    }

    @Test func developmentCatalogIsLabelled() {
        let catalog = StaticLookCatalogProvider.developmentCatalog
        #expect(catalog.isDevelopmentFixture)
        #expect(catalog.looks.allSatisfy { $0.isDevelopmentFixture })
        #expect(!catalog.isLaunchReady)
    }
}
