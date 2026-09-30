import SwiftUI
import RENNFeatures

/// Takes the tab bar's place while the Projects shelf is in select mode (owner-approved
/// 2026-09-30), like Photos: the same glass capsule with Rename (exactly one tape) and Delete.
struct ProjectsSelectionBar: View {
    let viewModel: ProjectsViewModel

    var body: some View {
        HStack(spacing: 0) {
            action("pencil", "projects.rename", isEnabled: viewModel.canRenameSelection) {
                viewModel.renameSelection()
            }
            .accessibilityIdentifier("projects.selection.rename")
            action("trash", "projects.delete", isEnabled: !viewModel.selection.isEmpty, isDestructive: true) {
                viewModel.requestDeleteSelection()
            }
            .accessibilityIdentifier("projects.selection.delete")
        }
        .padding(.horizontal, RENNMetrics.capsuleInnerPadding)
        .frame(height: RENNMetrics.capsuleHeight)
        .frame(maxWidth: .infinity)
        .barGlass(RoundedRectangle(cornerRadius: RENNMetrics.capsuleRadius, style: .continuous))
        .padding(.horizontal, RENNMetrics.sideMargin)
        .padding(.bottom, RENNMetrics.capsuleBottomGap)
    }

    private func action(
        _ symbol: String, _ title: LocalizedStringKey, isEnabled: Bool, isDestructive: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(
                !isEnabled ? RENNColor.textSecondary.opacity(0.4)
                    : isDestructive ? RENNColor.brandRed : RENNColor.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: RENNMetrics.tabCellHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: symbol)
            Text(title)
        }
    }
}
