import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import RENNDomain
import RENNFeatures

/// Import (05 V06): the system picker gives selected-media access only (no full library
/// permission). The received file is copied into app-owned temporary storage while access is
/// valid; the importer then moves it into staging and inspects it.
struct ImportFlowView: View {
    @State private var viewModel: ImportFlowViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsPicker = true
    @State private var loadTask: Task<Void, Never>?

    init(viewModel: @autoclosure () -> ImportFlowViewModel) {
        _viewModel = State(initialValue: viewModel())
    }

    var body: some View {
        ZStack {
            RENNColor.backgroundBase.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    CloseButton { cancel() }
                }
                Spacer()
                content
                Spacer()
            }
            .padding(RENNMetrics.sideMargin)
        }
        .photosPicker(isPresented: $showsPicker, selection: $pickerItem, matching: .videos, preferredItemEncoding: .current)
        .task { await viewModel.observeAccess() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            loadTask = Task { await load(item) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .picking:
            VStack(spacing: 12) {
                Text("import.pick.title")
                    .font(RENNFont.heading)
                    .foregroundStyle(RENNColor.textPrimary)
                Button("import.pick.cta") { showsPicker = true }
                    .buttonStyle(.rennPrimary)
            }
        case .preparing, .creatingProject, .finished:
            VStack(spacing: 12) {
                ProgressView()
                Text("import.preparing")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
            }
        case .requiresPro(let duration):
            VStack(spacing: 12) {
                Text("import.limit.title")
                    .font(RENNFont.heading)
                    .foregroundStyle(RENNColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("import.limit.body \(ProjectPreviewView.timestamp(duration.approximateSeconds))")
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("import.limit.upgrade") { viewModel.upgrade() }
                    .buttonStyle(.rennPrimary)
                Button("import.limit.another") {
                    Task {
                        await viewModel.chooseAnother()
                        pickerItem = nil
                        showsPicker = true
                    }
                }
                .buttonStyle(.rennSecondary)
            }
        case .failed(let failure):
            VStack(spacing: 12) {
                Text(message(for: failure))
                    .font(RENNFont.body)
                    .foregroundStyle(RENNColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("import.limit.another") {
                    Task {
                        await viewModel.chooseAnother()
                        pickerItem = nil
                        showsPicker = true
                    }
                }
                .buttonStyle(.rennPrimary)
            }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                await viewModel.didPickFailed()
                return
            }
            await viewModel.didPick(movie.url)
        } catch {
            await viewModel.didPickFailed()
        }
    }

    private func cancel() {
        loadTask?.cancel()
        Task { await viewModel.cancel() }
    }

    private func message(for failure: ImportFlowViewModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .unreadable: "import.failed.unreadable"
        case .noVideo: "import.failed.noVideo"
        case .unsupported: "import.failed.unsupported"
        case .insufficientStorage: "import.failed.storage"
        case .couldNotSave: "import.failed.save"
        }
    }
}

/// A picked movie copied into `tmp/RENNPicker/` while the picker's access is valid.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let directory = URL.temporaryDirectory.appendingPathComponent("RENNPicker", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
