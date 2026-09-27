import Testing
@testable import RENNDomain

@Suite("Onboarding curved wipe (03 M02)")
struct OnboardingWipeTests {
    @Test func timelineCoversSwapsAndReveals() {
        let start = OnboardingWipe.frame(at: 0)
        #expect(start.cover == 0 && start.reveal == 0 && !start.showsTarget && start.oldCopyOpacity == 1)

        let covered = OnboardingWipe.frame(at: 0.380)
        #expect(covered.cover == 1, "Viewport fully covered at 380 ms")
        #expect(covered.showsTarget, "Page is replaced while covered")
        #expect(covered.oldCopyOpacity == 0 && covered.newCopyOpacity == 0)

        let midReveal = OnboardingWipe.frame(at: 0.600)
        #expect(midReveal.reveal > 0 && midReveal.reveal < 1)
        #expect(midReveal.newCopyOpacity > 0 && midReveal.newCopyOpacity < 1)

        let end = OnboardingWipe.frame(at: 0.760)
        #expect(end.reveal == 1 && end.newCopyOpacity == 1 && end.isFinished)
        #expect(OnboardingWipe.frame(at: 5).isFinished)
    }

    @Test func oldCopyFadesWithinTheFirst100ms() {
        #expect(OnboardingWipe.frame(at: 0.050).oldCopyOpacity == 0.5)
        #expect(OnboardingWipe.frame(at: 0.100).oldCopyOpacity == 0)
    }

    @Test func coverageIsMonotonicAndEdgesSpanTheViewportIncludingCorners() {
        var previous = -1.0
        for step in 0...76 {
            let cover = OnboardingWipe.frame(at: Double(step) / 200).cover
            #expect(cover >= previous)
            previous = cover
        }
        // Start: even the bulging middle is off-screen right; end: even the corners are off-screen left.
        #expect(OnboardingWipe.edgeX(progress: 0) - OnboardingWipe.deflection >= 1)
        #expect(OnboardingWipe.edgeX(progress: 1) <= 0)
    }

    @Test func easingMatchesTheCurveEndpointsAndIsFastEarly() {
        #expect(OnboardingWipe.ease(0) == 0)
        #expect(OnboardingWipe.ease(1) == 1)
        #expect(OnboardingWipe.ease(0.5) > 0.85, "(0.22,1,0.36,1) front-loads motion")
        #expect(abs(OnboardingWipe.cubicBezier(0.3, 0.25, 0.25, 0.75, 0.75) - 0.3) < 1e-4, "Linear control points")
    }
}
