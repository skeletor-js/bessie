import Foundation

public struct WorkspaceFileRoot: Equatable, Sendable {
    public let connectionID: String
    public let workspaceID: String
    public let rootURL: URL
    public let gitTopLevel: URL?
    public let resolution: RootResolution

    init(
        connectionID: String,
        workspaceID: String,
        rootURL: URL,
        gitTopLevel: URL?,
        resolution: RootResolution
    ) {
        self.connectionID = connectionID
        self.workspaceID = workspaceID
        self.rootURL = rootURL
        self.gitTopLevel = gitTopLevel
        self.resolution = resolution
    }
}

public enum RootResolution: String, Equatable, Sendable {
    case herdrCwd
    case selectedPaneCwd
    case agentWorkingDir
    case unavailableRemote
    case missing
    case unauthorized
}

public enum WorkspacePathError: Error, Equatable, Sendable {
    case remoteUnsupported
    case missingRoot
    case notDirectory
    case unreadable
    case pathEscape
    case tooLarge
    case notFound
}

public enum FilePreviewKind: String, Equatable, Sendable {
    case text
    case markdown
    case image
    case video
    case binary
    case directory
}

public struct FileContentMeta: Equatable, Sendable {
    public let relativePath: String
    public let byteSize: Int
    public let contentType: String?
    public let kind: FilePreviewKind

    public init(relativePath: String, byteSize: Int, contentType: String?, kind: FilePreviewKind) {
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.contentType = contentType
        self.kind = kind
    }
}

public enum WorkspaceFS {
    public static let ignoredDirectoryNames: Set<String> = [
        ".git",
        "node_modules",
        ".build",
        "DerivedData",
    ]

    public static func resolveRoot(
        connection: BessieConnectionDefinition,
        projection: HerdrSessionProjection?,
        paneID: String? = nil,
        workspaceID: String? = nil
    ) -> Result<WorkspaceFileRoot, WorkspacePathError> {
        guard connection.kind == .local else { return .failure(.remoteUnsupported) }
        guard let projection else { return .failure(.missingRoot) }

        let selectedPane = paneID.flatMap { id in projection.panes.first { $0.id == id } }
        if paneID != nil, selectedPane == nil { return .failure(.missingRoot) }
        if let workspaceID, let selectedPane, selectedPane.workspaceID != workspaceID {
            return .failure(.missingRoot)
        }
        guard let resolvedWorkspaceID = workspaceID
            ?? selectedPane?.workspaceID
            ?? projection.focusedWorkspace?.id
        else { return .failure(.missingRoot) }

        let workspacePanes = projection.panes.filter { $0.workspaceID == resolvedWorkspaceID }
        guard !workspacePanes.isEmpty else { return .failure(.missingRoot) }

        let absoluteCWDs = workspacePanes.compactMap(\.cwd).filter(Self.isAbsolutePath)
        let consensusCWD = absoluteCWDs.count == workspacePanes.count && Set(absoluteCWDs).count == 1
            ? absoluteCWDs.first
            : nil
        let selectedCWD = selectedPane.flatMap { pane -> String? in
            guard pane.workspaceID == resolvedWorkspaceID,
                  let cwd = pane.cwd,
                  Self.isAbsolutePath(cwd) else { return nil }
            return cwd
        }
        guard let candidate = consensusCWD ?? selectedCWD else { return .failure(.missingRoot) }

        let rootURL = URL(fileURLWithPath: candidate, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .failure(.notDirectory) }
        guard FileManager.default.isReadableFile(atPath: rootURL.path) else { return .failure(.unreadable) }

        return .success(WorkspaceFileRoot(
            connectionID: connection.id,
            workspaceID: resolvedWorkspaceID,
            rootURL: rootURL,
            gitTopLevel: Self.findGitTopLevel(from: rootURL),
            resolution: consensusCWD == nil ? .selectedPaneCwd : .herdrCwd
        ))
    }

    public static func resolveContainedPath(
        root: WorkspaceFileRoot,
        relativePath: String
    ) -> Result<URL, WorkspacePathError> {
        guard !Self.isAbsolutePath(relativePath) else { return .failure(.pathEscape) }

        let pinnedRoot = root.rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pinnedRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .failure(.notFound) }
        guard pinnedRoot.resolvingSymlinksInPath().pathComponents == pinnedRoot.pathComponents else {
            return .failure(.pathEscape)
        }

