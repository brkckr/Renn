import SwiftUI

/// Heights of RENN bottom sheets (owner-approved sheet consistency, 2026-09-30).
enum RENNSheetSize {
    /// Pickers and panels: half height, pull up for the full height.
    case panel
    /// Short forms: half height only.
    case form
    /// Over the live camera: low, so the viewfinder stays visible.
    case overCamera
    /// Content that needs the whole height (summaries, panels with their own preview).
    case full

    var detents: Set<PresentationDetent> {
        switch self {
        case .panel: [.medium, .large]
        case .form: [.medium]
        case .overCamera: [.fraction(0.42), .medium]
        case .full: [.large]
        }
    }
}

/// One chrome for every RENN bottom sheet: grabber, the glass ✕ at the top leading corner (the
/// same control and place as every full-screen flow), centred title, brown background, content,
/// and the sheet's actions pinned at the bottom (one yellow primary, optional glass secondary).
/// Cancelling is ✕ or swiping down; sheets have no text Cancel/Close buttons. System sheets
/// (share, video picker) and confirmations stay native.
struct RENNSheet<Content: View, Actions: View>: View {
    let title: LocalizedStringKey
    let size: RENNSheetSize
    let onClose: () -> Void
    private let content: Content
    private let actions: Actions
    private let hasActions: Bool

    init(
        _ title: LocalizedStringKey,
        size: RENNSheetSize = .panel,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.size = size
        self.onClose = onClose
        self.content = content()
        self.actions = actions()
        hasActions = Actions.self != EmptyView.self
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if hasActions {
                VStack(spacing: 10) { actions }
                    .padding(.horizontal, RENNMetrics.sideMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
        .background(RENNColor.backgroundBase.ignoresSafeArea())
        .presentationBackground(RENNColor.backgroundBase)
        .presentationDetents(size.detents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(RENNFont.roboto(18, medium: true, relativeTo: .headline))
                .foregroundStyle(RENNColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, RENNMetrics.minimumTouchTarget + 12)
                .accessibilityAddTraits(.isHeader)
            HStack {
                CloseButton(action: onClose)
                Spacer()
            }
        }
        .padding(.horizontal, RENNMetrics.sideMargin)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

extension RENNSheet where Actions == EmptyView {
    init(
        _ title: LocalizedStringKey,
        size: RENNSheetSize = .panel,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, size: size, onClose: onClose, content: content, actions: { EmptyView() })
    }
}
