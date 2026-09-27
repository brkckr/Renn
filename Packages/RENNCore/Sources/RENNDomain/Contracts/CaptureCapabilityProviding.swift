/// Runtime Dual-Cam capability (01 P05). Unsupported configurations explain the reason and
/// offer normal camera/import, never a paywall.
public enum DualCameraAvailability: Sendable, Equatable {
    case supported
    case unsupported(DualCameraUnsupportedReason)
}

public enum DualCameraUnsupportedReason: String, Sendable, Equatable {
    /// The device/OS reports no multi-camera support (includes the Simulator).
    case hardwareNotSupported
    /// Supported hardware but no validated front/rear format pair (M04).
    case noCompatibleFormats
}

public protocol CaptureCapabilityProviding: Sendable {
    func dualCameraAvailability() -> DualCameraAvailability
}
