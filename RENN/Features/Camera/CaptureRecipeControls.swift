import SwiftUI
import RENNDomain
import RENNFeatures

/// Pre-record Look / Beat / Indicators access on the camera (02 D06). Shown only while the
/// camera is ready; the draft refuses changes from countdown until the take is finalized.
struct CaptureRecipeControls: View {
    let draft: RecipeDraftEditor
    let isSilent: Bool
    let engine: RenderEngine
    let source: any PreviewFrameSource

    @State private var showsBeat = false
    @State private var showsIndicators = false

    var body: some View {
        HStack(spacing: 12) {
            control("sparkles", label: "lookSelector.title") { draft.openLookSelector() }
            control("waveform", label: "preview.beat", isOn: draft.recipe?.beat.isEnabled == true) { showsBeat = true }
            control("calendar.badge.clock", label: "indicators.title", isOn: indicatorsOn) { showsIndicators = true }
        }
        .sheet(isPresented: lookBinding) {
            if let selection = draft.lookSelection {
                LookSelectorSheet(
                    looks: draft.catalog?.looks ?? [],
                    selection: selection,
                    onSelect: { draft.stageLook($0) },
                    onIntensity: { draft.stageIntensity($0) },
                    onApply: { draft.applyLookSelection() },
                    onCancel: { draft.cancelLookSelection() })
            }
        }
        .sheet(isPresented: $showsBeat) {
            CaptureBeatSheet(draft: draft, isSilent: isSilent)
        }
        .sheet(isPresented: $showsIndicators) {
            if let recipe = draft.recipe {
                IndicatorsPanelView(
                    engine: engine, source: source, recipe: recipe,
                    sourceDimensions: try? PixelDimensions(width: 1080, height: 1920), showsWatermark: false,
                    onApply: { staged in
                        draft.applyIndicators(staged)
                        showsIndicators = false
                    },
                    onCancel: { showsIndicators = false })
            }
        }
    }

    private var indicatorsOn: Bool {
        guard let indicators = draft.recipe?.indicators else { return false }
        return indicators.showsRec || indicators.showsPlay || indicators.showsBattery || indicators.showsDate
    }

    private var lookBinding: Binding<Bool> {
        Binding(get: { draft.lookSelection != nil }, set: { if !$0 { draft.cancelLookSelection() } })
    }

    private func control(_ symbol: String, label: LocalizedStringKey, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isOn ? RENNColor.onPrimary : RENNColor.textPrimary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(isOn ? RENNColor.brandYellow : Color.white.opacity(0.12)))
        }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Beat before recording: enable + intensity only, with the audio source explained (02 D05 S11).
/// Changes apply live, so the sheet has only ✕ (RENNSheet).
struct CaptureBeatSheet: View {
    let draft: RecipeDraftEditor
    let isSilent: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RENNSheet("preview.beat", size: .overCamera, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: Binding(get: { draft.recipe?.beat.isEnabled ?? false }, set: { draft.setBeatEnabled($0) })) {
                    Text("preview.beat")
                        .font(RENNFont.body)
                        .foregroundStyle(RENNColor.textPrimary)
                }
                .tint(RENNColor.brandYellow)
                VStack(alignment: .leading, spacing: 6) {
                    Text("preview.beatIntensity")
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.textSecondary)
                    Slider(
                        value: Binding(get: { draft.recipe?.beat.intensity ?? 0 }, set: { draft.setBeatIntensity($0) }),
                        in: 0...1)
                        .tint(RENNColor.brandYellow)
                        .accessibilityLabel(Text("preview.beatIntensity"))
                        .disabled(draft.recipe?.beat.isEnabled != true)
                }
                // Beat follows only the take's own recorded sound (01 P06).
                Text(isSilent ? LocalizedStringKey("camera.beat.silent") : LocalizedStringKey("preview.beat.source"))
                    .font(RENNFont.secondary)
                    .foregroundStyle(RENNColor.textSecondary)
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.top, 8)
        }
    }
}
