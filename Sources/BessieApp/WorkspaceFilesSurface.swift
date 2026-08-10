import AppKit
import AVKit
import BessieCore
import ImageIO
import SwiftUI

struct WorkspaceDecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    let size: CGSize
}

enum WorkspaceImageLoader {
    static let maximumSourcePixelCount = 40_000_000
    static let maximumPreviewDimension = 4_096

    static func decode(_ data: Data) throws -> WorkspaceDecodedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) != nil,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0
        else { throw WorkspacePathError.invalidImage }
        guard width <= maximumSourcePixelCount / height else { throw WorkspacePathError.tooLarge }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPreviewDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WorkspacePathError.invalidImage
        }
        return WorkspaceDecodedImage(
            cgImage: image,
            size: CGSize(width: image.width, height: image.height)
        )
    }
}

@MainActor
final class WorkspaceFilesViewModel: ObservableObject {
    enum Selection: Sendable {
        case none
        case markdown(path: String, document: WorkspaceTextDocument)
        case text(path: String, document: WorkspaceTextDocument)
        case image(WorkspaceDecodedImage)
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
        selectionTask?.cancel()
        selectedPath = nil
        selection = .none
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
        errorMessage = nil
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
                        let data = try WorkspaceFS.loadImageData(root: root, relativePath: item.relativePath).get()
                        return .image(try WorkspaceImageLoader.decode(data))
                    case .video:
                        return .video(try WorkspaceFS.materializeLocalURL(root: root, relativePath: item.relativePath).get())
                    default:
                        throw WorkspacePathError.unsupportedType
                    }
                }.value
                try Task.checkCancellation()
                guard selectedPath == item.relativePath else { return }
                selection = nextSelection
            } catch is CancellationError {
                return
            } catch {
                guard selectedPath == item.relativePath else { return }
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

    func loadMarkdownImage(markdownPath: String, reference: URL) async throws -> WorkspaceDecodedImage {
        guard reference.scheme == nil,
              !reference.path.isEmpty,
              !reference.path.hasPrefix("/"),
              reference.query == nil,
              reference.fragment == nil
        else { throw WorkspacePathError.unsupportedType }
        let parent = (markdownPath as NSString).deletingLastPathComponent
        let relativePath = parent == "." || parent.isEmpty
            ? reference.path
            : (parent as NSString).appendingPathComponent(reference.path)
        let root = self.root
        return try await Task.detached {
            let data = try WorkspaceFS.loadImageData(root: root, relativePath: relativePath).get()
            return try WorkspaceImageLoader.decode(data)
        }.value
    }

    func reloadSelection() {
        guard let selectedPath,
              let item = items.first(where: { $0.relativePath == selectedPath })
        else { return }
        open(item)
    }

    var hasValidSelection: Bool {
        guard let selectedPath else { return false }
        return items.contains { $0.relativePath == selectedPath }
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
        // Sidebar Files opens the home folder for the active connection.
        // Not tied to a Herdr workspace/pane.
        switch WorkspaceFS.resolveDefaultFilesRoot(
            connection: connection,
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
                "Can't open Files",
                systemImage: "folder.badge.questionmark",
                description: Text(Self.describe(error, connection: connection, remoteFileAccess: remoteFileAccess))
            )
        case .success(let root):
            WorkspaceFilesBrowser(root: root)
                .id("\(root.connectionID):\(root.workspaceID):\(root.rootURL.path):\(root.isRemote ? "remote" : "local")")
        }
    }

    private static func describe(
        _ error: WorkspacePathError,
        connection: BessieConnectionDefinition,
        remoteFileAccess: SSHRemoteFileAccess?
    ) -> String {
        switch error {
        case .remoteUnsupported:
            return "Reconnect this SSH Herdr session, then open Files again."
        case .missingRoot:
            return connection.kind == .ssh
                ? "SSH tunnel is not ready yet. Wait until Connected, then open Files again."
                : "Couldn't find your home folder."
        case .notDirectory:
            return connection.kind == .ssh
                ? "Remote home folder is missing or not a directory."
                : "Home folder is missing or not a directory."
        case .unreadable:
            return connection.kind == .ssh
                ? "Couldn't read the remote home folder over SSH. Check the tunnel and folder permissions."
                : "Bessie cannot read your home folder on this Mac."
        case .pathEscape:
            return "That path is outside the open folder."
        case .notFound:
            return "That file or folder was not found."
        case .tooLarge:
            return "That file is too large to open here."
        case .unsupportedType:
            return "That file type is not supported for preview."
        case .invalidImage:
            return "That image is damaged or uses an unsupported encoding."
        }
    }
}

private struct WorkspaceFilesBrowser: View {
    @StateObject private var model: WorkspaceFilesViewModel
    @State private var moveDestination = ""
    @State private var showMove = false
    @State private var showDelete = false
    @State private var isRenaming = false

    init(root: WorkspaceFileRoot) { _model = StateObject(wrappedValue: WorkspaceFilesViewModel(root: root)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.load(parentPath) } label: { Label("Up", systemImage: "chevron.left") }
                    .disabled(model.directory.isEmpty)
                Text(model.directory.isEmpty ? model.root.rootURL.lastPathComponent : model.directory)
                    .font(.system(size: 12, design: .monospaced)).lineLimit(1)
                Spacer()
                Button("Rename") { beginRename() }.disabled(!model.hasValidSelection)
                Button("Move") { beginMove() }.disabled(!model.hasValidSelection)
                Button("Move to Trash", role: .destructive) { showDelete = true }.disabled(!model.hasValidSelection)
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
                Text(isRenaming ? "Rename" : "Move").font(.system(size: 16, weight: .medium))
                Text(isRenaming ? "Enter a new name." : "Enter a path relative to the open folder.")
                    .foregroundStyle(BessieDesign.subtle)
                TextField(isRenaming ? "new-name.md" : "docs/new-name.md", text: $moveDestination)
                HStack {
                    Spacer()
                    Button("Cancel") { showMove = false }
                    Button(isRenaming ? "Rename" : "Move") { performMove() }
                        .disabled(moveActionDisabled)
                }
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
                loadImage: { reference in
                    try await model.loadMarkdownImage(markdownPath: path, reference: reference)
                },
                reload: model.reloadSelection
            )
            .id("\(path):\(document.revision.contentFingerprint)")
        case .text(_, let document):
            ScrollView { Text(document.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                .overlay(alignment: .topTrailing) { Text("Read only").font(.caption).padding(8).background(BessieDesign.inset) }
        case .image(let image):
            Image(decorative: image.cgImage, scale: 1)
                .resizable()
                .scaledToFit()
                .padding(18)
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
    private var moveActionDisabled: Bool {
        let value = moveDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || (isRenaming && (value == "." || value == ".." || value.contains("/")))
    }
    private func beginRename() {
        isRenaming = true
        moveDestination = model.selectedPath.map { ($0 as NSString).lastPathComponent } ?? ""
        showMove = true
    }
    private func beginMove() {
        isRenaming = false
        moveDestination = model.selectedPath ?? ""
        showMove = true
    }
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
    private func performMove() {
        let value = moveDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination: String
        if isRenaming, let selectedPath = model.selectedPath {
            let parent = (selectedPath as NSString).deletingLastPathComponent
            destination = parent == "." || parent.isEmpty
                ? value
                : (parent as NSString).appendingPathComponent(value)
        } else {
            destination = value
        }
        Task {
            do {
                try await model.moveSelected(to: destination)
                showMove = false
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
    private func performDelete() { Task { do { try await model.deleteSelected() } catch { model.errorMessage = error.localizedDescription } } }
}
