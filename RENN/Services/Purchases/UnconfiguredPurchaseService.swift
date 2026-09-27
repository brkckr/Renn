import RENNDomain

/// Production-safe purchase service used while the RevenueCat configuration is absent.
/// It never grants Pro: access stays unknown (Free policy applies), products are
/// unavailable and restore reports the missing configuration truthfully (06 C03).
/// Replaced by the RevenueCat adapter in M06.
struct UnconfiguredPurchaseService: Purchasing {
    func currentAccess() async -> AccessState { .notConfigured }

    func accessUpdates() async -> AsyncStream<AccessState> {
        AsyncStream { continuation in
            continuation.yield(.notConfigured)
            continuation.finish()
        }
    }

    func products() async throws(PurchaseFailure) -> [PurchaseProduct] {
        throw .notConfigured
    }

    func purchase(productID: String) async -> PurchaseOutcome {
        .failed(.notConfigured)
    }

    func restore() async -> RestoreOutcome {
        .failed(.notConfigured)
    }
}
