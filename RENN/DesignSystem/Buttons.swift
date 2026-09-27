import SwiftUI

/// Primary CTA: yellow, dark-brown Roboto Medium 16, height 52, radius 16 (02 D01).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RENNFont.button)
            .foregroundStyle(RENNColor.onPrimary)
            .frame(maxWidth: .infinity, minHeight: RENNMetrics.primaryButtonHeight)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: RENNMetrics.primaryButtonRadius, style: .continuous)
                    .fill(RENNColor.brandYellow.opacity(isEnabled ? 1 : 0.4)))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: RENNMetrics.primaryButtonRadius, style: .continuous))
    }
}

/// Secondary: glass surface, off-white text.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RENNFont.button)
            .foregroundStyle(RENNColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: RENNMetrics.primaryButtonHeight)
            .padding(.horizontal, 16)
            .glassBackground(cornerRadius: RENNMetrics.primaryButtonRadius)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: RENNMetrics.primaryButtonRadius, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var rennPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var rennSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
