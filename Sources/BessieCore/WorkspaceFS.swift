import Foundation

public struct WorkspaceFileRoot: Equatable, Sendable {
    public let connectionID: String
    public let workspaceID: String
    public let rootURL: URL
    public let gitTopLevel: URL?
    public let resolution: RootResolution
    /// When set, `rootURL` is a remote POSIX path carrier; I/O goes through SSH.
    public let remote: SSHRemoteFileAccess?

    public var isRemote: Bool { remote != nil }
    public var absoluteRootPath: String { rootURL.path }

    public init(
        connectionID: String,
        workspaceID: String,
        rootURL: URL,
        gitTopLevel: URL?,
        resolution: RootResolution,
        remote: SSHRemoteFileAccess? = nil
    ) {
        self.connectionID = connectionID
        self.workspaceID = workspaceID
        self.rootURL = rootURL
        self.gitTopLevel = gitTopLevel
        self.resolution = resolution
        self.remote = remote
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

    /// Default Files root when opening the sidebar destination: user home (local or remote).
    /// Not tied to a Herdr workspace/pane.
    public static func resolveDefaultFilesRoot(
        connection: BessieConnectionDefinition,
        remoteAccess: SSHRemoteFileAccess? = nil
    ) -> Result<WorkspaceFileRoot, WorkspacePathError> {
        if connection.kind == .ssh {
            guard let remoteAccess else { return .failure(.remoteUnsupported) }
            do {
                let home = try SSHRemoteFileClient(access: remoteAccess).homeDirectory()
                let st = try SSHRemoteFileClient(access: remoteAccess).stat(home)
                guard st.exists, st.isDirectory else { return .failure(.notDirectory) }
                let git = try SSHRemoteFileClient(access: remoteAccess).findGitTopLevel(from: home)
                return .success(WorkspaceFileRoot(
                    connectionID: connection.id,
                    workspaceID: "files-home",
                    rootURL: URL(fileURLWithPath: home, isDirectory: true),
                    gitTopLevel: git.map { URL(fileURLWithPath: $0, isDirectory: true) },
                    resolution: .herdrCwd,
                    remote: remoteAccess
                ))
            } catch let error as WorkspacePathError {
                return .failure(error)
            } catch {
                return .failure(.unreadable)
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: home.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .failure(.notDirectory) }
        guard FileManager.default.isReadableFile(atPath: home.path) else { return .failure(.unreadable) }
        return .success(WorkspaceFileRoot(
            connectionID: connection.id,
            workspaceID: "files-home",
            rootURL: home,
            gitTopLevel: Self.findGitTopLevel(from: home),
            resolution: .herdrCwd,
            remote: nil
        ))
    }

    public static func resolveRoot(
        connection: BessieConnectionDefinition,
        projection: HerdrSessionProjection?,
        paneID: String? = nil,
        workspaceID: String? = nil,
        remoteAccess: SSHRemoteFileAccess? = nil
    ) -> Result<WorkspaceFileRoot, WorkspacePathError> {
        if connection.kind == .ssh, remoteAccess == nil { return .failure(.remoteUnsupported) }
        // Files sidebar has no pane/workspace requirement — open home.
        if paneID == nil, workspaceID == nil {
            return resolveDefaultFilesRoot(connection: connection, remoteAccess: remoteAccess)
        }
        guard let projection else {
            return resolveDefaultFilesRoot(connection: connection, remoteAccess: remoteAccess)
        }

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

        func absoluteCWD(of pane: PaneProjection) -> String? {
            guard let cwd = pane.effectiveCWD, Self.isAbsolutePath(cwd) else { return nil }
            return cwd
        }

        let absoluteCWDs = workspacePanes.compactMap(absoluteCWD)
        let consensusCWD = !workspacePanes.isEmpty
            && absoluteCWDs.count == workspacePanes.count
            && Set(absoluteCWDs).count == 1
            ? absoluteCWDs.first
            : nil

        let selectedOrFocusedPane = selectedPane
            ?? workspacePanes.first(where: \.focused)
            ?? projection.focusedPane.flatMap { focused in
                focused.workspaceID == resolvedWorkspaceID ? focused : nil
            }
            ?? workspacePanes.first

        let selectedCWD = selectedOrFocusedPane.flatMap(absoluteCWD)
        let anyWorkspaceCWD = absoluteCWDs.first
        guard let candidate = consensusCWD ?? selectedCWD ?? anyWorkspaceCWD else {
            return .failure(.missingRoot)
        }

        let resolution: RootResolution
        if consensusCWD != nil {
            resolution = .herdrCwd
        } else if selectedCWD != nil {
            resolution = .selectedPaneCwd
        } else {
            resolution = .agentWorkingDir
        }

        if let remoteAccess {
            let client = SSHRemoteFileClient(access: remoteAccess)
            do {
                let st = try client.stat(candidate)
                guard st.exists else { return .failure(.notDirectory) }
                guard st.isDirectory else { return .failure(.notDirectory) }
                let git = try client.findGitTopLevel(from: candidate)
                let rootURL = URL(fileURLWithPath: candidate, isDirectory: true)
                return .success(WorkspaceFileRoot(
                    connectionID: connection.id,
                    workspaceID: resolvedWorkspaceID,
                    rootURL: rootURL,
                    gitTopLevel: git.map { URL(fileURLWithPath: $0, isDirectory: true) },
                    resolution: resolution,
                    remote: remoteAccess
                ))
            } catch let error as WorkspacePathError {
                return .failure(error)
            } catch {
                return .failure(.unreadable)
            }
        }

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
            resolution: resolution,
            remote: nil
        ))
    }

