import SwiftUI
import RENNFeatures

/// Compact Look inspection sheet (02 D05): example, name/description, Favorite and
/// Create with this Look. Dismissing clears the intent without creating anything.
struct LookInspectionView: View {
    @State private var viewModel: LookInspectionViewModel

    init(viewModel: @autoclosure () -> LookInspectionViewModel) {
        _viewModel = State(initialValue: viewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                CloseButton { viewModel.close() }
            }
            if let look = viewModel.look {
                LookPosterPlaceholder(look: look)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: RENNMetrics.cardRadius, style: .continuous))
                Text(LocalizedStringKey(look.nameKey))
                    .font(RENNFont.heading)
                    .foregroundStyle(RENNColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(LocalizedStringKey(look.descriptionKey))
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                Spacer(minLength: 0)
                Button {
                    Task { await viewModel.toggleFavorite() }
                } label: {
                    Label(
                        viewModel.isFavorite ? LocalizedStringKey("look.unfavorite") : LocalizedStringKey("look.favorite"),
                        systemImage: viewModel.isFavorite ? "heart.fill" : "heart")
                }
                .buttonStyle(.rennSecondary)
                Button("look.createWithThis") { viewModel.createWithThisLook() }
                    .buttonStyle(.rennPrimary)
            } else if viewModel.loadFailed {
                Text("look.unavailable")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                Spacer()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(RENNMetrics.sideMargin)
        .background(RENNColor.backgroundBase.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(RENNColor.backgroundBase)
        .task { await viewModel.load() }
    }
}
