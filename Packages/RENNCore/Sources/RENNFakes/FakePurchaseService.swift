import Foundation
import RENNDomain

/// Scriptable purchase fake for tests and explicitly enabled development builds.
/// Its products are labelled fixtures; it must never back a production build (06 C03).
public actor FakePurchaseService: Purchasing {
    public private(set) var access: AccessState
    public var scriptedProducts: Result<[PurchaseProduct], PurchaseFailure>
    public var scriptedPurchaseOutcome: PurchaseOutcome
    public var scriptedRestoreOutcome: RestoreOutcome
    public private(set) var purchaseRequests: [String] = []
    private var broadcaster = StreamBroadcaster<AccessState>()

    /// Development fixture products. Prices are marked as fixtures and are not Store prices.
    public static let fixtureProducts: [PurchaseProduct] = [
        PurchaseProduct(id: "dev.fixture.monthly", plan: .monthly, localizedPrice: "DEV 2.99"),
        PurchaseProduct(id: "dev.fixture.annual", plan: .annual, localizedPrice: "DEV 14.99"),
        PurchaseProduct(id: "dev.fixture.lifetime", plan: .lifetime, localizedPrice: "DEV 29.99"),
    ]

    public init(
        access: AccessState = AccessState(level: .free, provenance: .developmentFake),
        products: Result<[PurchaseProduct], PurchaseFailure> = .success(FakePurchaseService.fixtureProducts),
        purchaseOutcome: PurchaseOutcome = .granted(AccessState(level: .pro, provenance: .developmentFake)),
        restoreOutcome: RestoreOutcome = .nothingToRestore(AccessState(level: .free, provenance: .developmentFake))
    ) {
        self.access = access
        scriptedProducts = products
        scriptedPurchaseOutcome = purchaseOutcome
        scriptedRestoreOutcome = restoreOutcome
    }

    public func currentAccess() async -> AccessState { access }

    public func accessUpdates() async -> AsyncStream<AccessState> {
        broadcaster.makeStream(initial: access) { [weak self] token in
            Task { await self?.removeSubscriber(token) }
        }
    }

    public func products() async throws(PurchaseFailure) -> [PurchaseProduct] {
        try scriptedProducts.get()
    }

    public func purchase(productID: String) async -> PurchaseOutcome {
        purchaseRequests.append(productID)
        if case .granted(let newAccess) = scriptedPurchaseOutcome {
            setAccess(newAccess)
        }
        return scriptedPurchaseOutcome
    }

    public func restore() async -> RestoreOutcome {
        switch scriptedRestoreOutcome {
        case .restored(let newAccess), .nothingToRestore(let newAccess):
            setAccess(newAccess)
        case .failed:
            break
        }
        return scriptedRestoreOutcome
    }

    public func setAccess(_ newAccess: AccessState) {
        access = newAccess
        broadcaster.yield(newAccess)
    }

    public func script(products: Result<[PurchaseProduct], PurchaseFailure>) {
        scriptedProducts = products
    }

    public func script(purchaseOutcome: PurchaseOutcome) {
        scriptedPurchaseOutcome = purchaseOutcome
    }

    private func removeSubscriber(_ token: UUID) {
        broadcaster.remove(token)
    }
}
