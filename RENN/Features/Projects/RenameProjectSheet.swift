import SwiftUI
import RENNFeatures

/// Rename sheet with inline validation (80 characters, single line, not empty). Used from the
/// Projects shelf and from the preview header.
struct RenameProjectSheet: View {
    /// Returns the error to show, or nil when the rename succeeded.
    let onSave: (String) async -> ProjectsViewModel.RenameError?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: ProjectsViewModel.RenameError?
    @State private var isSaving = false
    @FocusState private var focused: Bool

    init(currentName: String, onSave: @escaping (String) async -> ProjectsViewModel.RenameError?) {
        self.onSave = onSave
        _text = State(initialValue: currentName)
    }

    var body: some View {
        RENNSheet("projects.rename.title", size: .form, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(text: $text) { Text("projects.rename.placeholder") }
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textPrimary)
                    .padding(12)
                    .frame(minHeight: RENNMetrics.minimumTouchTarget)
                    .glassBackground(cornerRadius: RENNMetrics.cardRadius)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                if let error {
                    Text(message(for: error))
                        .font(RENNFont.secondary)
                        .foregroundStyle(RENNColor.brandRed)
                }
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
            .padding(.top, 8)
        } actions: {
            Button("common.save") { save() }
                .buttonStyle(.rennPrimary)
                .disabled(isSaving)
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let failure = await onSave(text)
            isSaving = false
            if let failure {
                error = failure
            } else {
                dismiss()
            }
        }
    }

    private func message(for error: ProjectsViewModel.RenameError) -> LocalizedStringKey {
        switch error {
        case .empty: "projects.rename.error.empty"
        case .multiline: "projects.rename.error.multiline"
        case .tooLong(let maximum): "projects.rename.error.tooLong \(maximum)"
        case .failed: "projects.rename.error.failed"
        }
    }
}
