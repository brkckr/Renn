import SwiftUI
import RENNDomain
import RENNFeatures

/// Home (02 D04): small RENN brand, one recommended-Look hero, last-four Looks when
/// available, recent project cases with See all. Creation lives in +, not in the hero.
struct HomeView: View {
    let viewModel: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RENNWordmark(size: 22)
                    .padding(.top, 8)

                recommendedSection

                if !viewModel.recentLooks.isEmpty {
                    recentLooksSection
                }

                projectsSection
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .task { await viewModel.observe() }
    }

    @ViewBuilder
    private var recommendedSection: some View {
        switch viewModel.catalogState {
        case .loading:
            RoundedRectangle(cornerRadius: RENNMetrics.panelRadius, style: .continuous)
                .fill(RENNColor.glassOpaqueFallback)
                .frame(height: 220)
                .overlay(ProgressView())
        case .failed:
            Label(
                "home.catalogError",
                systemImage: "exclamationmark.triangle")
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textSecondary)
        case .loaded:
            if let look = viewModel.recommendedLook {
                Button {
                    viewModel.inspect(look.id)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        LookPosterPlaceholder(look: look)
                            .frame(height: 200)
                            .clipped()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("home.recommended")
                                .font(RENNFont.secondary)
                                .foregroundStyle(RENNColor.brandYellow)
                            Text(LocalizedStringKey(look.nameKey))
                                .font(RENNFont.heading)
                                .foregroundStyle(RENNColor.textPrimary)
                            Text(LocalizedStringKey(look.descriptionKey))
                                .font(RENNFont.secondary)
                                .foregroundStyle(RENNColor.textSecondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .glassBackground(cornerRadius: RENNMetrics.panelRadius)
                    .clipShape(RoundedRectangle(cornerRadius: RENNMetrics.panelRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("home.recommended.hint"))
            }
        }
    }

    private var recentLooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "home.recentLooks")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(viewModel.recentLooks) { look in
                        Button {
                            viewModel.inspect(look.id)
                        } label: {
                            Text(LocalizedStringKey(look.nameKey))
                                .font(RENNFont.roboto(14, medium: true, relativeTo: .subheadline))
                                .foregroundStyle(RENNColor.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .glassBackground(Capsule())
                                .frame(minHeight: RENNMetrics.minimumTouchTarget)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "home.recentTapes") {
                if !viewModel.recentProjects.isEmpty {
                    Button("home.seeAll") { viewModel.seeAll() }
                        .font(RENNFont.roboto(14, medium: true, relativeTo: .subheadline))
                        .foregroundStyle(RENNColor.brandYellow)
                        .frame(minHeight: RENNMetrics.minimumTouchTarget)
                }
            }
            if viewModel.showsFirstUsePrompt {
                VStack(alignment: .leading, spacing: 6) {
                    Text("home.firstUse.title")
                        .font(RENNFont.bodyMedium)
                        .foregroundStyle(RENNColor.textPrimary)
                    Text("home.firstUse.body")
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassBackground(cornerRadius: RENNMetrics.cardRadius)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(viewModel.recentProjects) { project in
                        Button {
                            viewModel.open(project.id)
                        } label: {
                            VHSCaseShell(
                                name: project.name.value,
                                variant: ProjectsViewModel.caseVariant(for: project.id))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text(verbatim: project.name.value))
                    }
                    ForEach(0..<max(0, HomeViewModel.maximumRecentProjects - viewModel.recentProjects.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
