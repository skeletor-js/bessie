import AppKit
import AVKit
import BessieCore
import SwiftUI

@MainActor
final class WorkspaceFilesViewModel: ObservableObject {
    enum Selection: Equatable, Sendable {
        case none
        case markdown(path: String, document: WorkspaceTextDocument)
        case text(path: String, document: WorkspaceTextDocument)
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
    private var loadTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?

    init(root: WorkspaceFileRoot) { self.root = root }

    func load(_ path: String = "") {
        loadTask?.cancel()
        let root = self.root
        loadTask = Task {
            do {
                let values = try await Task.detached { try WorkspaceFileOps.list(root: root, relativeDirectory: path) }.value
                try Task.checkCancellation()
                directory = path
                items = values
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func open(_ item: WorkspaceBrowserItem) {
        selectionTask?.cancel()
        if item.isDirectory {
            selectedPath = nil
            selection = .none
            load(item.relativePath)
            return
        }
        selectedPath = item.relativePath
        selection = .none
        let root = self.root
        selectionTask = Task {
            do {
                let nextSelection = try await Task.detached { () -> Selection in
                    let meta = try WorkspaceFS.fileMeta(root: root, relativePath: item.relativePath).get()
                    switch meta.kind {
                    case .markdown:
                        return .markdown(
                            path: item.relativePath,
                            document: try WorkspaceFileOps.loadText(root: root, relativePath: item.relativePath)
                        )
                    case .text:
                        return .text(
                            path: item.relativePath,
                            document: try WorkspaceFileOps.loadText(root: root, relativePath: item.relativePath)
                        )
                    case .image:
                        return .image(try WorkspaceFS.materializeLocalURL(root: root, relativePath: item.relativePath).get())
                    case .video:
                        return .video(try WorkspaceFS.materializeLocalURL(root: root, relativePath: item.relativePath).get())
                    default:
                        return .unsupported(try WorkspaceFS.materializeLocalURL(root: root, relativePath: item.relativePath).get())
                    }
                }.value
                try Task.checkCancellation()
                guard selectedPath == item.relativePath else { return }
                selection = nextSelection
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveSelectedMarkdown(
        relativePath: String,
        text: String,
        expected revision: WorkspaceFileRevision,
        allowOverwrite: Bool
    ) async throws -> WorkspaceFileRevision {
        let root = self.root
        return try await Task.detached {
            try WorkspaceFileOps.saveMarkdown(
                root: root,
                relativePath: relativePath,
                text: text,
                expected: revision,
                allowOverwrite: allowOverwrite
            )
        }.value
    }

    func reloadSelection() {
        guard let selectedPath,
              let item = items.first(where: { $0.relativePath == selectedPath })
        else { return }
        open(item)
    }

    func moveSelected(to destination: String) async throws {
        guard let selectedPath else { return }
        let root = self.root
        try await Task.detached { try WorkspaceFileOps.move(root: root, from: selectedPath, to: destination) }.value
        if self.selectedPath == selectedPath {
            self.selectedPath = nil
            selection = .none
        }
        load(directory)
    }

    func deleteSelected() async throws {
        guard let selectedPath else { return }
        let root = self.root
        try await Task.detached {
            try WorkspaceFileOps.delete(
                root: root,
                relativePath: selectedPath,
                trash: BessieProjectStore.moveToTrash
            )
        }.value
        if self.selectedPath == selectedPath {
            self.selectedPath = nil
            selection = .none
        }
        load(directory)
    }
}

struct WorkspaceFilesSurface: View {
    let connection: BessieConnectionDefinition
    let projection: HerdrSessionProjection
    let selectedWorkspaceID: String?
    let selectedPaneID: String?
    var remoteFileAccess: SSHRemoteFileAccess? = nil

    var body: some View {
        let paneID = selectedPaneID
            ?? projection.panes.first(where: { $0.workspaceID == selectedWorkspaceID && $0.focused })?.id
            ?? projection.focusedPane?.id
            ?? projection.panes.first(where: { selectedWorkspaceID == nil || $0.workspaceID == selectedWorkspaceID })?.id
        switch WorkspaceFS.resolveRoot(
            connection: connection,
            projection: projection,
            paneID: paneID,
            workspaceID: selectedWorkspaceID ?? projection.panes.first(where: { $0.id == paneID })?.workspaceID,
            remoteAccess: remoteFileAccess
        ) {
        case .failure(.remoteUnsupported):
            ContentUnavailableView(
                "Remote files need an active SSH tunnel",
                systemImage: "network.slash",
                description: Text("Reconnect this SSH Herdr session, then open Files again.")
            )
        case .failure(let error):
            ContentUnavailableView(
                "No workspace folder",
                systemImage: "folder.badge.questionmark",
                description: Text(Self.describe(error, connection: connection, remoteFileAccess: remoteFileAccess, paneID: paneID))
            )
        case .success(let root):
            WorkspaceFilesBrowser(root: root)
                .id("\(root.connectionID):\(root.workspaceID):\(root.rootURL.path):\(root.isRemote ? "remote" : "local")")
        }
    }

    private static func describe(
        _ error: WorkspacePathError,
        connection: BessieConnectionDefinition,
        remoteFileAccess: SSHRemoteFileAccess?,
        paneID: String?
    ) -> String {
        switch error {
        case .remoteUnsupported:
            return "Reconnect this SSH Herdr session, then open Files again."
        case .missingRoot:
            if connection.kind == .ssh, remoteFileAccess == nil {
                return "SSH tunnel is not ready yet. Wait for Connected, then reopen Files."
            }
            if paneID == nil {
                return "Select a workspace pane first so Bessie knows which folder to open."
            }
            return "Herdr did not report a working directory for this pane yet. Focus a terminal, run a command, then try again."
        case .notDirectory:
            return "The reported working directory is missing or not a folder on the \(connection.kind == .ssh ? "remote host" : "Mac")."
        case .unreadable:
            return connection.kind == .ssh
                ? "Could not read the remote folder over SSH (check python3 on the remote host and folder permissions)."
                : "Bessie cannot read that folder on this Mac."
        case .pathEscape:
            return "That path is outside the workspace root."
        case .notFound:
            return "That file or folder was not found."
        case .tooLarge:
            return "That file is too large to open here."
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
                }
                .frame(minWidth: 240, idealWidth: 300)
                preview
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { model.load() }
        .onChange(of: model.selectedPath) { _, path in
            guard let path,
                  let item = model.items.first(where: { $0.relativePath == path })
            else { return }
            model.open(item)
        }
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
        case .markdown(let path, let document):
            MarkdownFileEditor(
                document: document,
                save: { text, revision, overwrite in
                    try await model.saveSelectedMarkdown(
                        relativePath: path,
                        text: text,
                        expected: revision,
                        allowOverwrite: overwrite
                    )
                },
                reload: model.reloadSelection
            )
            .id("\(path):\(document.revision.contentFingerprint)")
        case .text(_, let document):
            ScrollView { Text(document.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                .overlay(alignment: .topTrailing) { Text("Read only").font(.caption).padding(8).background(BessieDesign.inset) }
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
