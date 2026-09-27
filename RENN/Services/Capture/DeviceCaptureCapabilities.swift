import AVFoundation
import RENNDomain

/// Runtime Dual-Cam probe (05 V03): multi-cam support, then a validated front/rear format pair
/// from the wide-angle cameras' actual formats. Device marketing names are never used (00, 07).
/// Session hardware cost is checked when the dual session is configured.
struct DeviceCaptureCapabilities: CaptureCapabilityProviding {
    func dualCameraAvailability() -> DualCameraAvailability {
        guard AVCaptureMultiCamSession.isMultiCamSupported else { return .unsupported(.hardwareNotSupported) }
        return Self.dualFormatPair() == nil ? .unsupported(.noCompatibleFormats) : .supported
    }

    static func dualFormatPair() -> DualFormatSelection.Pair? {
        guard let rear = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else { return nil }
        return DualFormatSelection.select(rear: candidates(rear), front: candidates(front))
    }

    static func candidates(_ device: AVCaptureDevice) -> [DualFormatSelection.Candidate] {
        device.formats.enumerated().compactMap { index, format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard let dimensions = try? PixelDimensions(width: Int(size.width), height: Int(size.height)) else { return nil }
            let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return DualFormatSelection.Candidate(
                index: index, dimensions: dimensions, maximumFrameRate: maxRate,
                isMultiCamSupported: format.isMultiCamSupported)
        }
    }
}
