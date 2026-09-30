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
        RENNSheet(title, size: .panel, onClose: { viewModel.close() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let look = viewModel.look {
                        LookPoster(look: look)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: RENNMetrics.cardRadius, style: .continuous))
                        Text(LocalizedStringKey(look.descriptionKey))
                            .font(RENNFont.body)
                            .foregroundStyle(RENNColor.textSecondary)
                    } else if viewModel.loadFailed {
                        Text("look.unavailable")
                            .font(RENNFont.body)
                            .foregroundStyle(RENNColor.textSecondary)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(.horizontal, RENNMetrics.sideMargin)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        } actions: {
            if viewModel.look != nil {
                Button("look.createWithThis") { viewModel.createWithThisLook() }
                    .buttonStyle(.rennPrimary)
                Button {
                    Task { await viewModel.toggleFavorite() }
                } label: {
                    Label(
                        viewModel.isFavorite ? LocalizedStringKey("look.unfavorite") : LocalizedStringKey("look.favorite"),
                        systemImage: viewModel.isFavorite ? "heart.fill" : "heart")
                }
                .buttonStyle(.rennSecondary)
            }
        }
        .task { await viewModel.load() }
    }

    private var title: LocalizedStringKey {
        viewModel.look.map { LocalizedStringKey($0.nameKey) } ?? "looks.title"
    }
}
