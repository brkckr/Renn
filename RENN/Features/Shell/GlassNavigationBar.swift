import SwiftUI
import RENNDomain

/// One continuous bottom-left-anchored glass surface that morphs from the tab capsule into
/// the creation menu (02 D04, 03 M03). Geometry uses the contract's starting values;
/// motion timing is a baseline that M07 refines against references/bottom bar.mp4.
struct GlassNavigationBar: View {
    let selectedTab: AppTab
    let isMenuOpen: Bool
    let dualCameraAvailability: DualCameraAvailability
    let onSelect: (AppTab) -> Void
    let onToggleMenu: () -> Void
    let onChoose: (CreationAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var pillNamespace
    @AccessibilityFocusState private var firstRowFocused: Bool

    private var isHome: Bool { selectedTab == .home }

    var body: some View {
        HStack(alignment: .bottom, spacing: RENNMetrics.createButtonGap) {
            surface
            if isHome {
                createButton
                    // Keep the + center aligned with the closed capsule's center.
                    .padding(.bottom, (RENNMetrics.capsuleHeight - RENNMetrics.createButtonSize) / 2)
                    .transition(.scale(scale: 0.75).combined(with: .opacity))
            }
        }
        .padding(.horizontal, RENNMetrics.sideMargin)
        .padding(.bottom, RENNMetrics.capsuleBottomGap)
        .animation(reduceMotion ? RENNMotion.reducedDissolve : RENNMotion.capsuleWidth, value: selectedTab)
        .animation(
            reduceMotion ? RENNMotion.reducedDissolve : (isMenuOpen ? RENNMotion.menuOpen : RENNMotion.menuClose),
            value: isMenuOpen)
        .onChange(of: isMenuOpen) { _, isOpen in
            if isOpen { firstRowFocused = true }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isMenuOpen) { _, isOpen in isOpen }
    }

    // MARK: Surface

    private var surface: some View {
        let shape = RoundedRectangle(
            cornerRadius: isMenuOpen ? RENNMetrics.panelRadius : RENNMetrics.capsuleRadius,
            style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            // The same material view in both states, so its identity never changes.
            GlassSurface(shape: shape)
            if isMenuOpen {
                menuContent
            } else {
                tabRow
                    .transition(.opacity.animation(.linear(duration: 0.08)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isMenuOpen ? RENNMetrics.menuOpenHeight : RENNMetrics.capsuleHeight)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAction(.escape) {
            if isMenuOpen { onToggleMenu() }
        }
    }

    // MARK: Tabs

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, RENNMetrics.capsuleInnerPadding)
        .frame(height: RENNMetrics.capsuleHeight)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = tab == selectedTab
        return Button {
            onSelect(tab)
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(contrast == .increased ? 0.2 : 0.12))
                        .matchedGeometryEffect(id: "selectedTabPill", in: pillNamespace)
                }
                tab.icon.image
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? Color.white : RENNColor.textSecondary)
                if isSelected && contrast == .increased {
                    // Increase Contrast: selected icon gets a 3 pt indicator dot (02 D01).
                    Circle().fill(Color.white).frame(width: 3, height: 3).offset(y: 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: RENNMetrics.tabCellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.titleKey))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("tab.\(tab)")
    }

    // MARK: Menu

    @ViewBuilder
    private var menuContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Large text: grow and scroll within the available height; never clip text.
            ScrollView { menuRows }
                .frame(maxHeight: 440)
        } else {
            menuRows
        }
    }

    private var menuRows: some View {
        VStack(spacing: RENNMetrics.menuRowGap) {
            menuRow(
                index: 0, action: .recordVideo, icon: .recordVideo,
                title: "creation.record.title", subtitle: "creation.record.subtitle")
                .accessibilityFocused($firstRowFocused)
            menuRow(
                index: 1, action: .recordWithBothCameras, icon: .recordBothCameras,
                title: "creation.dual.title",
                subtitle: dualCameraAvailability == .supported
                    ? LocalizedStringKey("creation.dual.subtitle")
                    : LocalizedStringKey("creation.dual.unsupportedSubtitle"))
            menuRow(
                index: 2, action: .importVideo, icon: .importVideo,
                title: "creation.import.title", subtitle: "creation.import.subtitle")
        }
        .padding(RENNMetrics.menuRowPadding)
    }

    private func menuRow(
        index: Int,
        action: CreationAction,
        icon: RENNIcon,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        Button {
            onChoose(action)
        } label: {
            HStack(spacing: 12) {
                icon.image
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(RENNFont.rowTitle)
                        .foregroundStyle(RENNColor.textPrimary)
                    Text(subtitle)
                        .font(RENNFont.rowSubtitle)
                        .foregroundStyle(RENNColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: RENNMetrics.menuRowMinHeight, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: RENNMetrics.menuRowRadius, style: .continuous))
        }
        .buttonStyle(MenuRowButtonStyle())
        .accessibilityIdentifier("creation.\(action)")
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8))
                .animation(.easeOut(duration: 0.16).delay(0.10 + 0.03 * Double(index))),
            removal: .opacity.animation(.linear(duration: 0.08))))
    }

    // MARK: Create button

    private var createButton: some View {
        Button(action: onToggleMenu) {
            RENNIcon.create.image
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .rotationEffect(.degrees(isMenuOpen ? 45 : 0))
                .frame(width: RENNMetrics.createButtonSize, height: RENNMetrics.createButtonSize)
                .glassBackground(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text(isMenuOpen ? LocalizedStringKey("creation.close") : LocalizedStringKey("creation.open")))
        .accessibilityIdentifier("creation.toggle")
    }
}

/// Row background white 5%, pressed 12% (02 D04).
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: RENNMetrics.menuRowRadius, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.05)))
    }
}

/// + press: scale to 0.94 in 70 ms, return in 120 ms (03 M03).
private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: configuration.isPressed ? 0.07 : 0.12), value: configuration.isPressed)
    }
}
