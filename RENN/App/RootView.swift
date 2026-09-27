import SwiftUI
import RENNFeatures

/// Launch phase switch: animated splash -> onboarding (first use) -> main shell.
struct RootView: View {
    let composition: AppComposition

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
                OnboardingView(viewModel: composition.makeOnboardingViewModel())
                    .transition(.opacity)
            case .main:
                MainShellView(composition: composition)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: composition.router.launchPhase)
        .environment(\.locale, composition.localization.locale)
        .preferredColorScheme(.dark)
        .tint(RENNColor.brandYellow)
    }
}