    public static func resolveContainedPath(
        root: WorkspaceFileRoot,
        relativePath: String
    ) -> Result<URL, WorkspacePathError> {
        guard !Self.isAbsolutePath(relativePath) else { return .failure(.pathEscape) }
        if root.remote != nil {
            switch absolutePath(root: root, relativePath: relativePath) {
            case .failure(let error): return .failure(error)
            case .success(let abs): return .success(URL(fileURLWithPath: abs))
            }
        }

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
        if let remote = root.remote {
            switch absolutePath(root: root, relativePath: relativePath) {
            case .failure(let error): return .failure(error)
            case .success(let abs):
                do {
                    let st = try SSHRemoteFileClient(access: remote).stat(abs)
                    guard st.exists else { return .failure(.notFound) }
                    return .success(URL(fileURLWithPath: abs, isDirectory: st.isDirectory))
                } catch let error as WorkspacePathError {
                    return .failure(error)
                } catch {
                    return .failure(.unreadable)
                }
            }
        }
        let candidate: URL
        if relativePath.isEmpty {
            candidate = root.rootURL.standardizedFileURL.resolvingSymlinksInPath()
        } else {
            switch resolveContainedPath(root: root, relativePath: relativePath) {
            case .success(let url):
                candidate = url
            case .failure(let error):
                return .failure(error)
            }
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return .failure(.notFound) }
        guard FileManager.default.isReadableFile(atPath: candidate.path) else { return .failure(.unreadable) }
        return .success(candidate)
    }

    /// Resolves a contained path without requiring it to exist, so deleted watcher paths can
    /// be validated before presentation or use as a process argument.
    public static func resolvePath(
        root: WorkspaceFileRoot,
        relativePath: String
    ) -> Result<URL, WorkspacePathError> {
        resolveContainedPath(root: root, relativePath: relativePath)
    }

    public static func isIgnoredRelativePath(_ path: String) -> Bool {
        guard !Self.isAbsolutePath(path) else { return false }
        return path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains { ignoredDirectoryNames.contains(String($0)) }
    }


    public static func absolutePath(root: WorkspaceFileRoot, relativePath: String) -> Result<String, WorkspacePathError> {
        guard !Self.isAbsolutePath(relativePath) else { return .failure(.pathEscape) }
        if relativePath.isEmpty { return .success(root.absoluteRootPath) }
        let joined = (root.absoluteRootPath as NSString).appendingPathComponent(relativePath)
        let standardized = URL(fileURLWithPath: joined).standardizedFileURL.path
        let rootPath = URL(fileURLWithPath: root.absoluteRootPath).standardizedFileURL.path
        let rootParts = rootPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let candParts = standardized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard candParts.count >= rootParts.count,
              candParts.prefix(rootParts.count).elementsEqual(rootParts) else {
            return .failure(.pathEscape)
        }
        return .success(standardized)
    }

    public static func materializeLocalURL(root: WorkspaceFileRoot, relativePath: String, maximumByteSize: Int = 40 * 1_024 * 1_024) -> Result<URL, WorkspacePathError> {
        if let remote = root.remote {
            switch absolutePath(root: root, relativePath: relativePath) {
            case .failure(let error): return .failure(error)
            case .success(let abs):
                do { return .success(try SSHRemoteFileClient(access: remote).downloadToTemporaryFile(abs, maximumByteSize: maximumByteSize)) }
                catch let error as WorkspacePathError { return .failure(error) }
                catch { return .failure(.unreadable) }
            }
        }
        return resolveFile(root: root, relativePath: relativePath)
    }

    public static func relativePath(of candidate: URL, under root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.count > rootComponents.count,
              candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents) else { return nil }
        return candidateComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    public static func fileMeta(
        root: WorkspaceFileRoot,
        relativePath: String,
        maximumByteSize: Int? = nil
    ) -> Result<FileContentMeta, WorkspacePathError> {
        do {
            if let remote = root.remote {
                let abs = try absolutePath(root: root, relativePath: relativePath).get()
                let st = try SSHRemoteFileClient(access: remote).stat(abs)
                guard st.exists else { return .failure(.notFound) }
                if st.isDirectory {
                    return .success(FileContentMeta(relativePath: relativePath, byteSize: 0, contentType: nil, kind: .directory))
                }
                guard st.isRegularFile else { return .failure(.unreadable) }
                if let maximumByteSize, st.byteSize > maximumByteSize { return .failure(.tooLarge) }
                let ext = URL(fileURLWithPath: abs).pathExtension.lowercased()
                let contentType = Self.contentType(forExtension: ext)
                let sampleLimit = min(st.byteSize, 8_192)
                let sample = sampleLimit > 0
                    ? try SSHRemoteFileClient(access: remote).readFile(abs, maximumByteSize: sampleLimit)
                    : Data()
                let kind: FilePreviewKind
                if let contentType, contentType.hasPrefix("image/") { kind = .image }
                else if let contentType, contentType.hasPrefix("video/") { kind = .video }
                else if sample.contains(0) || String(data: sample, encoding: .utf8) == nil { kind = .binary }
                else { kind = contentType == "text/markdown" ? .markdown : .text }
                return .success(FileContentMeta(relativePath: relativePath, byteSize: st.byteSize, contentType: contentType, kind: kind))
            }

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
            guard candidate.pathComponents.count > 1 else { return nil }
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
