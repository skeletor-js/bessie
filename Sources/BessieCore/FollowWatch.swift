import Foundation

public enum FileChangeKind: String, Equatable, Sendable {
    case added
    case modified
    case deleted
    case unknown
}

public struct WorkspaceFileChange: Equatable, Sendable {
    public let relativePath: String
    public let touchedAt: Date
    public let kind: FileChangeKind

    public init(relativePath: String, touchedAt: Date = Date(), kind: FileChangeKind) {
        self.relativePath = relativePath
        self.touchedAt = touchedAt
        self.kind = kind
    }
}

public struct TouchedPath: Equatable, Identifiable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let lastTouchedAt: Date
    public let changeKind: FileChangeKind

    public init(relativePath: String, lastTouchedAt: Date, changeKind: FileChangeKind) {
        self.relativePath = relativePath
        self.lastTouchedAt = lastTouchedAt
        self.changeKind = changeKind
    }
}

public struct FollowWatchStretch: Equatable, Sendable {
    public let id: UUID
    public let connectionID: String
    public let workspaceID: String
    public let root: WorkspaceFileRoot
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        connectionID: String,
        workspaceID: String,
        root: WorkspaceFileRoot,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.connectionID = connectionID
        self.workspaceID = workspaceID
        self.root = root
        self.startedAt = startedAt
    }
}

public struct FollowTouchState: Equatable, Sendable {
    public private(set) var touchedPaths: [TouchedPath] = []
    public private(set) var pinnedPath: String?
    public var followEnabled: Bool
    public private(set) var selectedPath: String?
    public let maximumCount: Int

    public init(followEnabled: Bool = true, maximumCount: Int = 500) {
        self.followEnabled = followEnabled
        self.maximumCount = max(1, min(maximumCount, 500))
    }

    public mutating func record(_ change: WorkspaceFileChange) {
        touchedPaths.removeAll { $0.relativePath == change.relativePath }
        touchedPaths.append(TouchedPath(
            relativePath: change.relativePath,
            lastTouchedAt: change.touchedAt,
            changeKind: change.kind
        ))
        touchedPaths.sort {
            if $0.lastTouchedAt == $1.lastTouchedAt { return $0.relativePath < $1.relativePath }
            return $0.lastTouchedAt > $1.lastTouchedAt
        }
        if touchedPaths.count > maximumCount {
            touchedPaths.removeLast(touchedPaths.count - maximumCount)
        }
        if followEnabled, pinnedPath == nil { selectedPath = change.relativePath }
    }

    public mutating func pin(_ relativePath: String?) {
        pinnedPath = relativePath
        selectedPath = relativePath ?? (followEnabled ? touchedPaths.first?.relativePath : selectedPath)
    }

    public mutating func select(_ relativePath: String?) {
        guard pinnedPath == nil else { return }
        selectedPath = relativePath
    }

    public mutating func setFollowEnabled(_ enabled: Bool) {
        followEnabled = enabled
        if enabled, pinnedPath == nil { selectedPath = touchedPaths.first?.relativePath }
    }
}

public actor WorkspaceFileWatcher {
    private struct Signature: Equatable, Sendable {
        let modifiedAt: Date?
        let size: Int?
    }

    private let root: WorkspaceFileRoot
    private let pollingInterval: Duration
    private var watchTask: Task<Void, Never>?
    private var continuation: AsyncStream<[WorkspaceFileChange]>.Continuation?

    public init(root: WorkspaceFileRoot, pollingInterval: Duration = .milliseconds(250)) {
        self.root = root
        self.pollingInterval = pollingInterval
    }

    public func start() -> AsyncStream<[WorkspaceFileChange]> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(
            of: [WorkspaceFileChange].self,
            bufferingPolicy: .bufferingNewest(8)
        )
        self.continuation = continuation
        watchTask = Task { [root, pollingInterval] in
            var previous = Self.snapshot(root: root)
            while !Task.isCancelled {
                do { try await Task.sleep(for: pollingInterval) } catch { break }
                let current = Self.snapshot(root: root)
                let changes = Self.changes(from: previous, to: current)
                previous = current
                if !changes.isEmpty { continuation.yield(changes) }
            }
            continuation.finish()
        }
        return stream
    }

    public func stop() {
        watchTask?.cancel()
        watchTask = nil
        continuation?.finish()
        continuation = nil
    }

    private nonisolated static func snapshot(root: WorkspaceFileRoot) -> [String: Signature] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root.rootURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [:] }

        var result: [String: Signature] = [:]
        let rootPath = root.rootURL.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            let relativePath = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            if WorkspaceFS.isIgnoredRelativePath(relativePath) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            guard case .success = WorkspaceFS.resolvePath(root: root, relativePath: relativePath) else { continue }
            result[relativePath] = Signature(modifiedAt: values.contentModificationDate, size: values.fileSize)
        }
        return result
    }

    private nonisolated static func changes(
        from previous: [String: Signature],
        to current: [String: Signature]
    ) -> [WorkspaceFileChange] {
        let now = Date()
        let paths = Set(previous.keys).union(current.keys)
        return paths.compactMap { path in
            switch (previous[path], current[path]) {
            case (nil, .some): return WorkspaceFileChange(relativePath: path, touchedAt: now, kind: .added)
            case (.some, nil): return WorkspaceFileChange(relativePath: path, touchedAt: now, kind: .deleted)
            case let (.some(old), .some(new)) where old != new:
                return WorkspaceFileChange(relativePath: path, touchedAt: now, kind: .modified)
            default: return nil
            }
        }.sorted { $0.relativePath < $1.relativePath }
    }
}