        switch Self.resolveComponents(
            from: pinnedRoot,
            components: Self.pathComponents(relativePath)
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let resolvedCandidate):
            guard Self.contains(resolvedCandidate, in: pinnedRoot) else { return .failure(.pathEscape) }
            return .success(resolvedCandidate)
        }
    }

    public static func resolveFile(
        root: WorkspaceFileRoot,
        relativePath: String
    ) -> Result<URL, WorkspacePathError> {
        let candidate: URL
        switch resolveContainedPath(root: root, relativePath: relativePath) {
        case .success(let url):
            candidate = url
        case .failure(let error):
            return .failure(error)
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return .failure(.notFound) }
        guard FileManager.default.isReadableFile(atPath: candidate.path) else { return .failure(.unreadable) }
        return .success(candidate)
    }

    public static func isIgnoredRelativePath(_ path: String) -> Bool {
        guard !Self.isAbsolutePath(path) else { return false }
        return path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains { ignoredDirectoryNames.contains(String($0)) }
    }

    public static func fileMeta(
        root: WorkspaceFileRoot,
        relativePath: String,
        maximumByteSize: Int? = nil
    ) -> Result<FileContentMeta, WorkspacePathError> {
        do {
            let url = try resolveFile(root: root, relativePath: relativePath).get()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            if values.isDirectory == true {
                return .success(FileContentMeta(
                    relativePath: relativePath,
                    byteSize: 0,
                    contentType: nil,
                    kind: .directory
                ))
            }
            guard values.isRegularFile == true else { return .failure(.unreadable) }

            guard let byteSize = values.fileSize else { return .failure(.notFound) }
            if let maximumByteSize, byteSize > maximumByteSize { return .failure(.tooLarge) }
            let contentType = Self.contentType(forExtension: url.pathExtension.lowercased())
            let kind = try Self.previewKind(url: url, contentType: contentType)
            return .success(FileContentMeta(
                relativePath: relativePath,
                byteSize: byteSize,
                contentType: contentType,
                kind: kind
            ))
        } catch let error as WorkspacePathError {
            return .failure(error)
        } catch {
            return .failure(.unreadable)
        }
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/")
    }

    private static func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    private static func resolveComponents(
        from baseURL: URL,
        components: [String]
    ) -> Result<URL, WorkspacePathError> {
        var current = baseURL
        var remaining = components
        var symlinkExpansions = 0

        while !remaining.isEmpty {
            let component = remaining.removeFirst()
            if component.isEmpty || component == "." { continue }
            if component == ".." {
                current.deleteLastPathComponent()
                continue
            }

            let next = current.appendingPathComponent(component)
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: next.path)
            } catch {
                guard Self.isMissingFileError(error) else { return .failure(.unreadable) }
                current = next
                continue
            }

            guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
                current = next
                continue
            }
            guard symlinkExpansions < 40,
                  let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: next.path)
            else { return .failure(.unreadable) }
            symlinkExpansions += 1
            if Self.isAbsolutePath(destination) {
                current = URL(fileURLWithPath: "/", isDirectory: true)
            }
            remaining = Self.pathComponents(destination) + remaining
        }

        return .success(current.standardizedFileURL)
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           error.code == CocoaError.Code.fileReadNoSuchFile.rawValue
            || error.code == CocoaError.Code.fileNoSuchFile.rawValue {
            return true
        }
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return underlying?.domain == NSPOSIXErrorDomain && underlying?.code == 2
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }

    private static func findGitTopLevel(from root: URL) -> URL? {
        var candidate = root
        while true {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }

    private static func previewKind(url: URL, contentType: String?) throws -> FilePreviewKind {
        switch contentType {
        case let type? where type.hasPrefix("image/"): return .image
        case let type? where type.hasPrefix("video/"): return .video
        default: break
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let sample = try handle.read(upToCount: 8_192) ?? Data()
        guard !sample.contains(0), String(data: sample, encoding: .utf8) != nil else { return .binary }
        return contentType == "text/markdown" ? .markdown : .text
    }

    private static func contentType(forExtension pathExtension: String) -> String? {
        switch pathExtension {
        case "md", "markdown", "mdown", "mkd": "text/markdown"
        case "txt", "log": "text/plain"
        case "swift": "text/x-swift"
        case "json": "application/json"
        case "yaml", "yml": "application/yaml"
        case "html", "htm": "text/html"
        case "css": "text/css"
        case "js", "mjs", "cjs": "text/javascript"
        case "ts", "tsx": "text/typescript"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "heic": "image/heic"
        case "svg": "image/svg+xml"
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "webm": "video/webm"
        default: nil
        }
    }
}
