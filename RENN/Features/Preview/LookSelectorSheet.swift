import SwiftUI
import RENNDomain
import RENNFeatures

/// Camera/preview Look selector (02 D05 S10): the catalog grid with a selected outline + check,
/// one intensity slider and staged Apply (✕ or swipe cancels, RENNSheet). No global tabs or Create button. The preview
/// behind the sheet renders the staged choice; nothing is saved until Apply.
struct LookSelectorSheet: View {
    let looks: [LookDefinition]
    let selection: LookSelection
    let onSelect: (LookID) -> Void
    let onIntensity: (Double) -> Void
    let onApply: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        dynamicTypeSize >= .accessibility3 ? 1 : dynamicTypeSize >= .xxLarge ? 2 : 3
    }

    var body: some View {
        RENNSheet("lookSelector.title", size: .panel, onClose: onCancel) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columnCount),
                        spacing: 16
                    ) {
                        ForEach(looks) { look in
                            card(look)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("preview.intensity")
                            .font(RENNFont.secondary)
                            .foregroundStyle(RENNColor.textSecondary)
                        Slider(value: Binding(get: { selection.intensity }, set: onIntensity), in: 0...1)
                            .tint(RENNColor.brandYellow)
                            .accessibilityLabel(Text("preview.intensity"))
                    }
                }
                .padding(.horizontal, RENNMetrics.sideMargin)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        } actions: {
            Button("indicators.apply", action: onApply)
                .buttonStyle(.rennPrimary)
        }
        // The preview behind stays live while the sheet is at half height.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func card(_ look: LookDefinition) -> some View {
        let isSelected = selection.lookID == look.id
        return Button {
            onSelect(look.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                LookPoster(look: look)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    // Selected: 2 pt yellow inner outline + check, never a coloured cover (02 D05).
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(RENNColor.brandYellow, lineWidth: 2)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(RENNColor.brandYellow)
                                .padding(6)
                                .accessibilityHidden(true)
                        }
                    }
                Text(LocalizedStringKey(look.nameKey))
                    .font(RENNFont.roboto(13, medium: true, relativeTo: .footnote))
                    .foregroundStyle(RENNColor.textPrimary)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
