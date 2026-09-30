import SwiftUI
import RENNDomain
import RENNFeatures

/// Projects tab: upper retro player, shelf divider and a three-column collection of
/// upright VHS cases (02 D08). Select mode (owner-approved 2026-09-30) is the discoverable
/// path to Rename/Delete: a Select button above the shelf, a selection bar in place of the tab
/// bar and one native confirmation for every selected tape. Long-press keeps the iOS context
/// menu with a RENN preview (the case large on the brown background), and VoiceOver has named
/// Rename/Delete actions on every case. Opening a ready project plays the insertion motion
/// (03 M05): the case lifts, travels along a curve to the slot and slides behind the player's
/// front plate (real occlusion, not shrinking away), then the preview is presented once. The
/// player is RENN's own layered vector art, approved by the owner as final (08 I02).
struct ProjectsView: View {
    let viewModel: ProjectsViewModel

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
                    if viewModel.hasLoaded && !viewModel.projects.isEmpty {
                        shelfHeader
                    }
                    // Shelf divider separating the player from the collection.
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                        .padding(.top, viewModel.hasLoaded && !viewModel.projects.isEmpty ? 0 : 12)
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
        .sheet(item: Binding(
            get: { viewModel.renaming },
            set: { if $0 == nil { viewModel.dismissRename() } })
        ) { project in
            RenameProjectSheet(currentName: project.name.value) { text in
                await viewModel.renameResult(project.id, to: text)
            }
        }
        .confirmationDialog(
            Text(deleteTitle),
            isPresented: Binding(
                get: { !viewModel.pendingDeletion.isEmpty },
                set: { if !$0 { viewModel.cancelDelete() } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await viewModel.confirmDelete() }
            } label: {
                Text(deleteConfirm)
            }
            Button("common.cancel", role: .cancel) { viewModel.cancelDelete() }
        } message: {
            Text(deleteMessage)
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

    /// "Projects" and Select; in select mode the count and Done.
    private var shelfHeader: some View {
        HStack {
            Group {
                if !viewModel.isSelecting {
                    Text("tab.projects")
                } else if viewModel.selection.isEmpty {
                    Text("projects.select.prompt")
                } else {
                    Text("projects.select.count \(viewModel.selection.count)")
                }
            }
            .font(RENNFont.roboto(18, medium: true, relativeTo: .headline))
            .foregroundStyle(RENNColor.textPrimary)
            .contentTransition(.numericText())
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                if viewModel.isSelecting {
                    viewModel.endSelection()
                } else {
                    viewModel.beginSelection()
                }
            } label: {
                Text(viewModel.isSelecting ? LocalizedStringKey("common.done") : LocalizedStringKey("projects.select"))
                    .font(RENNFont.bodyMedium)
                    .foregroundStyle(RENNColor.brandYellow)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(Color.white.opacity(viewModel.isSelecting ? 0.14 : 0.08)))
                    .frame(minHeight: RENNMetrics.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(insertion != nil)
            .accessibilityIdentifier("projects.select")
            .coachTarget(.projectsSelect)
        }
        .padding(.horizontal, RENNMetrics.sideMargin)
        .padding(.top, 4)
        .animation(.easeOut(duration: 0.18), value: viewModel.selection.count)
        .animation(.easeOut(duration: 0.18), value: viewModel.isSelecting)
    }

    private func caseCell(_ project: ProjectSummary) -> some View {
        let isSelected = viewModel.selection.contains(project.id)
        return Button {
            if viewModel.isSelecting {
                viewModel.toggleSelection(project.id)
            } else {
                open(project)
            }
        } label: {
            ProjectCaseView(
                project: project,
                loadPoster: { await viewModel.poster(for: $0) },
                status: statusKey(project.readiness))
                .background(frameReader { cellFrames[project.id] = $0 })
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(RENNColor.brandYellow, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if viewModel.isSelecting {
                        SelectionMark(isSelected: isSelected)
                            .padding(6)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .scaleEffect(isSelected ? 0.95 : 1)
                // The cell keeps its space while its visual travels.
                .opacity(insertion?.project.id == project.id ? 0 : 1)
        }
        .buttonStyle(.plain)
        .disabled(insertion != nil)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.isSelecting)
        .sensoryFeedback(.selection, trigger: isSelected)
        // No menu in select mode: the selection bar carries the actions there.
        .contextMenu {
            if !viewModel.isSelecting { actions(for: project) }
        } preview: {
            ProjectContextPreview(project: project, loadPoster: { await viewModel.poster(for: $0) })
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: project.name.value))
        .accessibilityHint(Text(
            viewModel.isSelecting ? LocalizedStringKey("projects.select.caseHint") : LocalizedStringKey("projects.case.hint")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("projects.rename")) { viewModel.requestRename(project.id) }
        .accessibilityAction(named: Text("projects.delete")) { viewModel.requestDelete(project.id) }
        .coachTarget(project.id == viewModel.projects.first?.id ? .projectsFirstTape : nil)
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
            viewModel.requestRename(project.id)
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

    private var deleteTitle: LocalizedStringKey {
        let count = viewModel.pendingDeletion.count
        if count > 1 { return "projects.deleteSelected.title \(count)" }
        return "projects.delete.title"
    }

    private var deleteConfirm: LocalizedStringKey {
        let count = viewModel.pendingDeletion.count
        if count > 1 { return "projects.deleteSelected.confirm \(count)" }
        return "projects.delete.confirm"
    }

    private var deleteMessage: LocalizedStringKey {
        if viewModel.pendingDeletion.count > 1 { return "projects.deleteSelected.message" }
        return "projects.delete.message"
    }

    private var errorMessage: LocalizedStringKey? {
        switch viewModel.actionError {
        case .none: nil
        case .projectInUse: "projects.error.inUse"
        case .deleteFailed: "projects.error.deleteFailed"
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

/// Select-mode checkmark on a case, like Photos: an empty ring, filled yellow when selected.
private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? RENNColor.brandYellow : Color.black.opacity(0.35))
            Circle()
                .strokeBorder(Color.white.opacity(isSelected ? 0 : 0.9), lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RENNColor.onPrimary)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

/// Long-press preview (owner-approved 2026-09-30): the tape large on RENN's brown background,
/// with its name and last change, instead of the system's white card around the small case.
private struct ProjectContextPreview: View {
    let project: ProjectSummary
    let loadPoster: (ProjectID) async -> Data?

    var body: some View {
        VStack(spacing: 14) {
            ProjectCaseView(project: project, loadPoster: loadPoster)
                .frame(width: 180)
            VStack(spacing: 4) {
                Text(verbatim: project.name.value)
                    .font(RENNFont.roboto(18, medium: true, relativeTo: .headline))
                    .foregroundStyle(RENNColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(project.updatedAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(RENNFont.secondary)
                    .foregroundStyle(RENNColor.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(width: 260)
        .background(RENNColor.backgroundBase)
    }
}
