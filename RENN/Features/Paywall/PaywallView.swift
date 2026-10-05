import SwiftUI
import RENNDomain
import RENNFeatures

/// RENN Pro paywall (02 D09, 06 C04), owner-approved layout (2026-09-30): a full-width before/after
/// hero over the street demo (drag the divider to compare; swipe for other Looks), the benefits,
/// three stacked plans, a fixed Continue, the auto-renewal disclosure and centred Restore · Terms ·
/// Privacy. Prices come only from the Store/provider; when products are unavailable it offers retry,
/// restore or continuing Free. The selection is authoritative at once; no decoration delays it.
/// A free trial (owner-approved, annual, 2026-10-05) is shown only when the Store offers one and
/// this user is eligible: a badge on the plan, "Start free trial" and the trial terms.
struct PaywallView: View {
    @State private var viewModel: PaywallViewModel
    /// Owner-hosted documents; nil until supplied (08 I04). Shown disabled, never faked.
    let termsURL: URL?
    let privacyURL: URL?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    init(viewModel: @autoclosure () -> PaywallViewModel, termsURL: URL?, privacyURL: URL?) {
        _viewModel = State(initialValue: viewModel())
        self.termsURL = termsURL
        self.privacyURL = privacyURL
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RENNColor.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    PaywallCompareHero()
                        .frame(height: 420)
                    VStack(alignment: .leading, spacing: 18) {
                        benefits
                        plans
                    }
                    .padding(.horizontal, RENNMetrics.sideMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
                    .padding(.horizontal, RENNMetrics.sideMargin)
                    .padding(.top, 10)
                    .background(RENNColor.backgroundBase.ignoresSafeArea())
            }
            closeButton
                .padding(.leading, 12)
                .padding(.top, 4)
        }
        .task { await viewModel.load() }
    }

    // MARK: Close

    /// Small translucent close over the hero (owner's choice B): blurred circle, 44 pt target.
    private var closeButton: some View {
        Button { viewModel.close() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .background(Color.black.opacity(0.2), in: Circle())
                .frame(width: RENNMetrics.minimumTouchTarget, height: RENNMetrics.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("common.close"))
        .accessibilityIdentifier("paywall.close")
    }

    // MARK: Benefits

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 9) {
            if viewModel.isAlreadyPro {
                Text("paywall.alreadyPro")
                    .font(RENNFont.bodyMedium)
                    .foregroundStyle(RENNColor.brandYellow)
            }
            benefit("paywall.freeReminder")
            benefit("paywall.benefit.duration")
            benefit("paywall.benefit.quality")
            benefit("paywall.benefit.watermark")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(RENNColor.brandYellow)
                .frame(width: 20, height: 20)
                .background(RENNColor.brandYellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            Text(key)
                .font(RENNFont.roboto(15, relativeTo: .subheadline))
                .foregroundStyle(RENNColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Plans

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
            VStack(spacing: 9) {
                ForEach(products) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: PurchaseProduct) -> some View {
        let isSelected = product.id == viewModel.selectedProductID
        return Button {
            viewModel.select(product.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(planTitle(product.plan))
                            .font(RENNFont.roboto(15, medium: true, relativeTo: .headline))
                            .textCase(.uppercase)
                            .kerning(0.6)
                            .foregroundStyle(isSelected ? RENNColor.brandYellow : RENNColor.textPrimary)
                        if let trial = product.freeTrial {
                            Text("paywall.trial.badge \(Self.duration(trial, locale: locale))")
                                .font(RENNFont.roboto(10.5, medium: true, relativeTo: .caption2))
                                .textCase(.uppercase)
                                .kerning(0.4)
                                .foregroundStyle(RENNColor.onPrimary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(RENNColor.brandYellow))
                                .lineLimit(1)
                        }
                    }
                    Text(planPeriod(product.plan))
                        .font(RENNFont.roboto(12.5, relativeTo: .caption))
                        .foregroundStyle(RENNColor.textSecondary)
                }
                Spacer(minLength: 8)
                // Store-localized price; for annual this is the full yearly total.
                Text(verbatim: product.localizedPrice)
                    .font(RENNFont.roboto(16, medium: true, relativeTo: .headline))
                    .foregroundStyle(RENNColor.textPrimary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0x171411).opacity(isSelected ? 0.6 : 0.45)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? RENNColor.brandYellow : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1))
            .shadow(color: isSelected ? RENNColor.brandYellow.opacity(0.28) : .clear, radius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPurchasing)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .animation(reduceMotion ? RENNMotion.reducedDissolve : RENNMotion.emphasized, value: isSelected)
    }

    // MARK: Footer

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
                    HStack {
                        Spacer()
                        Text(viewModel.selectedFreeTrial == nil ? LocalizedStringKey("paywall.cta") : LocalizedStringKey("paywall.cta.trial"))
                        Spacer()
                    }
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.rennPrimary)
            .disabled(!viewModel.canPurchase)

            // A trial's terms sit right under the button that starts it: how long it is free, what it
            // costs after, and how to avoid the charge.
            if let trial = viewModel.selectedFreeTrial, let product = viewModel.selectedProduct {
                Text(trialTerms(trial, product: product))
                    .font(RENNFont.roboto(12, medium: true, relativeTo: .caption))
                    .foregroundStyle(RENNColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Required with auto-renewing subscriptions (App Store): renewal terms at the point of sale.
            Text("paywall.renewalDisclosure")
                .font(RENNFont.roboto(10.5, relativeTo: .caption2))
                .foregroundStyle(RENNColor.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button("paywall.restore") { Task { await viewModel.restore() } }
                    .disabled(viewModel.isRestoring || viewModel.isPurchasing)
                Text(verbatim: "·").accessibilityHidden(true)
                Button("settings.terms") { if let termsURL { openURL(termsURL) } }
                    .disabled(termsURL == nil)
                Text(verbatim: "·").accessibilityHidden(true)
                Button("settings.privacyPolicy") { if let privacyURL { openURL(privacyURL) } }
                    .disabled(privacyURL == nil)
            }
            .font(RENNFont.secondary)
            .foregroundStyle(RENNColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: RENNMetrics.minimumTouchTarget)
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

    private func trialTerms(_ trial: FreeTrial, product: PurchaseProduct) -> LocalizedStringKey {
        let length = Self.duration(trial, locale: locale)
        if product.plan == .monthly { return "paywall.trialTerms.monthly \(length) \(product.localizedPrice)" }
        return "paywall.trialTerms.annual \(length) \(product.localizedPrice)"
    }

    /// "1 week", "7 days", "1 hafta"… in the app's language, from the Store-configured period.
    static func duration(_ trial: FreeTrial, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        var components = DateComponents()
        switch trial.unit {
        case .day: components.day = trial.value
        case .week: components.weekOfMonth = trial.value
        case .month: components.month = trial.value
        case .year: components.year = trial.value
        }
        return formatter.string(from: components) ?? "\(trial.value)"
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

/// Before/after hero (owner-approved): the street demo through the same render graph as export,
/// clean left of a divider the user drags, the Look on the right. Swiping elsewhere on the hero
/// changes the Look (dots below). Decorative for VoiceOver except the comparison, which is an
/// adjustable element.
private struct PaywallCompareHero: View {
    @Environment(\.showcase) private var showcase
    @Environment(\.scenePhase) private var scenePhase
    @State private var playback = DemoPlayback()
    @State private var looks: [LookDefinition] = []
    @State private var index = 0
    @State private var split = 0.5
    /// Split when the divider drag began; nil while not dragging the divider.
    @State private var dragStartSplit: Double?

    private static let lookIDs: [LookID] = [
        ShowcaseMedia.heroLookID, ShowcaseMedia.beatLookID, "renn.noir_grain", "renn.sunday_polaroid",
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let look = looks.indices.contains(index) ? looks[index] : nil
            ZStack(alignment: .top) {
                if let showcase, let look {
                    DemoVideoView(
                        engine: showcase.engine, player: playback.player, recipe: ShowcaseMedia.recipe(for: look),
                        compareSplit: split, isActive: scenePhase == .active)
                } else {
                    RENNColor.glassOpaqueFallback
                }
                // Readability at the top (close button) and a fade into the brown page below.
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
                LinearGradient(
                    colors: [RENNColor.backgroundBase.opacity(0), RENNColor.backgroundBase.opacity(0.85), RENNColor.backgroundBase],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                divider(width: width, height: height)
                labels(height: height)
                if let look {
                    VStack(spacing: 10) {
                        Text(LocalizedStringKey(look.nameKey))
                            .font(RENNFont.roboto(15, medium: true, relativeTo: .subheadline))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .bottom) {
                                Capsule().fill(RENNColor.brandSequence[index % 4]).frame(height: 2).padding(.horizontal, 10)
                            }
                        HStack(spacing: 7) {
                            ForEach(looks.indices, id: \.self) { dot in
                                Circle()
                                    .fill(Color.white.opacity(dot == index ? 1 : 0.35))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(heroDrag(width: width))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("paywall.compare.accessibility"))
            .accessibilityValue(Text(look.map { LocalizedStringKey($0.nameKey) } ?? ""))
            .accessibilityAdjustableAction { direction in
                // Swipe up/down with VoiceOver moves between Looks.
                guard !looks.isEmpty else { return }
                switch direction {
                case .increment: index = (index + 1) % looks.count
                case .decrement: index = (index - 1 + looks.count) % looks.count
                @unknown default: break
                }
            }
        }
        .task {
            var loaded: [LookDefinition] = []
            for id in Self.lookIDs {
                if let look = await showcase?.look(id) { loaded.append(look) }
            }
            looks = loaded
            await playback.start(.street)
        }
        .onChange(of: scenePhase) { _, phase in playback.setActive(phase == .active) }
        .onDisappear { playback.stop() }
    }

    /// Dragging near the divider moves it; a horizontal swipe elsewhere changes the Look.
    private func heroDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartSplit == nil {
                    let dividerX = width * split
                    guard abs(value.startLocation.x - dividerX) < 36 else { return }
                    dragStartSplit = split
                }
                if let start = dragStartSplit, width > 0 {
                    split = min(0.97, max(0.03, start + value.translation.width / width))
                }
            }
            .onEnded { value in
                defer { dragStartSplit = nil }
                guard dragStartSplit == nil, !looks.isEmpty, abs(value.translation.width) > 50,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    index = value.translation.width < 0
                        ? (index + 1) % looks.count
                        : (index - 1 + looks.count) % looks.count
                }
            }
    }

    private func divider(width: CGFloat, height: CGFloat) -> some View {
        let x = width * split
        return ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [.white, .white, .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 2, height: height - 60)
                .shadow(color: .black.opacity(0.4), radius: 4)
                .position(x: x, y: (height - 60) / 2)
            Image(systemName: "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(RENNColor.onPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.95)))
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                .position(x: x, y: height * 0.46)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func labels(height: CGFloat) -> some View {
        HStack {
            Text("paywall.compare.before")
            Spacer()
            Text("paywall.compare.after").foregroundStyle(RENNColor.brandYellow)
        }
        .font(RENNFont.roboto(11, medium: true, relativeTo: .caption2))
        .kerning(1.2)
        .textCase(.uppercase)
        .foregroundStyle(Color.white)
        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, height * 0.66)
        .accessibilityHidden(true)
    }
}
