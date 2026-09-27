import SwiftUI
import RENNDomain
import RENNFeatures

/// Projects tab: upper retro player, shelf divider and a three-column collection of
/// upright VHS cases (02 D08). Rename/Delete are in a discoverable, accessible action menu
/// on every case, not solely long-press. Layered player art, processed-frame prints and the
/// insertion motion (03 M05) come later; the shells here are placeholders.
struct ProjectsView: View {
    let viewModel: ProjectsViewModel

    @State private var renaming: ProjectSummary?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                PlayerPlaceholder()
                    .frame(height: min(proxy.size.height * 0.28, 200))
                    .padding(.horizontal, RENNMetrics.sideMargin)
                    .padding(.top, 8)
                // Shelf divider separating the player from the collection.
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.top, 12)
                collection
            }
        }
        .task { await viewModel.observe() }
        .sheet(item: $renaming) { project in
            RenameProjectSheet(project: project) { text in
                try await viewModel.rename(project.id, to: text)
            }
        }
        .confirmationDialog(
            Text("projects.delete.title"),
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.cancelDelete() } }),
            titleVisibility: .visible,
            presenting: viewModel.pendingDeletion
        ) { _ in
            Button("projects.delete.confirm", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
            Button("common.cancel", role: .cancel) { viewModel.cancelDelete() }
        } message: { _ in
            Text("projects.delete.message")
        }
        .alert(
            Text(errorMessage ?? ""),
            isPresented: Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.dismissError() } })
        ) {
            Button("common.ok") { viewModel.dismissError() }
        }
    }

    @ViewBuilder
    private var collection: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            VStack(spacing: 12) {
                Spacer()
                RENNIcon.warning.image
                    .font(.system(size: 32))
                    .foregroundStyle(RENNColor.brandAmber)
                    .accessibilityHidden(true)
                Text("projects.unavailable")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
        case .loaded where viewModel.projects.isEmpty:
            VStack(spacing: 12) {
                Spacer()
                Text("projects.empty.title")
                    .font(RENNFont.heading)
                    .foregroundStyle(RENNColor.textPrimary)
                Text("projects.empty.body")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("projects.empty.cta") { viewModel.createFirstTape() }
                    .buttonStyle(.rennPrimary)
                    .padding(.top, 8)
                Spacer()
            }
            .padding(.horizontal, RENNMetrics.sideMargin)
        case .loaded:
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                    spacing: 20
                ) {
                    ForEach(viewModel.projects) { project in
                        caseCell(project)
                    }
                }
                .padding(.horizontal, RENNMetrics.sideMargin)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func caseCell(_ project: ProjectSummary) -> some View {
        Button {
            viewModel.open(project.id)
        } label: {
            VHSCaseShell(
                name: project.name.value,
                variant: ProjectsViewModel.caseVariant(for: project.id),
                status: statusKey(project.readiness))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Menu {
                actions(for: project)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RENNColor.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .frame(width: RENNMetrics.minimumTouchTarget, height: RENNMetrics.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("projects.action.more"))
        }
        .contextMenu { actions(for: project) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: project.name.value))
        .accessibilityHint(Text("projects.case.hint"))
        .accessibilityAction(named: Text("projects.rename")) { renaming = project }
        .accessibilityAction(named: Text("projects.delete")) { viewModel.requestDelete(project.id) }
    }

    @ViewBuilder
    private func actions(for project: ProjectSummary) -> some View {
        Button {
            renaming = project
        } label: {
            Label("projects.rename", systemImage: "pencil")
        }
        Button(role: .destructive) {
            viewModel.requestDelete(project.id)
        } label: {
            Label("projects.delete", systemImage: "trash")
        }
    }

    private func statusKey(_ readiness: ProjectSummary.Readiness) -> LocalizedStringKey? {
        switch readiness {
        case .ready, .deleting: nil
        case .preparing: "projects.status.preparing"
        case .interrupted: "projects.status.interrupted"
        case .sourceMissing: "projects.status.sourceMissing"
        }
    }

    private var errorMessage: LocalizedStringKey? {
        switch viewModel.actionError {
        case .none: nil
        case .projectInUse: "projects.error.inUse"
        case .deleteFailed: "projects.error.deleteFailed"
        }
    }
}

/// Rename sheet with inline validation (80 characters, single line, not empty).
private struct RenameProjectSheet: View {
    let project: ProjectSummary
    let onSave: (String) async throws(ProjectsViewModel.RenameError) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: ProjectsViewModel.RenameError?
    @State private var isSaving = false
    @FocusState private var focused: Bool

    init(project: ProjectSummary, onSave: @escaping (String) async throws(ProjectsViewModel.RenameError) -> Void) {
        self.project = project
        self.onSave = onSave
        _text = State(initialValue: project.name.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("projects.rename.title")
                .font(RENNFont.heading)
                .foregroundStyle(RENNColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
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
            HStack(spacing: 12) {
                Button("common.cancel") { dismiss() }
                    .buttonStyle(.rennSecondary)
                Button("common.save") { save() }
                    .buttonStyle(.rennPrimary)
                    .disabled(isSaving)
            }
            Spacer(minLength: 0)
        }
        .padding(RENNMetrics.sideMargin)
        .presentationDetents([.medium])
        .presentationBackground(RENNColor.backgroundBase)
        .onAppear { focused = true }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onSave(text)
                dismiss()
            } catch {
                self.error = error
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

/// PLACEHOLDER vector player. Final original/licensed rear/front/slot layers are an
/// outstanding owner input (08 I02). Decorative buttons have no function.
private struct PlayerPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: 0x1E1B18))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.horizontal, 24)
                // Thin horizontal slot.
                Capsule()
                    .fill(Color.black)
                    .frame(width: 120, height: 6)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 10, height: 10)
                    }
                    Spacer()
                    Circle().fill(RENNColor.brandRed.opacity(0.8)).frame(width: 8, height: 8)
                }
                .padding(.horizontal, 28)
            }
            .padding(.vertical, 16)
        }
        .aspectRatio(1.25, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) { DevelopmentFixtureBadge().padding(10) }
        .accessibilityHidden(true)
    }
}
