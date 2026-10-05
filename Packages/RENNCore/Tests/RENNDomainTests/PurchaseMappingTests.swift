import Foundation
import Testing
@testable import RENNDomain

@Suite("Purchase mapping (06 C02/C03)")
struct PurchaseMappingTests {
    typealias Package = PurchaseMapping.OfferedPackage
    let now = Date(timeIntervalSince1970: 1_000)

    @Test func offeringBecomesThreePlansInDisplayOrder() {
        let products = PurchaseMapping.products(from: [
            Package(productID: "life", kind: .lifetime, localizedPrice: "₺599,99"),
            Package(productID: "custom", kind: .other, localizedPrice: "x"),
            Package(productID: "year", kind: .annual, localizedPrice: "₺249,99"),
            Package(productID: "month", kind: .monthly, localizedPrice: "₺49,99"),
            Package(productID: "month2", kind: .monthly, localizedPrice: "₺1"),
        ])
        #expect(products.map(\.plan) == [.monthly, .annual, .lifetime])
        #expect(products.map(\.id) == ["month", "year", "life"], "First package of each kind wins")
        #expect(products[1].localizedPrice == "₺249,99", "Store-localized price passes through")
    }

    @Test func missingPackagesAreAbsentNotInvented() {
        #expect(PurchaseMapping.products(from: []).isEmpty)
        #expect(PurchaseMapping.products(from: [Package(productID: "", kind: .annual, localizedPrice: "$1")]).isEmpty)
        #expect(PurchaseMapping.products(from: [Package(productID: "y", kind: .annual, localizedPrice: "$14.99")]).map(\.plan) == [.annual])
    }

    @Test func eligibleFreeTrialStaysOnSubscriptionsOnly() {
        let week = FreeTrial(value: 1, unit: .week)
        let products = PurchaseMapping.products(from: [
            Package(productID: "month", kind: .monthly, localizedPrice: "$2.99"),
            Package(productID: "year", kind: .annual, localizedPrice: "$14.99", eligibleFreeTrial: week),
            Package(productID: "life", kind: .lifetime, localizedPrice: "$29.99", eligibleFreeTrial: week),
        ])
        #expect(products.map(\.freeTrial) == [nil, week, nil], "Only the subscription the Store offers it on; never lifetime")
        let zero = PurchaseMapping.products(from: [
            Package(productID: "year", kind: .annual, localizedPrice: "$14.99", eligibleFreeTrial: FreeTrial(value: 0, unit: .day)),
        ])
        #expect(zero.first?.freeTrial == nil, "A zero-length period is no trial")
    }

    @Test func onlyTheProEntitlementGrantsPro() {
        let pro = PurchaseMapping.access(activeEntitlements: ["pro"], fromCache: false, checkedAt: now)
        #expect(pro == AccessState(level: .pro, provenance: .providerVerified, checkedAt: now))
        let cached = PurchaseMapping.access(activeEntitlements: ["pro"], fromCache: true, checkedAt: now)
        #expect(cached.provenance == .providerCache && cached.effectiveTier == .pro)
        let other = PurchaseMapping.access(activeEntitlements: ["legacy"], fromCache: false, checkedAt: now)
        #expect(other.level == .free)
    }

    @Test func purchaseOutcomesNeverUnlockWithoutTheEntitlement() {
        #expect(PurchaseMapping.outcome(.completed(activeEntitlements: ["pro"]), checkedAt: now)
            == .granted(AccessState(level: .pro, provenance: .providerVerified, checkedAt: now)))
        #expect(PurchaseMapping.outcome(.completed(activeEntitlements: []), checkedAt: now) == .pending)
        #expect(PurchaseMapping.outcome(.userCancelled, checkedAt: now) == .cancelled)
        #expect(PurchaseMapping.outcome(.pending, checkedAt: now) == .pending)
        #expect(PurchaseMapping.outcome(.failed(.network), checkedAt: now) == .failed(.network))
    }

    @Test func restoreReportsNothingWithoutAnActiveEntitlement() {
        #expect(PurchaseMapping.restoreOutcome(activeEntitlements: [], checkedAt: now)
            == .nothingToRestore(AccessState(level: .free, provenance: .providerVerified, checkedAt: now)))
        if case .restored = PurchaseMapping.restoreOutcome(activeEntitlements: ["pro"], checkedAt: now) {} else {
            Issue.record("Active entitlement restores Pro")
        }
    }
}
