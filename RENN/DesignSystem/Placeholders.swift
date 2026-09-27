import SwiftUI
import RENNDomain

/// PLACEHOLDER poster for a Look until licensed comparison-scene posters exist (02 D05,
/// 08 I02). Deterministic per Look ID; always carries the fixture badge when the Look
/// is a development fixture.
struct LookPosterPlaceholder: View {
    let look: LookDefinition

    var body: some View {
        let seed = look.id.rawValue.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let color = RENNColor.brandSequence[seed % 4]
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [color.opacity(0.7), RENNColor.glassOpaqueFallback],
                startPoint: .top, endPoint: .bottom)
            // Scanline hint so the placeholder reads as "video", not final art.
            VStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
                }
            }
            if look.isDevelopmentFixture {
                DevelopmentFixtureBadge().padding(6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// PLACEHOLDER upright VHS case shell (02 D08). Final case/sleeve art, the processed-frame
/// print and the player insertion motion arrive with M05/M07. The print color follows the
/// deterministic per-project variant.
struct VHSCaseShell: View {
    let name: String
    let variant: Int
    /// Non-ready states are printed on the case, never hidden (05 V08).
    var status: LocalizedStringKey? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(RENNColor.glassOpaqueFallback)
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(RENNColor.brandSequence[variant % 4])
                    .frame(height: 10)
                // Print window: the project's processed frame goes here (M05).
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .padding(8)
                Text(verbatim: name)
                    .font(RENNFont.roboto(12, medium: true, relativeTo: .caption))
                    .foregroundStyle(RENNColor.textPrimary)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, status == nil ? 8 : 2)
                if let status {
                    Label(status, systemImage: "exclamationmark.triangle.fill")
                        .font(RENNFont.roboto(10, medium: true, relativeTo: .caption2))
                        .foregroundStyle(RENNColor.brandAmber)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                Spacer(minLength: 0)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 6, x: 2, y: 4)
    }
}

/// Section heading in Roboto Medium.
struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(RENNFont.roboto(18, medium: true, relativeTo: .headline))
                .foregroundStyle(RENNColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}
