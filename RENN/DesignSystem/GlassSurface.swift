import SwiftUI

/// Glass material surface (02 D01). Blurs content behind the surface, never its own
/// text/icons. Reduce Transparency uses the opaque fallback; Increase Contrast strengthens
/// the border.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(RENNColor.glassOpaqueFallback)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(RENNColor.glassTint)
            }
            shape.strokeBorder(Color.white.opacity(contrast == .increased ? 0.4 : 0.12), lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: RENNColor.glassShadow, radius: 20, x: 0, y: 8)
    }
}

extension View {
    func glassBackground<S: InsettableShape>(_ shape: S) -> some View {
        background(GlassSurface(shape: shape))
    }

    func glassBackground(cornerRadius: CGFloat) -> some View {
        background(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}
