import SwiftUI
import RENNDomain
import RENNFeatures

/// Drag handles over the Indicators panel preview (owner-approved free placement, 2026-09-30).
/// Each handle sits on the frame `IndicatorLayout` resolves for the staged settings and the same
/// reservations as the rendered preview (Free watermark, Dual-Cam inset), so what is dragged is
/// what preview and export draw. Centres snap to the margin edges and the centre lines with a
/// selection haptic; VoiceOver gets Move up/down/left/right actions.
struct IndicatorDragLayer: View {
    @Binding var draft: IndicatorsDraft
    let baseSettings: IndicatorSettings
    let sourceDimensions: PixelDimensions?
    let showsWatermark: Bool
    /// Dual-Cam inset corner when the source is a Dual-Cam preview.
    let dualCorner: DualCameraLayout.Corner?

    /// Canvas centre of the indicator when its drag began.
    @State private var dragStart: [IndicatorLayout.Kind: CGPoint] = [:]
    @State private var snapX: CGFloat?
    @State private var snapY: CGFloat?
    @State private var snapTick = 0

    /// Snap distance in points.
    private static let snapDistance: CGFloat = 8
    /// VoiceOver step, as a fraction of the frame.
    private static let accessibilityStep = 0.05
    /// The watermark's width/height, measured once from the real renderer.
    private static let watermarkAspect = WatermarkRenderer.render(width: 240)?.aspectRatio ?? 4

    var body: some View {
        GeometryReader { geometry in
            if let dimensions = sourceDimensions,
               let output = canvas(dimensions, in: geometry.size) {
                let origin = CGPoint(
                    x: ((geometry.size.width - CGFloat(output.width)) / 2).rounded(),
                    y: ((geometry.size.height - CGFloat(output.height)) / 2).rounded())
                let layout = IndicatorLayout.resolve(
                    output: output, settings: draft.applied(to: baseSettings), reserved: reserved(output))
                ZStack(alignment: .topLeading) {
                    guides(output: output, origin: origin)
                    ForEach(layout.indicators, id: \.kind) { placed in
                        handle(placed, output: output, origin: origin)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: snapTick)
    }

    // MARK: Geometry

    /// The aspect-fitted preview area in points, as the renderer letterboxes it.
    private func canvas(_ dimensions: PixelDimensions, in size: CGSize) -> PixelDimensions? {
        let fit = PreviewRenderer.aspectFit(dimensions, in: size)
        return try? PixelDimensions(width: Int(fit.width), height: Int(fit.height))
    }

    private func reserved(_ output: PixelDimensions) -> [WatermarkLayout.Rect] {
        let inset = dualCorner.map { DualInsetLayout(canvas: output, corner: $0) }
        var rects: [WatermarkLayout.Rect] = []
        if showsWatermark {
            rects.append(WatermarkLayout(
                output: output, aspectRatio: Self.watermarkAspect,
                reservedBottomRight: inset?.reservedBottomRight(canvas: output) ?? 0).frame)
        }
        if let inset { rects.append(inset.frame) }
        return rects
    }

    // MARK: Handles

    private func handle(_ placed: IndicatorLayout.Placed, output: PixelDimensions, origin: CGPoint) -> some View {
        let frame = placed.frame
        let centre = CGPoint(x: CGFloat(frame.x + frame.width / 2), y: CGFloat(frame.y + frame.height / 2))
        let isDragging = dragStart[placed.kind] != nil
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(
                RENNColor.brandYellow.opacity(isDragging ? 1 : 0.7),
                style: StrokeStyle(lineWidth: isDragging ? 1.5 : 1, dash: [3, 3]))
            .background(Color.white.opacity(isDragging ? 0.08 : 0.001))
            .frame(width: CGFloat(frame.width) + 12, height: CGFloat(frame.height) + 12)
            .contentShape(Rectangle())
            .position(x: origin.x + centre.x, y: origin.y + centre.y)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart[placed.kind] ?? centre
                        if dragStart[placed.kind] == nil { dragStart[placed.kind] = start }
                        move(
                            placed.kind,
                            to: CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height),
                            output: output)
                    }
                    .onEnded { _ in
                        dragStart[placed.kind] = nil
                        snapX = nil
                        snapY = nil
                    })
            .accessibilityElement()
            .accessibilityLabel(Text(title(placed.kind)))
            .accessibilityHint(Text("indicators.dragHint"))
            .accessibilityAction(named: Text("indicators.move.up")) { nudge(placed.kind, centre, output, dx: 0, dy: -1) }
            .accessibilityAction(named: Text("indicators.move.down")) { nudge(placed.kind, centre, output, dx: 0, dy: 1) }
            .accessibilityAction(named: Text("indicators.move.left")) { nudge(placed.kind, centre, output, dx: -1, dy: 0) }
            .accessibilityAction(named: Text("indicators.move.right")) { nudge(placed.kind, centre, output, dx: 1, dy: 0) }
    }

