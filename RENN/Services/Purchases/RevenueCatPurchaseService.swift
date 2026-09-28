import Foundation
import RENNDomain
import RevenueCat
import UIKit

/// RevenueCat is the sole transaction owner (06 C03): no parallel StoreKit purchase/finish
/// logic. SDK types are converted into `PurchaseMapping` inputs; the mapping decides access,
/// plans and outcomes (tested without the SDK). Access comes only from the `pro` entitlement,
/// refreshed on launch, foreground, purchase and restore, and follows SDK cache semantics.
///
/// Created only when the owner's public SDK key is configured; otherwise the app uses
/// `UnconfiguredPurchaseService`. No keys, products or accounts are invented here.
actor RevenueCatPurchaseService: Purchasing {
    private var state: AccessState = .notLoaded
    private var broadcaster = StreamBroadcaster<AccessState>()
    /// Packages of the last loaded offering, keyed by product ID, so a purchase uses exactly the
    /// product the user selected (06 C03: captured at purchase tap).
    private var packages: [String: Package] = [:]
    private var observation: Task<Void, Never>?
    private var foreground: NSObjectProtocol?

    /// Configures the SDK once. Must be called before any other use.
    static func configure(apiKey: String, environment: AppConfiguration.Environment) -> RevenueCatPurchaseService {
        Purchases.logLevel = environment == .production ? .warn : .info
        Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey).build())
        let service = RevenueCatPurchaseService()
        Task { await service.start() }
        return service
    }

    private func start() {
        guard observation == nil else { return }
        // The SDK's stream delivers its cached value first, then every change.
        observation = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                await self?.apply(info, fromCache: true)
            }
        }
        foreground = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    /// Fetches current customer information; failures keep the SDK-cached state (no custom grace).
    private func refresh() async {
        guard let info = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) else { return }
        apply(info, fromCache: false)
    }

    private func apply(_ info: CustomerInfo, fromCache: Bool) {
        let next = PurchaseMapping.access(
            activeEntitlements: Set(info.entitlements.active.keys), fromCache: fromCache, checkedAt: Date())
        // A cached value never downgrades a state verified in this session.
        if fromCache, state.provenance == .providerVerified, state.level != next.level { return }
        state = next
        broadcaster.yield(next)
    }

    // MARK: Purchasing

    func currentAccess() async -> AccessState { state }

    func accessUpdates() async -> AsyncStream<AccessState> {
        broadcaster.makeStream(initial: state) { [weak self] token in
            Task { await self?.removeSubscriber(token) }
        }
    }

    private func removeSubscriber(_ token: UUID) {
        broadcaster.remove(token)
    }

    func products() async throws(PurchaseFailure) -> [PurchaseProduct] {
        let offerings: Offerings
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            throw Self.failure(error)
        }
        let available = offerings.current?.availablePackages ?? []
        packages = Dictionary(available.map { ($0.storeProduct.productIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let products = PurchaseMapping.products(from: available.map { package in
            PurchaseMapping.OfferedPackage(
                productID: package.storeProduct.productIdentifier,
                kind: Self.kind(package.packageType),
                localizedPrice: package.storeProduct.localizedPriceString)
        })
        guard !products.isEmpty else { throw .productsUnavailable }
        return products
    }

    func purchase(productID: String) async -> PurchaseOutcome {
        guard let package = packages[productID] else { return .failed(.productsUnavailable) }
        let result: PurchaseMapping.TransactionResult
        do {
            let data = try await Purchases.shared.purchase(package: package)
            if data.userCancelled {
                result = .userCancelled
            } else {
                apply(data.customerInfo, fromCache: false)
                result = .completed(activeEntitlements: Set(data.customerInfo.entitlements.active.keys))
            }
        } catch let error as ErrorCode where error == .paymentPendingError {
            result = .pending
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            result = .userCancelled
        } catch {
            result = .failed(Self.failure(error))
        }
        return PurchaseMapping.outcome(result, checkedAt: Date())
    }

    func restore() async -> RestoreOutcome {
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info, fromCache: false)
            return PurchaseMapping.restoreOutcome(
                activeEntitlements: Set(info.entitlements.active.keys), checkedAt: Date())
        } catch {
            return .failed(Self.failure(error))
        }
    }

    // MARK: Mapping SDK types

    private static func kind(_ type: PackageType) -> PurchaseMapping.OfferedPackage.Kind {
        switch type {
        case .monthly: .monthly
        case .annual: .annual
        case .lifetime: .lifetime
        default: .other
        }
    }

    /// Typed error codes only; SDK messages never leave the adapter (06 C05).
    private static func failure(_ error: any Error) -> PurchaseFailure {
        guard let code = error as? ErrorCode else { return .unknown }
        switch code {
        case .networkError: return .network
        case .storeProblemError, .purchaseNotAllowedError, .purchaseInvalidError, .productNotAvailableForPurchaseError:
            return .store
        case .configurationError, .invalidCredentialsError: return .notConfigured
        default: return .unknown
        }
    }
}
