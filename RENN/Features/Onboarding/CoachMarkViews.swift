import SwiftUI
import RENNDomain
import RENNFeatures

/// Views a coach-mark tip can point at. Each is marked in place with `.coachTarget(_:)`.
enum CoachTarget: Hashable {
    case homeCreate
    case homeHero
    case homeProjectsTab
    case looksFilters
    case looksFirstLook
    case projectsFirstTape
    case projectsSelect
    case previewLook
    case previewIndicators
    case previewExport

    /// Round controls get a circular spotlight.
    var isRound: Bool {
        switch self {
        case .homeCreate, .previewLook, .previewIndicators: true
        default: false
        }
    }
}

struct CoachStep {
    let target: CoachTarget
    let title: LocalizedStringKey
    let message: LocalizedStringKey
}

extension CoachTour {
    /// Only the essentials, at most three per screen (owner: "don't overwhelm").
    var steps: [CoachStep] {
        switch self {
        case .home:
            [
                CoachStep(target: .homeCreate, title: "coach.home.create.title", message: "coach.home.create.message"),
                CoachStep(target: .homeHero, title: "coach.home.look.title", message: "coach.home.look.message"),
                CoachStep(target: .homeProjectsTab, title: "coach.home.tapes.title", message: "coach.home.tapes.message"),
            ]
        case .looks:
            [
                CoachStep(target: .looksFirstLook, title: "coach.looks.card.title", message: "coach.looks.card.message"),
                CoachStep(target: .looksFilters, title: "coach.looks.filters.title", message: "coach.looks.filters.message"),
            ]
        case .projects:
            [
                CoachStep(target: .projectsFirstTape, title: "coach.projects.tape.title", message: "coach.projects.tape.message"),
                CoachStep(target: .projectsSelect, title: "coach.projects.select.title", message: "coach.projects.select.message"),
            ]
        case .preview:
            [
                CoachStep(target: .previewLook, title: "coach.preview.look.title", message: "coach.preview.look.message"),
                CoachStep(target: .previewIndicators, title: "coach.preview.indicators.title", message: "coach.preview.indicators.message"),
                CoachStep(target: .previewExport, title: "coach.preview.export.title", message: "coach.preview.export.message"),
            ]
        }
    }
}

extension EnvironmentValues {
    /// App-lifetime coach marks; nil in isolated previews.
    var coachMarks: CoachMarks? {
        get { self[CoachMarksKey.self] }
        set { self[CoachMarksKey.self] = newValue }
    }
}

private struct CoachMarksKey: EnvironmentKey {
    static var defaultValue: CoachMarks? { nil }
}