    /// Stores the dragged centre, snapped to the margin edges or the centre lines when close.
    private func move(_ kind: IndicatorLayout.Kind, to point: CGPoint, output: PixelDimensions) {
        let width = CGFloat(output.width)
        let height = CGFloat(output.height)
        let margin = (CGFloat(output.shortEdge) * IndicatorLayout.marginFraction).rounded()
        let size = IndicatorLayout.size(kind, output: output)
        let halfWidth = CGFloat(size.width) / 2
        let halfHeight = CGFloat(size.height) / 2
        let xs: [CGFloat] = [margin + halfWidth, width / 2, width - margin - halfWidth]
        let ys: [CGFloat] = [margin + halfHeight, height / 2, height - margin - halfHeight]
        let newSnapX = xs.first { abs($0 - point.x) < Self.snapDistance }
        let newSnapY = ys.first { abs($0 - point.y) < Self.snapDistance }
        if (newSnapX != nil && newSnapX != snapX) || (newSnapY != nil && newSnapY != snapY) { snapTick += 1 }
        snapX = newSnapX
        snapY = newSnapY
        let x = newSnapX ?? point.x
        let y = newSnapY ?? point.y
        draft.move(kind, to: IndicatorPosition(x: Double(x / width), y: Double(y / height)))
    }

    private func nudge(_ kind: IndicatorLayout.Kind, _ centre: CGPoint, _ output: PixelDimensions, dx: Double, dy: Double) {
        let x = Double(centre.x) / Double(output.width) + dx * Self.accessibilityStep
        let y = Double(centre.y) / Double(output.height) + dy * Self.accessibilityStep
        draft.move(kind, to: IndicatorPosition(x: x, y: y))
    }

    /// Centre guides while an indicator is snapped to a centre line.
    @ViewBuilder
    private func guides(output: PixelDimensions, origin: CGPoint) -> some View {
        let width = CGFloat(output.width)
        let height = CGFloat(output.height)
        if let snapX, abs(snapX - width / 2) < 0.5 {
            Rectangle()
                .fill(RENNColor.brandYellow.opacity(0.6))
                .frame(width: 1, height: height)
                .position(x: origin.x + width / 2, y: origin.y + height / 2)
                .accessibilityHidden(true)
        }
        if let snapY, abs(snapY - height / 2) < 0.5 {
            Rectangle()
                .fill(RENNColor.brandYellow.opacity(0.6))
                .frame(width: width, height: 1)
                .position(x: origin.x + width / 2, y: origin.y + height / 2)
                .accessibilityHidden(true)
        }
    }

    private func title(_ kind: IndicatorLayout.Kind) -> LocalizedStringKey {
        switch kind {
        case .rec: "indicators.rec"
        case .play: "indicators.play"
        case .battery: "indicators.battery"
        case .date: "indicators.date"
        }
    }
}
