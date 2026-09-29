import SwiftUI
import RENNDomain
import RENNFeatures

/// Projects tab: upper retro player, shelf divider and a three-column collection of
/// upright VHS cases (02 D08). Rename/Delete are in a discoverable, accessible action menu
/// on every case, not solely long-press. Opening a ready project plays the insertion motion
/// (03 M05): the case lifts, travels along a curve to the slot and slides behind the player's
/// front plate (real occlusion, not shrinking away), then the preview is presented once. The
/// player is RENN's own layered vector art, approved by the owner as final (08 I02).
struct ProjectsView: View {
    let viewModel: ProjectsViewModel

    @State private var renaming: ProjectSummary?
    @State private var cellFrames: [ProjectID: CGRect] = [:]
    @State private var playerFrame: CGRect?
    @State private var slotFrame: CGRect?
    @State private var insertion: Insertion?
    @State private var viewportHeight: CGFloat = 800
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let space = "projects"

    /// One insertion at a time, identified so stale completions never navigate.
    private struct Insertion: Equatable {
        let id = UUID()
        let project: ProjectSummary
        let size: CGSize
        let geometry: CassetteInsertion.Geometry
        let start: Date
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    PlayerArt(onSlotFrame: { slotFrame = $0 })
                        .frame(height: min(proxy.size.height * 0.28, 200))
                        .background(frameReader { playerFrame = $0 })
                        .padding(.horizontal, RENNMetrics.sideMargin)
                        .padding(.top, 8)
                    // Shelf divider separating the player from the collection.
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                        .padding(.top, 12)
                    collection
                }
                if let insertion {
                    insertionOverlay(insertion)
                }
            }
            .coordinateSpace(name: Self.space)
            .onChange(of: proxy.size.height, initial: true) { _, height in viewportHeight = height }
        }
        // Tab change, background or inactivity cancels: the card returns, nothing opens.
        .onDisappear { insertion = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { insertion = nil } }
        .task { await viewModel.observe() }
        .sheet(item: $renaming) { project in
            RenameProjectSheet(project: project) { text in
                await viewModel.renameResult(project.id, to: text)
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
            // The source must not move while it travels.
            .scrollDisabled(insertion != nil)
        }
    }

    private func caseCell(_ project: ProjectSummary) -> some View {
        Button {
            open(project)
        } label: {
            ProjectCaseView(
                project: project,
                loadPoster: { await viewModel.poster(for: $0) },
                status: statusKey(project.readiness))
                .background(frameReader { cellFrames[project.id] = $0 })
                // The cell keeps its space while its visual travels.
                .opacity(insertion?.project.id == project.id ? 0 : 1)
        }
        .buttonStyle(.plain)
        .disabled(insertion != nil)
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

    // MARK: Insertion (03 M05)

    private func open(_ project: ProjectSummary) {
        guard insertion == nil else { return }
        // Reduce Motion, non-ready media or unmeasured geometry: open directly (no travel).
        guard !reduceMotion, project.readiness == .ready,
              let source = cellFrames[project.id], let slot = slotFrame
        else {
            viewModel.open(project.id)
            return
        }
        let geometry = CassetteInsertion.Geometry(
            source: .init(x: source.midX, y: source.midY), sourceWidth: source.width, sourceHeight: source.height,
            slot: .init(x: slot.midX, y: slot.midY), slotWidth: slot.width * 0.9,
            visibleMinY: 0, viewportHeight: viewportHeight)
        let started = Insertion(project: project, size: source.size, geometry: geometry, start: .now)
        insertion = started
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CassetteInsertion.totalDuration))
            guard insertion?.id == started.id else { return }
            viewModel.open(project.id)
            insertion = nil
        }
    }

    /// Layering at insertion: rear player (in the layout) → travelling case → front plate.
    private func insertionOverlay(_ insertion: Insertion) -> some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation) { context in
                let pose = CassetteInsertion.pose(at: context.date.timeIntervalSince(insertion.start), geometry: insertion.geometry)
                ProjectCaseView(project: insertion.project, loadPoster: { await viewModel.poster(for: $0) })
                    .frame(width: insertion.size.width, height: insertion.size.height)
                    .scaleEffect(pose.scale)
                    .rotationEffect(.degrees(pose.rotationDegrees))
                    .shadow(color: .black.opacity(pose.shadowOpacity), radius: 12, x: 0, y: 8)
                    .position(x: pose.center.x, y: pose.center.y)
            }
            if let player = playerFrame, let slot = slotFrame {
                // The same player drawn again, cut at the slot line: the case slides behind it.
                PlayerArt(onSlotFrame: nil)
                    .frame(width: player.width, height: player.height)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: max(0, slot.midY - player.minY))
                    }
                    .position(x: player.midX, y: player.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func frameReader(_ update: @escaping (CGRect) -> Void) -> some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { update(geometry.frame(in: .named(Self.space))) }
                .onChange(of: geometry.frame(in: .named(Self.space))) { _, frame in update(frame) }
        }
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
    /// Returns the error to show, or nil when the rename succeeded.
    let onSave: (String) async -> ProjectsViewModel.RenameError?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: ProjectsViewModel.RenameError?
    @State private var isSaving = false
    @FocusState private var focused: Bool

    init(project: ProjectSummary, onSave: @escaping (String) async -> ProjectsViewModel.RenameError?) {
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

/// RENN's own vector player, approved by the owner as final art (08 I02). Decorative buttons
/// have no function. The slot reports its frame so the insertion motion targets it.
private struct PlayerArt: View {
    let onSlotFrame: ((CGRect) -> Void)?

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
                    .background(GeometryReader { geometry in
                        Color.clear
                            .onAppear { onSlotFrame?(geometry.frame(in: .named("projects"))) }
                            .onChange(of: geometry.frame(in: .named("projects"))) { _, frame in onSlotFrame?(frame) }
                    })
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
        .accessibilityHidden(true)
    }
}
