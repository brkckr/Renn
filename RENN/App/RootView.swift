import SwiftUI
import RENNDomain
import RENNFeatures

/// Launch phase switch: animated splash -> onboarding (first use) -> main shell.
struct RootView: View {
    let composition: AppComposition
    /// Get started's red wipe: onboarding covered the screen; this reveals Home (owner-approved).
    @State private var exitRevealStart: Date?

    var body: some View {
        ZStack {
            RENNColor.backgroundBase.ignoresSafeArea()
            switch composition.router.launchPhase {
            case .splash:
                SplashView {
                    composition.router.finishSplash(hasCompletedOnboarding: composition.hasCompletedOnboarding)
                }
                .transition(.opacity)
            case .onboarding:
                OnboardingView(
                    viewModel: composition.makeOnboardingViewModel(),
                    onExitCovered: { exitRevealStart = .now })
                    .transition(.opacity)
            case .main:
                MainShellView(composition: composition)
                    .transition(.opacity)
            }
            if let start = exitRevealStart {
                TimelineView(.animation) { context in
                    let frame = OnboardingWipe.frame(
                        at: OnboardingWipe.coverDuration + context.date.timeIntervalSince(start))
                    CurvedWipeShape(cover: frame.cover, reveal: frame.reveal)
                        .fill(RENNColor.brandSequence[OnboardingWipe.colorIndex(leaving: OnboardingPager.pageCount - 1)])
                        .ignoresSafeArea()
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                // Appears fully covering in the same update as the phase change: no fade.
                .transition(.identity)
                .task(id: start) {
                    try? await Task.sleep(for: .seconds(OnboardingWipe.totalDuration - OnboardingWipe.coverDuration))
                    if exitRevealStart == start { exitRevealStart = nil }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: composition.router.launchPhase)
        .environment(\.locale, composition.localization.locale)
        .environment(\.showcase, composition.showcase)
        .preferredColorScheme(.dark)
        .tint(RENNColor.brandYellow)
    }
}
