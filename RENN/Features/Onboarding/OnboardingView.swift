import SwiftUI
import RENNDomain
import RENNFeatures

/// Four onboarding pages (02 D03) with the curved colour wipe (03 M02): brown background →
/// page scene and copy → moving curved mask → navigation. The page swaps while fully covered.
/// Reduce Motion uses a 120 ms dissolve. Scene areas are labelled placeholders until the owner's
/// licensed demo scenes arrive, never fake user projects.
struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var headingFocused: Bool
    /// One transition at a time, identified so stale completions are ignored (03 shared rules).
    @State private var transition: Transition?
    /// Page shown when no transition is running.
    @State private var settledIndex = 0

    private struct Transition: Equatable {
        let id = UUID()
        let from: Int
        let to: Int
        let start: Date
    }

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
        TimelineView(.animation(paused: transition == nil)) { context in
            let frame = transition.map { OnboardingWipe.frame(at: context.date.timeIntervalSince($0.start)) }
            let shownIndex = transition.map { (frame?.showsTarget ?? true) ? $0.to : $0.from } ?? settledIndex
            let copyOpacity = frame.map { $0.showsTarget ? $0.newCopyOpacity : $0.oldCopyOpacity } ?? 1
            ZStack {
                page(shownIndex, copyOpacity: copyOpacity)
                if let transition, let frame {
                    CurvedWipeShape(cover: frame.cover, reveal: frame.reveal)
                        .fill(RENNColor.brandSequence[transition.to % 4])
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .onChange(of: viewModel.pageIndex) { old, new in begin(from: old, to: new) }
        .onChange(of: scenePhase) { _, phase in
            // Inactivity settles on the intended page and removes partial masks.
            if phase != .active { settle() }
        }
    }

    private func begin(from old: Int, to new: Int) {
        guard !reduceMotion else {
            withAnimation(RENNMotion.reducedDissolve) { settledIndex = new }
            headingFocused = true
            return
        }
        let started = Transition(from: old, to: new, start: .now)
        transition = started
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(OnboardingWipe.totalDuration))
            guard transition?.id == started.id else { return }
            settle()
        }
    }

    private func settle() {
        transition = nil
        settledIndex = viewModel.pageIndex
        headingFocused = true
    }

    @ViewBuilder
    private func page(_ index: Int, copyOpacity: Double) -> some View {
        let page = Self.pages[index]
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("onboarding.skip") { viewModel.skip() }
                    .accessibilityIdentifier("onboarding.skip")
                    .font(RENNFont.bodyMedium)
                    .foregroundStyle(RENNColor.textSecondary)
                    .frame(minWidth: RENNMetrics.minimumTouchTarget, minHeight: RENNMetrics.minimumTouchTarget)
                    .opacity(viewModel.isLastPage ? 0 : 1)
                    .disabled(viewModel.isLastPage)
                    .accessibilityHidden(viewModel.isLastPage)
            }
            .padding(.horizontal, RENNMetrics.sideMargin)

            OnboardingScenePlaceholder(pageIndex: index)
                .padding(.horizontal, RENNMetrics.sideMargin)
                .padding(.top, 8)

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
            .opacity(copyOpacity)

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                ForEach(0..<viewModel.pageCount, id: \.self) { dot in
                    Capsule()
                        .fill(dot == index ? RENNColor.brandYellow : RENNColor.textSecondary.opacity(0.35))
                        .frame(width: dot == index ? 20 : 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("onboarding.progress \(index + 1) \(viewModel.pageCount)"))
            .padding(.bottom, 20)

            Button {
                viewModel.next()
            } label: {
                Text(viewModel.isLastPage ? LocalizedStringKey("onboarding.getStarted") : LocalizedStringKey("onboarding.next"))
            }
            .accessibilityIdentifier("onboarding.next")
            .buttonStyle(.rennPrimary)
            // A running transition serializes navigation so a double tap cannot skip a page.
            .disabled(transition != nil)
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.bottom, 16)
        }
    }
}

/// The moving band between a leading and a trailing curved edge (03 M02). Each edge is a
/// quadratic curve from top to bottom whose middle bulges left by `OnboardingWipe.deflection`·W,
/// so full coverage at `cover == 1` includes every corner.
private struct CurvedWipeShape: Shape {
    var cover: Double
    var reveal: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(cover, reveal) }
        set { (cover, reveal) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let lead = rect.minX + OnboardingWipe.edgeX(progress: cover) * width
        let trail = rect.minX + OnboardingWipe.edgeX(progress: reveal) * width
        // Quadratic midpoint = (anchor + control) / 2, so the control sits 2 × deflection left.
        let bulge = 2 * OnboardingWipe.deflection * width
        var path = Path()
        path.move(to: CGPoint(x: lead, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: lead, y: rect.maxY), control: CGPoint(x: lead - bulge, y: rect.midY))
        path.addLine(to: CGPoint(x: trail, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: trail, y: rect.minY), control: CGPoint(x: trail - bulge, y: rect.midY))
        path.closeSubpath()
        return path
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
