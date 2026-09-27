import SwiftUI
import RENNDomain

/// Monoton RENN wordmark with the four brand glyph colors (R yellow, E amber, N orange,
/// N red). Used for small in-app branding and the watermark phrase. The splash uses a
/// different, stripe-aligned treatment (02 D03).
struct RENNWordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array("RENN".enumerated()), id: \.offset) { index, glyph in
                Text(String(glyph))
                    .foregroundStyle(RENNColor.brandSequence[index])
            }
        }
        .font(RENNFont.monoton(size))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: AppIdentity.displayName))
    }
}

/// Visible marker for development fixtures so they are never mistaken for final content.
struct DevelopmentFixtureBadge: View {
    var body: some View {
        Text("fixture.badge")
            .font(RENNFont.roboto(11, medium: true, relativeTo: .caption2))
            .foregroundStyle(RENNColor.onPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(RENNColor.brandAmber))
            .accessibilityLabel(Text("fixture.badge.accessibility"))
    }
}
