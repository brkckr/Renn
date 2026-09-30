import SwiftUI
import RENNDomain
import RENNFeatures

/// Looks catalog tab (02 D05): heading, chips, 3-column 3:4 grid. No paid badges or locks.
struct LooksView: View {
    @Bindable var viewModel: LooksViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        switch dynamicTypeSize {
        case .accessibility3, .accessibility4, .accessibility5: 1
        case _ where dynamicTypeSize.isAccessibilitySize: 2
        default: 3
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("looks.title")
                    .font(RENNFont.heading)
                    .foregroundStyle(RENNColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)

                if viewModel.isDevelopmentCatalog {
                    HStack(alignment: .top, spacing: 8) {
                        DevelopmentFixtureBadge()
                        Text("looks.developmentCatalog \(viewModel.lookCount) \(LookCatalog.requiredLaunchLookCount)")
                            .font(RENNFont.secondary)
                            .foregroundStyle(RENNColor.textSecondary)
                    }
                }

                chips

                content
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .task { await viewModel.observe() }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.filters, id: \.self) { filter in
                    let isSelected = viewModel.filter == filter
                    Button {
                        viewModel.filter = filter
                    } label: {
                        Text(title(for: filter))
                            .font(RENNFont.roboto(14, medium: true, relativeTo: .subheadline))
                            .foregroundStyle(isSelected ? RENNColor.onPrimary : RENNColor.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(isSelected ? RENNColor.brandYellow : Color.white.opacity(0.08)))
                            .frame(minHeight: RENNMetrics.minimumTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        case .failed:
            VStack(spacing: 12) {
                Text("looks.loadError")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                Button("common.retry") { Task { await viewModel.retry() } }
                    .buttonStyle(.rennSecondary)
            }
        case .loaded:
            if viewModel.visibleLooks.isEmpty {
                Text(viewModel.filter == .favorites ? LocalizedStringKey("looks.favoritesEmpty") : LocalizedStringKey("looks.empty"))
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columnCount),
                    spacing: 16
                ) {
                    ForEach(viewModel.visibleLooks) { look in
                        Button {
                            viewModel.inspect(look.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                LookPoster(look: look)
                                    .aspectRatio(3 / 4, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        if viewModel.isFavorite(look.id) {
                                            RENNIcon.favoriteFilled.image
                                                .font(.system(size: 12))
                                                .foregroundStyle(RENNColor.brandRed)
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
                        .accessibilityHint(Text("looks.card.hint"))
                    }
                }
            }
        }
    }

    private func title(for filter: LooksViewModel.Filter) -> LocalizedStringKey {
        switch filter {
        case .all: "looks.filter.all"
        case .favorites: "looks.filter.favorites"
        case .family(let family):
            // Built as a plain String so the family ID is part of the key, not an argument.
            LocalizedStringKey("look.family." + family)
        }
    }
}
