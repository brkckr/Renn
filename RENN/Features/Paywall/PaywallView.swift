import SwiftUI
import RENNDomain
import RENNFeatures

/// RENN Pro paywall (02 D09, 06 C04). Prices come only from the Store/provider; when
/// products are unavailable it offers retry / restore / continue Free. The animated
/// three-object selection stage (03 M04) is added in M07.
struct PaywallView: View {
    @State private var viewModel: PaywallViewModel
    /// Owner-hosted documents; nil until supplied (08 I04). Shown disabled, never faked.
    let termsURL: URL?
    let privacyURL: URL?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: @autoclosure () -> PaywallViewModel, termsURL: URL?, privacyURL: URL?) {
        _viewModel = State(initialValue: viewModel())
        self.termsURL = termsURL
        self.privacyURL = privacyURL
    }

    var body: some View {
        ZStack {
            RENNColor.backgroundBase.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    CloseButton { viewModel.close() }
                }
                .padding(.horizontal, RENNMetrics.sideMargin)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        benefits
                        plans
                    }
                    .padding(.horizontal, RENNMetrics.sideMargin)
                    .padding(.bottom, 16)
                }

                footer
                    .padding(.horizontal, RENNMetrics.sideMargin)
                    .padding(.bottom, 8)
            }
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RENNWordmark(size: 26)
                Text(verbatim: "Pro")
                    .font(RENNFont.roboto(22, medium: true, relativeTo: .title2))
                    .foregroundStyle(RENNColor.brandYellow)
                RENNIcon.crown.image
                    .foregroundStyle(RENNColor.brandYellow)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if viewModel.isAlreadyPro {
                Text("paywall.alreadyPro")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
            }
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            benefit("paywall.benefit.duration")
            benefit("paywall.benefit.quality")
            benefit("paywall.benefit.watermark")
            Text("paywall.freeReminder")
                .font(RENNFont.secondary)
                .foregroundStyle(RENNColor.textSecondary)
                .padding(.top, 4)
        }
    }

    private func benefit(_ key: LocalizedStringKey) -> some View {
        Label {
            Text(key).font(RENNFont.body).foregroundStyle(RENNColor.textPrimary)
        } icon: {
            Image(systemName: "checkmark").foregroundStyle(RENNColor.brandYellow)
        }
    }

    @ViewBuilder
    private var plans: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        case .unavailable(let failure):
            VStack(alignment: .leading, spacing: 12) {
                Text(failure == .notConfigured
                     ? LocalizedStringKey("paywall.unavailable.notConfigured")
                     : LocalizedStringKey("paywall.unavailable.generic"))
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                Button("common.retry") { Task { await viewModel.retry() } }
                    .buttonStyle(.rennSecondary)
            }
            .padding(16)
            .glassBackground(cornerRadius: RENNMetrics.cardRadius)
        case .ready(let products):
            VStack(spacing: 10) {
                ForEach(products) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: PurchaseProduct) -> some View {
        let isSelected = product.id == viewModel.selectedProductID
        let accent = accentColor(for: product.plan)
        return Button {
            viewModel.select(product.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? accent : RENNColor.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(planTitle(product.plan))
                        .font(RENNFont.bodyMedium)
                        .foregroundStyle(RENNColor.textPrimary)
                    Text(planPeriod(product.plan))
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.textSecondary)
                }
                Spacer()
                // Store-localized price; for annual this is the full yearly total.
                Text(verbatim: product.localizedPrice)
                    .font(RENNFont.bodyMedium)
                    .foregroundStyle(RENNColor.textPrimary)
            }
            .padding(16)
            .frame(minHeight: 64)
            .glassBackground(cornerRadius: RENNMetrics.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: RENNMetrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: RENNMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPurchasing)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .animation(reduceMotion ? RENNMotion.reducedDissolve : RENNMotion.emphasized, value: isSelected)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let message = statusMessage {
                Text(message)
                    .font(RENNFont.secondary)
                    .foregroundStyle(RENNColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await viewModel.purchase() }
            } label: {
                if viewModel.isPurchasing {
                    ProgressView().tint(RENNColor.onPrimary)
                } else {
                    Text("paywall.cta")
                }
            }
            .buttonStyle(.rennPrimary)
            .disabled(!viewModel.canPurchase)

            HStack(spacing: 16) {
                Button("paywall.restore") { Task { await viewModel.restore() } }
                    .disabled(viewModel.isRestoring || viewModel.isPurchasing)
                Button("settings.terms") { if let termsURL { openURL(termsURL) } }
                    .disabled(termsURL == nil)
                Button("settings.privacyPolicy") { if let privacyURL { openURL(privacyURL) } }
                    .disabled(privacyURL == nil)
            }
            .font(RENNFont.secondary)
            .foregroundStyle(RENNColor.textSecondary)
            .frame(minHeight: RENNMetrics.minimumTouchTarget)
        }
    }

    private var statusMessage: LocalizedStringKey? {
        switch viewModel.purchaseState {
        case .idle, .purchasing, .granted: nil
        case .pending: "paywall.status.pending"
        case .cancelled: "paywall.status.cancelled"
        case .failed(.notConfigured): "paywall.unavailable.notConfigured"
        case .failed: "paywall.status.failed"
        }
    }

    /// Proposed accents: monthly amber, annual yellow, lifetime orange (03 M04).
    private func accentColor(for plan: PurchasePlan) -> Color {
        switch plan {
        case .monthly: RENNColor.brandAmber
        case .annual: RENNColor.brandYellow
        case .lifetime: RENNColor.brandOrange
        }
    }

    private func planTitle(_ plan: PurchasePlan) -> LocalizedStringKey {
        switch plan {
        case .monthly: "paywall.plan.monthly"
        case .annual: "paywall.plan.annual"
        case .lifetime: "paywall.plan.lifetime"
        }
    }

    private func planPeriod(_ plan: PurchasePlan) -> LocalizedStringKey {
        switch plan {
        case .monthly: "paywall.period.monthly"
        case .annual: "paywall.period.annual"
        case .lifetime: "paywall.period.lifetime"
        }
    }
}
