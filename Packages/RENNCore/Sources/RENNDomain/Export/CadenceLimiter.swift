/// Decides which source frames to keep so output cadence never exceeds the policy rate,
/// without interpolating motion or retiming kept frames (01 P08, 05 V01).
///
/// Timing policy (M02 ADR 0003): kept frames keep their original presentation timestamps.
/// A frame is kept when its timestamp reaches the next slot of an output grid anchored at the
/// first frame; slot tolerance is an eighth of the output interval, so jittered/VFR input still keeps
/// one frame per slot. CFR input that already fits the rate keeps every frame.
/// Audio is untouched, so duration and pitch are preserved.
public struct CadenceLimiter: Sendable {
    public let outputRate: FrameRate
    private var nextSlot: RationalTime?
    private var slotIndex: Int64 = 0
    private var origin: RationalTime?

    public init(outputRate: FrameRate) {
        self.outputRate = outputRate
    }

    /// Call once per decoded frame in presentation order.
    public mutating func shouldKeep(presentationTime pts: RationalTime) -> Bool {
        guard let origin else {
            self.origin = pts
            slotIndex = 1
            return true
        }
        // Slot k starts at origin + k / rate. Keep if pts >= slotStart - tolerance, measured
        // exactly in eighth-slot units: floor((pts - origin) * rate * 8).
        guard let elapsed = Self.eighthSlots(pts, minus: origin, rate: outputRate) else { return false }
        if elapsed >= 8 * slotIndex - 1 {
            // Advance to the slot after the one this frame fills (skip slots with no frames).
            slotIndex = max(slotIndex + 1, (elapsed + 1) / 8 + 1)
            return true
        }
        return false
    }

    /// floor((pts - origin) * rate * 8) using exact integer math; nil if pts < origin.
    static func eighthSlots(_ pts: RationalTime, minus origin: RationalTime, rate: FrameRate) -> Int64? {
        // (a/b - c/d) = (a*d - c*b) / (b*d)
        let numerator = pts.value.multipliedReportingOverflow(by: Int64(origin.timescale))
        let subtrahend = origin.value.multipliedReportingOverflow(by: Int64(pts.timescale))
        guard !numerator.overflow, !subtrahend.overflow else { return nil }
        let delta = numerator.partialValue - subtrahend.partialValue
        guard delta >= 0 else { return nil }
        let denominator = Int64(pts.timescale) * Int64(origin.timescale)
        let scaled = delta.multipliedReportingOverflow(by: Int64(rate.frames) * 8)
        guard !scaled.overflow else { return nil }
        return scaled.partialValue / (denominator * Int64(rate.seconds))
    }
}
