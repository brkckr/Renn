import SwiftUI
import RENNDomain

/// Decorative plan stage (03 M04): one object per product in plan accent colours (monthly amber,
/// annual yellow, lifetime orange). Purely visual: `selectedProductID` is authoritative and the
/// price/CTA update at t = 0; this stage only follows it. Hidden from accessibility and hit-testing.
///
/// Objects are RENN's own simple cassette shapes (development art pending visual review), not
/// copies of reference product art.
struct PaywallStage: View {
    let products: [PurchaseProduct]
    let selectedID: String?
    let accent: (PurchasePlan) -> Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var height: CGFloat { verticalSizeClass == .compact ? 80 : 120 }

    var body: some View {
        HStack(spacing: -height * 0.18) {
            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                let isSelected = product.id == selectedID
                let tilt = index == 0 ? -6.0 : index == products.count - 1 ? 6.0 : 0
                PlanObject(color: accent(product.plan), isSelected: isSelected, reduceMotion: reduceMotion)
                    .frame(width: height * 0.9, height: height * 0.62)
                    // Passive pose: scale 0.92, lifted 8 pt, tilted ±6°; selected settles to rest.
                    .scaleEffect(isSelected || reduceMotion ? 1 : 0.92)
                    .offset(y: isSelected || reduceMotion ? 0 : -8)
                    .rotationEffect(.degrees(isSelected || reduceMotion ? 0 : tilt))
                    .zIndex(isSelected ? 1 : 0)
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.12) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.32),
                        value: isSelected)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height + 32)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// One stage object with its bounded halo. The selected halo rises 0.12 → 0.28 → 0.20 between
/// 180 and 480 ms (peak ≈ 330 ms), then holds: no perpetual pulse.
private struct PlanObject: View {
    let color: Color
    let isSelected: Bool
    let reduceMotion: Bool

    /// (value, duration) for three consecutive halo keyframes. The resting value (last keyframe)
    /// equals the animator's initial value, so the halo holds whether or not the animator keeps
    /// its final keyframe.
    private var haloKeys: [(Double, Double)] {
        switch (isSelected, reduceMotion) {
        case (true, false): [(0.12, 0.18), (0.28, 0.15), (0.20, 0.15)]
        case (true, true): [(0.20, 0.12), (0.20, 0.01), (0.20, 0.01)]
        case (false, _): [(0.0, reduceMotion ? 0.12 : 0.24), (0.0, 0.01), (0.0, 0.01)]
        }
    }

    var body: some View {
        let keys = haloKeys
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .blur(radius: 16)
                .padding(-8)  // Spill stays within 16 pt.
                .keyframeAnimator(initialValue: keys[2].0, trigger: isSelected) { halo, opacity in
                    halo.opacity(opacity)
                } keyframes: { _ in
                    LinearKeyframe(keys[0].0, duration: keys[0].1)
                    CubicKeyframe(keys[1].0, duration: keys[1].1)
                    CubicKeyframe(keys[2].0, duration: keys[2].1)
                }
            cassette
        }
    }

    private var cassette: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: size.height * 0.12, style: .continuous)
                    .fill(RENNColor.glassOpaqueFallback)
                RoundedRectangle(cornerRadius: size.height * 0.12, style: .continuous)
                    .strokeBorder(color, lineWidth: 1.5)
                // Label band and two reel windows.
                VStack(spacing: size.height * 0.08) {
                    Capsule().fill(color).frame(width: size.width * 0.72, height: size.height * 0.16)
                    HStack(spacing: size.width * 0.18) {
                        Circle().strokeBorder(color, lineWidth: 1.5).frame(width: size.height * 0.26)
                        Circle().strokeBorder(color, lineWidth: 1.5).frame(width: size.height * 0.26)
                    }
                }
            }
        }
    }
}
