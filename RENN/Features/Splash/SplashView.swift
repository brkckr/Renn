import SwiftUI

/// In-app animated splash (02 D03, 03 M01). The system launch screen is a static brown
/// background (UILaunchScreen); motion starts here. Geometry and timing are the contract's
/// starting values and still need visual review against references/splash.jpg.
struct SplashView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ribbonProgress: CGFloat = 0
    @State private var logoOpacity: Double = 0
    @State private var didFinish = false

    /// Combined stripe width as a fraction of W, and where the bend begins as a fraction of H.
    private let stripeWidthFraction: CGFloat = 0.40
    private let bendFraction: CGFloat = 0.70

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let stripeWidth = size.width * stripeWidthFraction / 4
            let startX = (size.width - stripeWidth * 4) / 2
            ZStack(alignment: .topLeading) {
                RENNColor.backgroundBase
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        SplashRibbon(index: index, stripeWidthFraction: stripeWidthFraction, bendFraction: bendFraction)
                            .fill(RENNColor.brandSequence[index])
                    }
                }
                .mask(alignment: .top) {
                    // Reveal top-to-bottom along the bent ribbons; the shapes themselves stay put.
                    Rectangle().frame(height: size.height * ribbonProgress)
                }
                // Each glyph is centered on its own stripe (not the watermark treatment).
                ZStack {
                    ForEach(Array("RENN".enumerated()), id: \.offset) { index, glyph in
                        Text(String(glyph))
                            .font(RENNFont.monoton(stripeWidth * 0.9, relativeTo: .largeTitle))
                            .foregroundStyle(Color.white)  // Owner decision (2026-09-28): white glyphs, overriding the dark-brown baseline.
                            .frame(width: stripeWidth)
                            .position(x: startX + stripeWidth * (CGFloat(index) + 0.5), y: size.height / 2)
                    }
                }
                .opacity(logoOpacity)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "RENN"))
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            ribbonProgress = 1
            logoOpacity = 1
            try? await Task.sleep(for: .milliseconds(600))
        } else {
            // 0–800 ms ribbons, 300–700 ms logo, 800–1100 ms settle.
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.8)) { ribbonProgress = 1 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.4)) { logoOpacity = 1 }
            try? await Task.sleep(for: .milliseconds(800))
        }
        guard !Task.isCancelled, !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

/// One vertical ribbon that runs straight down, then bends outward to the bottom edge,
/// fanning the four stripes across the full width as in the reference.
struct SplashRibbon: Shape {
    let index: Int
    let stripeWidthFraction: CGFloat
    let bendFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let stripeWidth = rect.width * stripeWidthFraction / 4
        let startX = rect.minX + (rect.width - stripeWidth * 4) / 2
        let left = startX + stripeWidth * CGFloat(index)
        let right = left + stripeWidth
        let bendY = rect.minY + rect.height * bendFraction
        // Map the stripe edges at the bend onto the full width at the bottom edge.
        let bottomLeft = rect.minX + rect.width * CGFloat(index) / 4
        let bottomRight = rect.minX + rect.width * CGFloat(index + 1) / 4

        var path = Path()
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: bendY))
        path.addLine(to: CGPoint(x: bottomLeft, y: rect.maxY))
        path.addLine(to: CGPoint(x: bottomRight, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: bendY))
        path.addLine(to: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
