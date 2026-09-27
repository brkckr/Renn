import AVFoundation
import RENNDomain

/// Runtime Dual-Cam probe. M00 checks only `isMultiCamSupported`; M04 adds the validated
/// front/rear format-pair check. Device marketing names are never used (00, 07).
struct DeviceCaptureCapabilities: CaptureCapabilityProviding {
    func dualCameraAvailability() -> DualCameraAvailability {
        AVCaptureMultiCamSession.isMultiCamSupported ? .supported : .unsupported(.hardwareNotSupported)
    }
}
