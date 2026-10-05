/// The three settled plans; all grant the same `pro` entitlement (06 C02).
public enum PurchasePlan: String, Sendable, CaseIterable, Codable {
    case monthly
    case annual
    case lifetime
}

/// A purchasable product as reported by the Store/provider at runtime. Prices are
/// always Store-localized strings; the app never hardcodes a purchasable price (06 C03).
public struct PurchaseProduct: Sendable, Equatable, Identifiable {
    /// Store product identifier (external configuration, not invented here).
    public let id: String
    public let plan: PurchasePlan
    public let localizedPrice: String
    /// A free introductory period the Store reports for this subscription and this user is
    /// eligible for; nil shows no trial copy (owner-approved annual trial, 2026-10-05).
    public let freeTrial: FreeTrial?

    public init(id: String, plan: PurchasePlan, localizedPrice: String, freeTrial: FreeTrial? = nil) {
        self.id = id
        self.plan = plan
        self.localizedPrice = localizedPrice
        self.freeTrial = freeTrial
    }
}

/// Length of a free introductory period, as configured in the Store (never invented here).
public struct FreeTrial: Sendable, Equatable {
    public enum Unit: Sendable, Equatable {
        case day, week, month, year
    }

    public let value: Int
    public let unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }
}

public enum PurchaseFailure: Error, Equatable, Sendable {
    /// No provider configuration in this build.
    case notConfigured
    /// Offerings/products could not be loaded.
    case productsUnavailable
    case network
    case store
    case unknown
}

public enum PurchaseOutcome: Sendable, Equatable {
    /// Verified entitlement from the provider; the only outcome that unlocks Pro.
    case granted(AccessState)
    /// Ask to Buy / deferred.
    case pending
    case cancelled
    case failed(PurchaseFailure)
}

public enum RestoreOutcome: Sendable, Equatable {
    case restored(AccessState)
    case nothingToRestore(AccessState)
    case failed(PurchaseFailure)
}

/// Read-only access state for screens and export policy (04 A05).
public protocol AccessStateProviding: Sendable {
    func currentAccess() async -> AccessState
    /// Emits the current state immediately, then on every change.
    func accessUpdates() async -> AsyncStream<AccessState>
}

/// Purchase authority (RevenueCat in production, M06). No parallel StoreKit owner.
public protocol Purchasing: AccessStateProviding {
    func products() async throws(PurchaseFailure) -> [PurchaseProduct]
    func purchase(productID: String) async -> PurchaseOutcome
    func restore() async -> RestoreOutcome
}