private struct CoachAnchorsKey: PreferenceKey {
    static var defaultValue: [CoachTarget: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [CoachTarget: Anchor<CGRect>], nextValue: () -> [CoachTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports this view's frame so a tip can spotlight it; nil reports nothing.
    func coachTarget(_ target: CoachTarget?) -> some View {
        anchorPreference(key: CoachAnchorsKey.self, value: .bounds) { anchor in
            target.map { [$0: anchor] } ?? [:]
        }
    }

    /// Draws the active tour above this view (and everything inside it that reports targets).
    func coachMarkHost(_ coachMarks: CoachMarks?) -> some View {
        overlayPreferenceValue(CoachAnchorsKey.self) { anchors in
            if let coachMarks, let tour = coachMarks.activeTour {
                GeometryReader { proxy in
                    CoachMarkOverlay(coachMarks: coachMarks, tour: tour, anchors: anchors, proxy: proxy)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: coachMarks?.activeTour)
    }
}

/// Dimmed screen with a spotlight on the step's target and a tip card beside it. Tapping outside
/// the card moves on; Skip ends every tour. The spotlight glides between steps.
private struct CoachMarkOverlay: View {
    let coachMarks: CoachMarks
    let tour: CoachTour
    let anchors: [CoachTarget: Anchor<CGRect>]
    let proxy: GeometryProxy

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var cardFocused: Bool

    private static let spotPadding: CGFloat = 8
    private static let margin: CGFloat = 16
    private static let gap: CGFloat = 14

    var body: some View {
        let steps = tour.steps
        let index = min(coachMarks.stepIndex, steps.count - 1)
        let step = steps[index]
        let size = proxy.size
        let spot = spotlight(for: step.target, in: size)
        ZStack(alignment: .topLeading) {
            CoachDimShape(hole: spot ?? .zero, radius: radius(step.target, spot))
                .fill(Color.black.opacity(0.68), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture { coachMarks.next() }
                .accessibilityHidden(true)
            if let spot {
                SpotlightRing(radius: radius(step.target, spot), pulses: !reduceMotion)
                    .frame(width: spot.width, height: spot.height)
                    .position(x: spot.midX, y: spot.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            card(step, index: index, count: steps.count, spot: spot, in: size)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.86), value: index)
        .sensoryFeedback(.selection, trigger: index)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { coachMarks.skip() }
        .onAppear { cardFocused = true }
        .onChange(of: index) { _, _ in cardFocused = true }
    }

    // MARK: Geometry

    /// The target's frame with breathing room, or nil when it is missing or off screen (the tip
    /// then shows centered, without a spotlight).
    private func spotlight(for target: CoachTarget, in size: CGSize) -> CGRect? {
        guard let anchor = anchors[target] else { return nil }
        var rect = proxy[anchor].insetBy(dx: -Self.spotPadding, dy: -Self.spotPadding)
        if target.isRound {
            let side = max(rect.width, rect.height)
            rect = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        }
        let bounds = CGRect(origin: .zero, size: size)
        guard rect.width > 0, bounds.contains(CGPoint(x: rect.midX, y: rect.midY)),
              rect.height < size.height * 0.6 else { return nil }
        return rect
    }

    private func radius(_ target: CoachTarget, _ spot: CGRect?) -> CGFloat {
        guard let spot else { return 0 }
        return target.isRound ? spot.width / 2 : min(28, spot.height / 2)
    }

    // MARK: Card

    @ViewBuilder
    private func card(_ step: CoachStep, index: Int, count: Int, spot: CGRect?, in size: CGSize) -> some View {
        let width = min(size.width - Self.margin * 2, 360)
        let centerX = spot?.midX ?? size.width / 2
        let x = min(max(centerX - width / 2, Self.margin), size.width - Self.margin - width)
        let below = spot.map { $0.midY < size.height * 0.5 } ?? true
        let arrowX = min(max(centerX - x, 28), width - 28)
        let content = CoachCard(
            step: step, index: index, count: count, isLast: coachMarks.isLastStep,
            arrow: spot == nil ? nil : (below ? .up : .down), arrowX: arrowX,
            onNext: { coachMarks.next() }, onSkip: { coachMarks.skip() })
            .frame(width: width)
            .accessibilityFocused($cardFocused)
            .id(index)
            .transition(.opacity.combined(with: .offset(y: below ? -6 : 6)))
        VStack(alignment: .leading, spacing: 0) {
            if let spot {
                if below {
                    Color.clear.frame(height: spot.maxY + Self.gap)
                    content
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    content
                    Color.clear.frame(height: size.height - spot.minY + Self.gap)
                }
            } else {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .offset(x: x)
    }
}

/// The tip: VHS-style counter, Skip, title, one or two lines and Next / Got it.
private struct CoachCard: View {
    enum Arrow { case up, down }

    let step: CoachStep
    let index: Int
    let count: Int
    let isLast: Bool
    let arrow: Arrow?
    let arrowX: CGFloat
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(RENNColor.brandRed)
                        .frame(width: 6, height: 6)
                    Text(verbatim: String(format: "%02d/%02d", index + 1, count))
                        .font(RENNFont.pressStart(9, relativeTo: .caption2))
                        .foregroundStyle(RENNColor.brandYellow)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("coach.step \(index + 1) \(count)"))
                Spacer()
                if !isLast {
                    Button(action: onSkip) {
                        Text("coach.skip")
                            .font(RENNFont.roboto(14, medium: true, relativeTo: .subheadline))
                            .foregroundStyle(RENNColor.textSecondary)
                            .frame(minWidth: RENNMetrics.minimumTouchTarget, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach.skip")
                }
            }
            Text(step.title)
                .font(RENNFont.roboto(18, medium: true, relativeTo: .headline))
                .foregroundStyle(RENNColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(step.message)
                .font(RENNFont.roboto(15, relativeTo: .subheadline))
                .foregroundStyle(RENNColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { dot in
                    Capsule()
                        .fill(dot == index ? RENNColor.brandYellow : Color.white.opacity(0.25))
                        .frame(width: dot == index ? 16 : 6, height: 6)
                }
                .accessibilityHidden(true)
                Spacer()
                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text(isLast ? LocalizedStringKey("coach.done") : LocalizedStringKey("coach.next"))
                        if !isLast {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .accessibilityHidden(true)
                        }
                    }
                    .font(RENNFont.roboto(15, medium: true, relativeTo: .subheadline))
                    .foregroundStyle(RENNColor.onPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(RENNColor.brandYellow))
                    .frame(minHeight: RENNMetrics.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(isLast ? "coach.done" : "coach.next")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(RENNColor.glassOpaqueFallback)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10))
        .overlay(alignment: arrow == .down ? .bottomLeading : .topLeading) {
            if let arrow {
                CoachArrow(pointsUp: arrow == .up)
                    .fill(RENNColor.glassOpaqueFallback)
                    .frame(width: 18, height: 9)
                    .offset(x: arrowX - 9, y: arrow == .up ? -8.5 : 8.5)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card")
    }
}

/// Full-screen dim with a rounded hole; the hole's frame animates between steps.
private struct CoachDimShape: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, radius) }
        set {
            hole.animatableData = newValue.first
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}

/// Yellow outline around the spotlight with a soft outward pulse (static under Reduce Motion).
private struct SpotlightRing: View {
    let radius: CGFloat
    let pulses: Bool

    @State private var expanded = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.strokeBorder(RENNColor.brandYellow, lineWidth: 2)
            if pulses {
                shape
                    .strokeBorder(RENNColor.brandYellow.opacity(expanded ? 0 : 0.6), lineWidth: 2)
                    .scaleEffect(expanded ? 1.12 : 1)
            }
        }
        .onAppear {
            guard pulses else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { expanded = true }
        }
    }
}

private struct CoachArrow: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}
