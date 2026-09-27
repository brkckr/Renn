import SwiftUI
import RENNDomain
import RENNFeatures

/// Projects tab: upper retro player, shelf divider and a three-column collection of
/// upright VHS cases (02 D08). M00 uses placeholder vector shells; the layered player art,
/// processed-frame prints, rename/delete menu and insertion motion (03 M05) come later.
struct ProjectsView: View {
    let viewModel: ProjectsViewModel

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                PlayerPlaceholder()
                    .frame(height: min(proxy.size.height * 0.28, 200))
                    .padding(.horizontal, RENNMetrics.sideMargin)
                    .padding(.top, 8)
                // Shelf divider separating the player from the collection.
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.top, 12)
                collection
            }
        }
        .task { await viewModel.observe() }
    }

    @ViewBuilder
    private var collection: some View {
        if !viewModel.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Text("projects.empty.title")
                    .font(RENNFont.heading)
                    .foregroundStyle(RENNColor.textPrimary)
                Text("projects.empty.body")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("projects.empty.cta") { viewModel.createFirstTape() }
                    .buttonStyle(.rennPrimary)
                    .padding(.top, 8)
                Spacer()
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                    spacing: 20
                ) {
                    ForEach(viewModel.projects) { project in
                        Button {
                            viewModel.open(project.id)
                        } label: {
                            VHSCaseShell(
                                name: project.name.value,
                                variant: ProjectsViewModel.caseVariant(for: project.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: project.name.value))
                        .accessibilityHint(Text("projects.case.hint"))
                    }
                }
                .padding(.horizontal, RENNMetrics.sideMargin)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// PLACEHOLDER vector player. Final original/licensed rear/front/slot layers are an
/// outstanding owner input (08 I02). Decorative buttons have no function.
private struct PlayerPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: 0x1E1B18))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.horizontal, 24)
                // Thin horizontal slot.
                Capsule()
                    .fill(Color.black)
                    .frame(width: 120, height: 6)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 10, height: 10)
                    }
                    Spacer()
                    Circle().fill(RENNColor.brandRed.opacity(0.8)).frame(width: 8, height: 8)
                }
                .padding(.horizontal, 28)
            }
            .padding(.vertical, 16)
        }
        .aspectRatio(1.25, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) { DevelopmentFixtureBadge().padding(10) }
        .accessibilityHidden(true)
    }
}
