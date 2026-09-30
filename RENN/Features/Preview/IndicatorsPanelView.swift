import SwiftUI
import RENNDomain
import RENNFeatures

/// On-screen Indicators panel (02 D06): aspect-correct preview up to 240 pt, four rows,
/// Gregorian date-only picker when Date is on, Turn all off, staged Apply (✕ or swipe cancels).
struct IndicatorsPanelView: View {
    let engine: RenderEngine
    let source: any PreviewFrameSource
    let recipe: Recipe
    let sourceDimensions: PixelDimensions?
    let showsWatermark: Bool
    let onApply: (IndicatorsDraft) -> Void
    let onCancel: () -> Void

    @State private var draft: IndicatorsDraft

    init(
        engine: RenderEngine, source: any PreviewFrameSource, recipe: Recipe, sourceDimensions: PixelDimensions?,
        showsWatermark: Bool, onApply: @escaping (IndicatorsDraft) -> Void, onCancel: @escaping () -> Void
    ) {
        self.engine = engine
        self.source = source
        self.recipe = recipe
        self.sourceDimensions = sourceDimensions
        self.showsWatermark = showsWatermark
        self.onApply = onApply
        self.onCancel = onCancel
        _draft = State(initialValue: IndicatorsDraft(recipe.indicators))
    }

    var body: some View {
        RENNSheet("indicators.title", size: .full, onClose: onCancel) {
            ScrollView {
                VStack(spacing: 12) {
                    MetalPreviewView(
                        engine: engine, source: source, recipe: stagedRecipe, sourceDimensions: sourceDimensions,
                        showsWatermark: showsWatermark, bypassCreative: false)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: RENNMetrics.cardRadius, style: .continuous))
                        .accessibilityHidden(true)
                    row("indicators.rec", isOn: $draft.showsRec)
                    row("indicators.play", isOn: $draft.showsPlay)
                    row("indicators.battery", isOn: $draft.showsBattery)
                    row("indicators.date", isOn: $draft.showsDate)
                    if draft.showsDate {
                        DatePicker(
                            selection: dateBinding, in: Self.dateRange, displayedComponents: .date
                        ) {
                            Text("indicators.dateValue")
                        }
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                        .tint(RENNColor.brandYellow)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .glassBackground(cornerRadius: RENNMetrics.cardRadius)
                    }
                }
                .padding(.horizontal, RENNMetrics.sideMargin)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        } actions: {
            Button("indicators.apply") { onApply(draft) }
                .buttonStyle(.rennPrimary)
            Button("indicators.turnAllOff") { draft.turnAllOff() }
                .buttonStyle(.rennSecondary)
                .disabled(!draft.anyOn)
        }
    }

    private var stagedRecipe: Recipe {
        var staged = recipe
        staged.indicators = draft.applied(to: recipe.indicators)
        return staged
    }

    private func row(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(RENNFont.body)
                .foregroundStyle(RENNColor.textPrimary)
        }
        .tint(RENNColor.brandYellow)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .glassBackground(cornerRadius: RENNMetrics.cardRadius)
    }

    /// The picker works in the current calendar day; the stamp stores only Y/M/D.
    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.year = draft.stampDate.year
                components.month = draft.stampDate.month
                components.day = draft.stampDate.day
                components.hour = 12
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                return calendar.date(from: components) ?? Date()
            },
            set: { draft.setDate($0, timeZone: .current) })
    }

    private static let dateRange: ClosedRange<Date> = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let lower = calendar.date(from: DateComponents(year: 1, month: 1, day: 1, hour: 12)) ?? .distantPast
        let upper = calendar.date(from: DateComponents(year: 9999, month: 12, day: 31, hour: 12)) ?? .distantFuture
        return lower...upper
    }()
}
