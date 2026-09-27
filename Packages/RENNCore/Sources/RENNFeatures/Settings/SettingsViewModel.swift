import Observation
import RENNDomain

/// App-wide settings only: no Look/Beat/video-indicator controls (01 P10, 02 D09).
@MainActor
@Observable
public final class SettingsViewModel {
    public enum RestoreState: Equatable, Sendable {
        case idle
        case restoring
        case restored
        case nothingToRestore
        case failed(PurchaseFailure)
    }

    public private(set) var access: AccessState = .notLoaded
    public private(set) var language: AppLanguage
    public private(set) var diagnosticsConsent: DiagnosticsConsent
    public private(set) var restoreState: RestoreState = .idle
    /// Nil until measured, or when no storage provider is configured.
    public private(set) var storage: StorageUsage?
    public private(set) var isClearingCache = false

    private let purchases: any Purchasing
    private let preferencesStore: any AppPreferencesStoring
    private let storageUsage: (any StorageUsageProviding)?
    private let onLanguageChange: @MainActor (AppLanguage) -> Void
    private let onShowPaywall: @MainActor () -> Void

    public init(
        purchases: any Purchasing,
        preferencesStore: any AppPreferencesStoring,
        storageUsage: (any StorageUsageProviding)? = nil,
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        onShowPaywall: @escaping @MainActor () -> Void
    ) {
        self.purchases = purchases
        self.preferencesStore = preferencesStore
        self.storageUsage = storageUsage
        self.onLanguageChange = onLanguageChange
        self.onShowPaywall = onShowPaywall
        let preferences = preferencesStore.load()
        language = preferences.language
        diagnosticsConsent = preferences.diagnosticsConsent
    }

    public var isPro: Bool { access.effectiveTier == .pro }

    public func observe() async {
        for await state in await purchases.accessUpdates() {
            access = state
        }
    }

    public func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        var preferences = preferencesStore.load()
        preferences.language = newLanguage
        preferencesStore.save(preferences)
        onLanguageChange(newLanguage)
    }

    /// Optional diagnostics; declining never changes features (06 C05).
    public func setDiagnosticsEnabled(_ enabled: Bool) {
        let consent: DiagnosticsConsent = enabled ? .granted : .declined
        guard consent != diagnosticsConsent else { return }
        diagnosticsConsent = consent
        var preferences = preferencesStore.load()
        preferences.diagnosticsConsent = consent
        preferencesStore.save(preferences)
    }

    public func refreshStorage() async {
        guard let storageUsage else { return }
        storage = await storageUsage.usage()
    }

    /// Clears regenerable cache (posters); projects are untouched. Repeated taps are ignored.
    public func clearCache() async {
        guard let storageUsage, !isClearingCache else { return }
        isClearingCache = true
        await storageUsage.clearCache()
        storage = await storageUsage.usage()
        isClearingCache = false
    }

    public func showPaywall() {
        guard !isPro else { return }
        onShowPaywall()
    }

    /// Restore is always reachable (06 C03). Repeated taps while restoring are ignored.
    public func restorePurchases() async {
        guard restoreState != .restoring else { return }
        restoreState = .restoring
        switch await purchases.restore() {
        case .restored(let state):
            access = state
            restoreState = state.effectiveTier == .pro ? .restored : .nothingToRestore
        case .nothingToRestore(let state):
            access = state
            restoreState = .nothingToRestore
        case .failed(let failure):
            restoreState = .failed(failure)
        }
    }
}
