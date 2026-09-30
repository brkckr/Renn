import Observation
import RENNDomain

/// RENN Pro paywall state (02 D09, 03 M04, 06 C03/C04). `selectedProductID` is the
/// authoritative selection; animation never changes billing data. Only a verified
/// `.granted` outcome can unlock Pro.
@MainActor
@Observable
public final class PaywallViewModel {
    public enum LoadState: Equatable, Sendable {
        case loading
        /// Show retry / restore / continue Free, never a hardcoded price.
        case unavailable(PurchaseFailure)
        case ready([PurchaseProduct])
    }

    public enum PurchaseState: Equatable, Sendable {
        case idle
        case purchasing(productID: String)
        case pending
        case cancelled
        case failed(PurchaseFailure)
        case granted
    }

    public private(set) var loadState: LoadState = .loading
    public private(set) var selectedProductID: String?
    public private(set) var purchaseState: PurchaseState = .idle
    public private(set) var access: AccessState = .notLoaded
    public private(set) var isRestoring = false

    public let reason: PaywallReason
    private let purchases: any Purchasing
    private let telemetry: any TelemetryRecording
    private let onClose: @MainActor () -> Void
    private let onGranted: @MainActor () -> Void

    public init(
        reason: PaywallReason,
        purchases: any Purchasing,
        telemetry: any TelemetryRecording,
        onClose: @escaping @MainActor () -> Void,
        onGranted: @escaping @MainActor () -> Void
    ) {
        self.reason = reason
        self.purchases = purchases
        self.telemetry = telemetry
        self.onClose = onClose
        self.onGranted = onGranted
    }

    public var products: [PurchaseProduct] {
        if case .ready(let products) = loadState { return products }
        return []
    }

    public var selectedProduct: PurchaseProduct? {
        products.first { $0.id == selectedProductID }
    }

    public var isPurchasing: Bool {
        if case .purchasing = purchaseState { return true }
        return false
    }

    /// Existing Pro must not be asked to buy the same access again (06 C04).
    public var isAlreadyPro: Bool { access.effectiveTier == .pro }

    public var canPurchase: Bool {
        selectedProduct != nil && !isPurchasing && !isAlreadyPro && !isRestoring
    }

    public func load() async {
        access = await purchases.currentAccess()
        await telemetry.record(.paywallShown(placement: reason.telemetryPlacement))
        await loadProducts()
    }

    public func retry() async {
        await loadProducts()
    }

    /// Last selection wins; locked while a Store transaction is active.
    public func select(_ productID: String) {
        guard !isPurchasing, products.contains(where: { $0.id == productID }) else { return }
        selectedProductID = productID
    }

    public func purchase() async {
        // Snapshot the product at tap time so UI and purchase always agree.
        guard canPurchase, let product = selectedProduct else { return }
        purchaseState = .purchasing(productID: product.id)
        await telemetry.record(.purchaseStarted(plan: product.plan))
        let outcome = await purchases.purchase(productID: product.id)
        switch outcome {
        case .granted(let state):
            access = state
            purchaseState = state.effectiveTier == .pro ? .granted : .failed(.unknown)
        case .pending:
            purchaseState = .pending
        case .cancelled:
            purchaseState = .cancelled
        case .failed(let failure):
            purchaseState = .failed(failure)
        }
        await telemetry.record(.purchaseFinished(plan: product.plan, result: outcome.telemetryResult))
        if purchaseState == .granted {
            onGranted()
        }
    }

    public func restore() async {
        guard !isRestoring, !isPurchasing else { return }
        isRestoring = true
        defer { isRestoring = false }
        let outcome = await purchases.restore()
        switch outcome {
        case .restored(let state), .nothingToRestore(let state):
            access = state
            await telemetry.record(.restoreFinished(tier: state.effectiveTier))
            if state.effectiveTier == .pro { onGranted() }
        case .failed(let failure):
            purchaseState = .failed(failure)
        }
    }

    public func close() {
        onClose()
    }

    private func loadProducts() async {
        loadState = .loading
        do {
            let loaded = try await purchases.products()
            guard !loaded.isEmpty else {
                loadState = .unavailable(.productsUnavailable)
                return
            }
            let ordered = loaded.sorted { $0.plan.displayOrder < $1.plan.displayOrder }
            loadState = .ready(ordered)
            if selectedProductID == nil || !ordered.contains(where: { $0.id == selectedProductID }) {
                // Baseline: annual when available, otherwise the first product. Never auto-purchase.
                selectedProductID = (ordered.first { $0.plan == .annual } ?? ordered.first)?.id
            }
        } catch {
            loadState = .unavailable(error)
        }
    }
}

extension PurchasePlan {
    var displayOrder: Int {
        switch self {
        case .monthly: 0
        case .annual: 1
        case .lifetime: 2
        }
    }
}

extension PaywallReason {
    var telemetryPlacement: TelemetryEvent.PaywallPlacement {
        switch self {
        case .settings: .settings
        case .exportUpgrade: .exportUpgrade
        case .freeDurationLimit: .freeDurationLimit
        case .home: .home
        }
    }
}

extension PurchaseOutcome {
    var telemetryResult: TelemetryEvent.PurchaseResult {
        switch self {
        case .granted: .granted
        case .pending: .pending
        case .cancelled: .cancelled
        case .failed: .failed
        }
    }
}
