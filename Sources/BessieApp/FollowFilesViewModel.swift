import BessieCore
import Combine
import Foundation

@MainActor
final class FollowFilesViewModel: ObservableObject {
    enum Availability: Equatable {
        case loading
        case local(WorkspaceFileRoot)
        case remoteUnsupported
        case unavailable(String)
    }

    @Published private(set) var availability: Availability = .loading
    @Published private(set) var stretch: FollowWatchStretch?
    @Published private(set) var touchState = FollowTouchState()
    @Published private(set) var preview: DiffPreview?
    @Published private(set) var previewLoading = false

    private var contextID: String?
    private var generation = 0
    private var watcher: WorkspaceFileWatcher?
    private var watchTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    func configure(
        connection: BessieConnectionDefinition,
        projection: HerdrSessionProjection,
        paneID: String,
        remoteFileAccess: SSHRemoteFileAccess? = nil
    ) {
        let pane = projection.panes.first { $0.id == paneID }
        let nextContextID = "\(connection.id)::\(paneID)::\(pane?.workspaceID ?? "-")::\(pane?.effectiveCWD ?? "-")::\(remoteFileAccess?.controlPath ?? "local")"
        guard nextContextID != contextID else { return }
        stop()
        contextID = nextContextID

        if connection.kind == .ssh, remoteFileAccess == nil {
            availability = .remoteUnsupported
            return
        }

        switch WorkspaceFS.resolveRoot(
            connection: connection,
            projection: projection,
            paneID: paneID,
            workspaceID: pane?.workspaceID,
            remoteAccess: remoteFileAccess
        ) {
        case .failure(let error):
            availability = .unavailable(Self.message(for: error))
        case .success(let root):
            availability = .local(root)
            stretch = FollowWatchStretch(
                connectionID: connection.id,
                workspaceID: root.workspaceID,
                root: root
            )
            startWatcher(root: root)
        }
    }

    func stop() {
        generation += 1
        watchTask?.cancel()
        watchTask = nil
        previewTask?.cancel()
        previewTask = nil
        let previous = watcher
        watcher = nil
        if let previous {
            Task { await previous.stop() }
        }
        contextID = nil
        stretch = nil
        touchState = FollowTouchState()
        preview = nil
        previewLoading = false
        availability = .loading
    }

    func select(_ relativePath: String) {
        touchState.select(relativePath)
        loadSelectedPreview()
    }

    func setFollowEnabled(_ enabled: Bool) {
        touchState.setFollowEnabled(enabled)
        loadSelectedPreview()
    }

    func togglePin() {
        touchState.pin(touchState.pinnedPath == nil ? touchState.selectedPath : nil)
        loadSelectedPreview()
    }

    private func startWatcher(root: WorkspaceFileRoot) {
        let watcher = WorkspaceFileWatcher(root: root)
        self.watcher = watcher
        let generation = self.generation
        watchTask = Task { [weak self] in
            let stream = await watcher.start()
            for await batch in stream {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.generation == generation else { return }
                    let selectedPath = self.touchState.selectedPath
                    self.touchState.record(contentsOf: batch)
                    if selectedPath != self.touchState.selectedPath
                        || batch.contains(where: { $0.relativePath == self.touchState.selectedPath }) {
                        self.loadSelectedPreview()
                    }
                }
            }
        }
    }

    private func loadSelectedPreview() {
        guard case .local(let root) = availability,
              let relativePath = touchState.selectedPath else {
            preview = nil
            previewLoading = false
            return
        }
        let generation = self.generation
        previewTask?.cancel()
        previewLoading = true
        previewTask = Task { [weak self] in
            let result = GitDiffService().preview(root: root, relativePath: relativePath)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.generation == generation,
                      self.touchState.selectedPath == relativePath else { return }
                self.preview = result
                self.previewLoading = false
            }
        }
    }

    private static func message(for error: WorkspacePathError) -> String {
        switch error {
        case .missingRoot: "No local working directory is available for this pane."
        case .notDirectory: "The pane working directory is no longer available."
        case .unreadable: "Bessie cannot read this working directory."
        case .remoteUnsupported: "Reconnect the SSH tunnel to follow remote files."
        case .pathEscape, .tooLarge, .notFound: "The workspace files are unavailable."
        }
    }
}
