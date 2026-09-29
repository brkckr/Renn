import SwiftUI

/// Material for the bottom tab bar and its + button only (owner-approved native tab bar
/// look). On iOS 26 it is the system Liquid Glass, which handles Reduce Transparency and
/// Increase Contrast itself; earlier systems keep the RENN glass surface (02 D01).
/// Other screens keep `glassBackground`.
private struct BarGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            content.background(GlassSurface(shape: shape))
        }
        #else
        content.background(GlassSurface(shape: shape))
        #endif
    }
}

extension View {
    func barGlass<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(BarGlassModifier(shape: shape, interactive: interactive))
    }
}
