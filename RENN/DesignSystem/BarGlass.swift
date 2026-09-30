import SwiftUI

/// Material for the bottom tab bar and its + button only (owner-approved native tab bar
/// look). On iOS 26 it is the system Liquid Glass, which handles Reduce Transparency and
/// Increase Contrast itself; earlier systems keep the RENN glass surface (02 D01).
/// Other screens keep `glassBackground`. Not the interactive variant: inside a Button its own
/// touch tracking can compete with the button's tap (a CI UI test saw one tap on + leave the
/// menu closed); the + press motion is `PressScaleButtonStyle` (03 M03).
private struct BarGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(Glass.regular, in: shape)
        } else {
            content.background(GlassSurface(shape: shape))
        }
        #else
        content.background(GlassSurface(shape: shape))
        #endif
    }
}

extension View {
    func barGlass<S: InsettableShape>(_ shape: S) -> some View {
        modifier(BarGlassModifier(shape: shape))
    }
}
