/// Settled product identity (README, 01 P01, 06 C01). Used by tests that guard the
/// Xcode build settings and by provider adapters that must register the same identity.
public enum AppIdentity {
    public static let displayName = "RENN"
    public static let bundleIdentifier = "tzlapp.studio.renn"
    /// RevenueCat entitlement granted by the monthly, annual and lifetime products (06 C02).
    public static let proEntitlementID = "pro"
    /// Exact Free watermark phrase (01 P08, 02 D07).
    public static let watermarkPhrase = "shot by RENN"
}
