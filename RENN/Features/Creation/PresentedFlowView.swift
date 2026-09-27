import SwiftUI
import RENNDomain
import RENNFeatures

/// Routes a presented flow to its screen. Camera, import and preview are M00 placeholders:
/// the one-Look media vertical slice (M02) replaces them with real capture/import/preview.
struct PresentedFlowView: View {
    let flow: PresentedFlow
    let composition: AppComposition

    var body: some View {
        @Bindable var router = composition.router
        flowContent
            .sheet(item: $router.nestedPaywall) { reason in
                PaywallView(
                    viewModel: composition.makeNestedPaywallViewModel(reason: reason),
                    termsURL: composition.configuration.termsURL,
                    privacyURL: composition.configuration.privacyURL)
                    .environment(\.locale, composition.localization.locale)
            }
    }

    @ViewBuilder
    private var flowContent: some View {
        switch flow {
        case .camera(let lookID):
            CameraView(parts: composition.makeCameraParts(lookID: lookID), engine: composition.renderEngine)
        case .dualCamera(let lookID):
            DualCameraView(parts: composition.makeDualCameraParts(lookID: lookID), engine: composition.renderEngine)
        case .dualCameraUnavailable(let reason, let lookID):
            DualCameraUnavailableView(
                reason: reason,
                onRecordWithOneCamera: { composition.router.replaceFlow(with: .camera(lookID: lookID)) },
                onImport: { composition.router.replaceFlow(with: .importVideo(lookID: lookID)) },
                onClose: { composition.router.dismissFlow() })
        case .importVideo(let lookID):
            ImportFlowView(viewModel: composition.makeImportFlowViewModel(lookID: lookID))
        case .projectPreview(let projectID):
            ProjectPreviewView(
                viewModel: composition.makeProjectPreviewViewModel(projectID: projectID),
                engine: composition.renderEngine)
        case .paywall(let reason):
            PaywallView(
                viewModel: composition.makePaywallViewModel(reason: reason),
                termsURL: composition.configuration.termsURL,
                privacyURL: composition.configuration.privacyURL)
        }
    }
}

/// Unsupported Dual-Cam explains the reason and offers normal camera/import, never a
/// paywall (01 P05, 06 C06).
struct DualCameraUnavailableView: View {
    let reason: DualCameraUnsupportedReason
    let onRecordWithOneCamera: () -> Void
    let onImport: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            RENNColor.backgroundBase.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    CloseButton(action: onClose)
                }
                Spacer()
                RENNIcon.recordBothCameras.image
                    .font(.system(size: 40))
                    .foregroundStyle(RENNColor.brandAmber)
                    .accessibilityHidden(true)
                Text("dual.unavailable.title")
                    .font(RENNFont.heading)
                    .foregroundStyle(RENNColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(reason == .hardwareNotSupported
                    ? LocalizedStringKey("dual.unavailable.hardware")
                    : LocalizedStringKey("dual.unavailable.formats"))
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                Spacer()
                Button("creation.record.title", action: onRecordWithOneCamera)
                    .buttonStyle(.rennPrimary)
                Button("creation.import.title", action: onImport)
                    .buttonStyle(.rennSecondary)
            }
            .padding(RENNMetrics.sideMargin)
        }
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RENNIcon.close.image
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(RENNColor.textPrimary)
                .frame(width: RENNMetrics.minimumTouchTarget, height: RENNMetrics.minimumTouchTarget)
                .glassBackground(Circle())
        }
        .accessibilityLabel(Text("common.close"))
    }
}
