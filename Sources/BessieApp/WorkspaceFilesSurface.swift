import AppKit
import AVKit
import BessieCore
import SwiftUI

@MainActor
final class WorkspaceFilesViewModel: ObservableObject {
    enum Selection: Equatable {
        case none
        case text(WorkspaceTextDocument, markdown: Bool)
        case image(URL)
        case video(URL)
        case unsupported(URL)
    }

    @Published private(set) var items: [WorkspaceBrowserItem] = []
    @Published private(set) var directory = ""
    @Published private(set) var selection: Selection = .none
    @Published var selectedPath: String?
    @Published var errorMessage: String?
    let root: WorkspaceFileRoot

    init(root: WorkspaceFileRoot) { self.root = root }

    func load(_ path: String = "") {
        let root = self.root
        Task {
            do {
                let values = try await Task.detached { try WorkspaceFileOps.list(root: root, relativeDirectory: path) }.value
                directory = path
                items = values
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func open(_ item: WorkspaceBrowserItem) {
        if item.isDirectory { selectedPath = nil; selection = .none; load(item.relativePath); return }
        selectedPath = item.relativePath
        let root = self.root
        Task {
            do {
                let meta = try await Task.detached { try WorkspaceFS.fileMeta(root: root, relativePath: item.relativePath).get() }.value
                let url = try WorkspaceFS.resolveFile(root: root, relativePath: item.relativePath).get()
                switch meta.kind {
                case .markdown, .text:
                    let document = try await Task.detached { try WorkspaceFileOps.loadText(root: root, relativePath: item.relativePath) }.value
                    selection = .text(document, markdown: meta.kind == .markdown)
                case .image: selection = .image(url)
                case .video: selection = .video(url)
                default: selection = .unsupported(url)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func moveSelected(to destination: String) async throws {
        guard let selectedPath else { return }
        let root = self.root
        try await Task.detached { try WorkspaceFileOps.move(root: root, from: selectedPath, to: destination) }.value
        self.selectedPath = nil
        selection = .none
        load(directory)
    }

    func deleteSelected() async throws {
        guard let selectedPath else { return }
        try WorkspaceFileOps.delete(root: root, relativePath: selectedPath) { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }
        self.selectedPath = nil
        selection = .none
        load(directory)
    }
}

struct WorkspaceFilesSurface: View {
    let connection: BessieConnectionDefinition
    let projection: HerdrSessionProjection
    let selectedWorkspaceID: String?
    let selectedPaneID: String?

    var body: some View {
        switch WorkspaceFS.resolveRoot(connection: connection, projection: projection, paneID: selectedPaneID, workspaceID: selectedWorkspaceID) {
        case .failure(.remoteUnsupported):
            ContentUnavailableView("Files aren’t available for remote connections", systemImage: "network.slash", description: Text("V1 file browsing works only with a local Herdr workspace."))
        case .failure:
            ContentUnavailableView("No local workspace folder", systemImage: "folder.badge.questionmark", description: Text("Select a pane with an available working directory."))
        case .success(let root):
            WorkspaceFilesBrowser(root: root)
                .id("\(root.connectionID):\(root.workspaceID):\(root.rootURL.path)")
        }
    }
}

private struct WorkspaceFilesBrowser: View {
    @StateObject private var model: WorkspaceFilesViewModel
    @State private var moveDestination = ""
    @State private var showMove = false
    @State private var showDelete = false

    init(root: WorkspaceFileRoot) { _model = StateObject(wrappedValue: WorkspaceFilesViewModel(root: root)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.load(parentPath) } label: { Label("Up", systemImage: "chevron.left") }
                    .disabled(model.directory.isEmpty)
                Text(model.directory.isEmpty ? model.root.rootURL.lastPathComponent : model.directory)
                    .font(.system(size: 12, design: .monospaced)).lineLimit(1)
                Spacer()
                Button("Rename / Move") { moveDestination = model.selectedPath ?? ""; showMove = true }.disabled(model.selectedPath == nil)
                Button("Move to Trash", role: .destructive) { showDelete = true }.disabled(model.selectedPath == nil)
            }
            .padding(10)
            Divider()
            HSplitView {
                List(model.items, selection: $model.selectedPath) { item in
                    Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
                        .tag(item.relativePath)
                        .contentShape(Rectangle())
                        .onTapGesture { model.open(item) }
                }
                .frame(minWidth: 240, idealWidth: 300)
                preview
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { model.load() }
        .sheet(isPresented: $showMove) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename or move").font(.headline)
                Text("Enter a path relative to this workspace.").foregroundStyle(BessieDesign.subtle)
                TextField("docs/new-name.md", text: $moveDestination)
                HStack { Spacer(); Button("Cancel") { showMove = false }; Button("Move") { performMove() }.disabled(moveDestination.isEmpty) }
            }.padding(20).frame(width: 440)
        }
        .confirmationDialog("Move this item to Trash?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("File action failed", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    @ViewBuilder private var preview: some View {
        switch model.selection {
        case .none: ContentUnavailableView("Select a file", systemImage: "doc.text.magnifyingglass")
        case .text(let document, let markdown):
            if markdown {
                MarkdownFileEditor(document: document, save: { text, revision, overwrite in
                    guard let path = model.selectedPath else { throw WorkspacePathError.notFound }
                    let root = model.root
                    return try await Task.detached { try WorkspaceFileOps.saveMarkdown(root: root, relativePath: path, text: text, expected: revision, allowOverwrite: overwrite) }.value
                }, reload: { if let item = model.items.first(where: { $0.relativePath == model.selectedPath }) { model.open(item) } })
                .id(document.revision.modificationDate)
            } else {
                ScrollView { Text(document.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                    .overlay(alignment: .topTrailing) { Text("Read only").font(.caption).padding(8).background(BessieDesign.inset) }
            }
        case .image(let url):
            if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().padding(18) }
            else { fallback(url, message: "This image couldn’t be previewed.") }
        case .video(let url):
            VStack(spacing: 10) {
                VideoPlayer(player: AVPlayer(url: url))
                Button("Open Externally") { NSWorkspace.shared.open(url) }
            }
            .padding(18)
        case .unsupported(let url): fallback(url, message: "This file can’t be previewed in Bessie.")
        }
    }

    private var parentPath: String { (model.directory as NSString).deletingLastPathComponent == "." ? "" : (model.directory as NSString).deletingLastPathComponent }
    private func fallback(_ url: URL, message: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Preview unavailable",
                systemImage: "doc",
                description: Text(message)
            )
            Button("Open Externally") { NSWorkspace.shared.open(url) }
                .buttonStyle(BessieSecondaryButtonStyle())
        }
    }
    private func performMove() { Task { do { try await model.moveSelected(to: moveDestination); showMove = false } catch { model.errorMessage = error.localizedDescription } } }
    private func performDelete() { Task { do { try await model.deleteSelected() } catch { model.errorMessage = error.localizedDescription } } }
}
