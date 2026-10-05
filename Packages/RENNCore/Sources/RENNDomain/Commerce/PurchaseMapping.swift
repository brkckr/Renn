import Foundation

/// Provider-neutral rules for turning the purchase SDK's data into RENN's commerce model
/// (06 C02/C03). The RevenueCat adapter only converts SDK types into these inputs, so the rules
/// are testable without the SDK or a Store.
public enum PurchaseMapping {
    /// One package of the current offering, as reported by the provider.
    public struct OfferedPackage: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case monthly, annual, lifetime, other
        }

        public let productID: String
        public let kind: Kind
        /// Store-localized price string (never hardcoded by the app).
        public let localizedPrice: String
        /// The Store's free introductory period, only when the user is eligible for it.
        public let eligibleFreeTrial: FreeTrial?

        public init(productID: String, kind: Kind, localizedPrice: String, eligibleFreeTrial: FreeTrial? = nil) {
            self.productID = productID
            self.kind = kind
            self.localizedPrice = localizedPrice
            self.eligibleFreeTrial = eligibleFreeTrial
        }
    }

    /// The three plans in display order (monthly, annual, lifetime). The first package of each
    /// kind wins; other package types are ignored; a missing plan is simply absent. Empty means
    /// "products unavailable" (retry / restore / continue Free), never a hardcoded price.
    /// A free trial is kept only on a subscription (a one-time lifetime purchase never has one)
    /// and only with a positive length.
    public static func products(from packages: [OfferedPackage]) -> [PurchaseProduct] {
        let order: [(OfferedPackage.Kind, PurchasePlan)] = [(.monthly, .monthly), (.annual, .annual), (.lifetime, .lifetime)]
        return order.compactMap { kind, plan in
            packages.first { $0.kind == kind && !$0.productID.isEmpty }.map {
                let trial = plan == .lifetime ? nil : $0.eligibleFreeTrial.flatMap { $0.value > 0 ? $0 : nil }
                return PurchaseProduct(id: $0.productID, plan: plan, localizedPrice: $0.localizedPrice, freeTrial: trial)
            }
        }
    }

    /// Access from the provider's customer information: Pro only when the `pro` entitlement is
    /// active. `fromCache` marks SDK-cached information (06 C03: SDK cache semantics only; no
    /// custom offline grace).
    public static func access(activeEntitlements: Set<String>, fromCache: Bool, checkedAt: Date) -> AccessState {
        AccessState(
            level: activeEntitlements.contains(AppIdentity.proEntitlementID) ? .pro : .free,
            provenance: fromCache ? .providerCache : .providerVerified,
            checkedAt: checkedAt)
    }

    /// Purchase result from the provider. Only a verified active entitlement grants Pro; a
    /// completed transaction without it is reported as pending (e.g. awaiting verification).
    public enum TransactionResult: Sendable, Equatable {
        case completed(activeEntitlements: Set<String>)
        case userCancelled
        case pending
        case failed(PurchaseFailure)
    }

    public static func outcome(_ result: TransactionResult, checkedAt: Date) -> PurchaseOutcome {
        switch result {
        case .completed(let entitlements):
            let state = access(activeEntitlements: entitlements, fromCache: false, checkedAt: checkedAt)
            return state.level == .pro ? .granted(state) : .pending
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        case .failed(let failure):
            return .failed(failure)
        }
    }

    /// Restore result: restored only if the entitlement is now active.
    public static func restoreOutcome(activeEntitlements: Set<String>, checkedAt: Date) -> RestoreOutcome {
        let state = access(activeEntitlements: activeEntitlements, fromCache: false, checkedAt: checkedAt)
        return state.level == .pro ? .restored(state) : .nothingToRestore(state)
    }
}
