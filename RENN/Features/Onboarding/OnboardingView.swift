import SwiftUI
import RENNFeatures

/// Four onboarding pages (02 D03). M00 uses a simple dissolve between pages; the curved
/// color wipe (03 M02) and the licensed demo scenes arrive with M07. Scene areas are
/// labelled placeholders, never fake user projects.
struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool

    init(viewModel: @autoclosure () -> OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel())
    }

    private static let pages: [(heading: String, body: String?)] = [
        ("onboarding.page1.heading", nil),
        ("onboarding.page2.heading", "onboarding.page2.body"),
        ("onboarding.page3.heading", "onboarding.page3.body"),
        ("onboarding.page4.heading", "onboarding.page4.body"),
    ]

    var body: some View {
        let page = Self.pages[viewModel.pageIndex]
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("onboarding.skip") { viewModel.skip() }
                    .font(RENNFont.bodyMedium)
                    .foregroundStyle(RENNColor.textSecondary)
                    .frame(minWidth: RENNMetrics.minimumTouchTarget, minHeight: RENNMetrics.minimumTouchTarget)
                    .opacity(viewModel.isLastPage ? 0 : 1)
                    .disabled(viewModel.isLastPage)
                    .accessibilityHidden(viewModel.isLastPage)
            }
            .padding(.horizontal, RENNMetrics.sideMargin)

            OnboardingScenePlaceholder(pageIndex: viewModel.pageIndex)
                .padding(.horizontal, RENNMetrics.sideMargin)
                .padding(.top, 8)
                .id(viewModel.pageIndex)
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(page.heading))
                    .font(RENNFont.roboto(28, medium: true, relativeTo: .largeTitle))
                    .foregroundStyle(RENNColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                if let body = page.body {
                    Text(LocalizedStringKey(body))
                        .font(RENNFont.body)
                        .foregroundStyle(RENNColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.top, 24)
            .id("copy-\(viewModel.pageIndex)")
            .transition(.opacity)

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                ForEach(0..<viewModel.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == viewModel.pageIndex ? RENNColor.brandYellow : RENNColor.textSecondary.opacity(0.35))
                        .frame(width: index == viewModel.pageIndex ? 20 : 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("onboarding.progress \(viewModel.pageIndex + 1) \(viewModel.pageCount)"))
            .padding(.bottom, 20)

            Button {
                viewModel.next()
            } label: {
                Text(viewModel.isLastPage ? LocalizedStringKey("onboarding.getStarted") : LocalizedStringKey("onboarding.next"))
            }
            .buttonStyle(.rennPrimary)
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.bottom, 16)
        }
        .animation(reduceMotion ? RENNMotion.reducedDissolve : .easeInOut(duration: 0.3), value: viewModel.pageIndex)
        .onChange(of: viewModel.pageIndex) { headingFocused = true }
    }
}

/// PLACEHOLDER scene: owned/licensed demo clips are an outstanding owner input (02 D03).
private struct OnboardingScenePlaceholder: View {
    let pageIndex: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: RENNMetrics.panelRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [RENNColor.brandSequence[pageIndex % 4].opacity(0.55), RENNColor.glassOpaqueFallback],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 6) {
                DevelopmentFixtureBadge()
                Text("onboarding.scenePlaceholder")
                    .font(RENNFont.secondary)
                    .foregroundStyle(RENNColor.textPrimary.opacity(0.8))
            }
            .padding(16)
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
