import Foundation

public struct WorkspaceBrowserItem: Identifiable, Equatable, Sendable {
    public let relativePath: String
    public let name: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public var id: String { relativePath }

    public init(relativePath: String, name: String, isDirectory: Bool, isSymbolicLink: Bool = false) {
        self.relativePath = relativePath
        self.name = name
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
    }
}

public struct WorkspaceFileRevision: Equatable, Sendable {
    public let modificationDate: Date
    public let byteSize: Int
    public let contentFingerprint: UInt64
}

public struct WorkspaceTextDocument: Equatable, Sendable {
    public let text: String
    public let revision: WorkspaceFileRevision
}

public enum WorkspaceFileOperationError: Error, Equatable, Sendable {
    case staleRevision
    case invalidUTF8
    case notMarkdown
    case destinationExists
    case symbolicLinkUnsupported
}

public enum WorkspaceFileOps {
    public static let defaultListLimit = 2_000
    public static let defaultTextByteLimit = 2 * 1_024 * 1_024

    public static func list(
        root: WorkspaceFileRoot,
        relativeDirectory: String = "",
        limit: Int = defaultListLimit,
        fileManager: FileManager = .default
    ) throws -> [WorkspaceBrowserItem] {
        if let remote = root.remote {
            let abs = try WorkspaceFS.resolveFile(root: root, relativePath: relativeDirectory).get().path
            let entries = try SSHRemoteFileClient(access: remote).listDirectory(abs, limit: limit)
            return entries.compactMap { entry in
                let relativePath = relativeDirectory.isEmpty ? entry.name : "\(relativeDirectory)/\(entry.name)"
                guard !WorkspaceFS.isIgnoredRelativePath(relativePath) else { return nil }
                return WorkspaceBrowserItem(
                    relativePath: relativePath,
                    name: entry.name,
                    isDirectory: entry.isDirectory,
                    isSymbolicLink: entry.isSymbolicLink
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }

        let directory = try WorkspaceFS.resolveFile(root: root, relativePath: relativeDirectory).get()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            let relativePath = relativeDirectory.isEmpty ? url.lastPathComponent : "\(relativeDirectory)/\(url.lastPathComponent)"
            guard !WorkspaceFS.isIgnoredRelativePath(relativePath) else { return nil }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // Never browse through directory symlinks; file resolution still safely handles file links.
            let isSymbolicLink = values.isSymbolicLink == true
            let isDirectory = values.isDirectory == true && !isSymbolicLink
            return WorkspaceBrowserItem(
                relativePath: relativePath,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    public static func loadText(
        root: WorkspaceFileRoot,
        relativePath: String,
        maximumByteSize: Int = defaultTextByteLimit
    ) throws -> WorkspaceTextDocument {
        if let remote = root.remote {
            let abs = try WorkspaceFS.resolveFile(root: root, relativePath: relativePath).get().path
            let client = SSHRemoteFileClient(access: remote)
            let st = try client.stat(abs)
            guard st.exists, st.isRegularFile else { throw WorkspacePathError.notFound }
            guard st.byteSize <= maximumByteSize else { throw WorkspacePathError.tooLarge }
            let data = try client.readFile(abs, maximumByteSize: maximumByteSize)
            guard let text = String(data: data, encoding: .utf8) else { throw WorkspaceFileOperationError.invalidUTF8 }
            return WorkspaceTextDocument(text: text, revision: revision(data: data, date: st.modificationDate ?? .distantPast, size: st.byteSize))
        }
        let url = try WorkspaceFS.resolveFile(root: root, relativePath: relativePath).get()
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let byteSize = values.fileSize else { throw WorkspacePathError.notFound }
        guard byteSize <= maximumByteSize else { throw WorkspacePathError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = String(data: data, encoding: .utf8) else { throw WorkspaceFileOperationError.invalidUTF8 }
        return WorkspaceTextDocument(text: text, revision: try revision(of: url, data: data))
    }

    @discardableResult
    public static func saveMarkdown(
        root: WorkspaceFileRoot,
        relativePath: String,
        text: String,
        expected: WorkspaceFileRevision,
        allowOverwrite: Bool = false
    ) throws -> WorkspaceFileRevision {
        try rejectSymbolicLink(root: root, relativePath: relativePath)
        guard try WorkspaceFS.fileMeta(root: root, relativePath: relativePath).get().kind == .markdown else {
            throw WorkspaceFileOperationError.notMarkdown
        }
        if let remote = root.remote {
            let abs = try WorkspaceFS.absolutePath(root: root, relativePath: relativePath).get()
            let client = SSHRemoteFileClient(access: remote)
            let st = try client.stat(abs)
            guard st.exists, st.isRegularFile else { throw WorkspacePathError.notFound }
            if st.isSymbolicLink { throw WorkspaceFileOperationError.symbolicLinkUnsupported }
            let currentData = try client.readFile(abs, maximumByteSize: defaultTextByteLimit * 2)
            let current = revision(data: currentData, date: st.modificationDate ?? .distantPast, size: st.byteSize)
            if !allowOverwrite, current != expected { throw WorkspaceFileOperationError.staleRevision }
            let data = Data(text.utf8)
            try client.writeFile(abs, data: data)
            let after = try client.stat(abs)
            return revision(data: data, date: after.modificationDate ?? Date(), size: after.byteSize)
        }
        let url = try WorkspaceFS.resolveFile(root: root, relativePath: relativePath).get()
        if !allowOverwrite, try revision(of: url) != expected { throw WorkspaceFileOperationError.staleRevision }
        try Data(text.utf8).write(to: url, options: [.atomic])
        return try revision(of: url)
    }

    public static func move(
        root: WorkspaceFileRoot,
        from sourcePath: String,
        to destinationPath: String,
        fileManager: FileManager = .default
    ) throws {
        try rejectSymbolicLink(root: root, relativePath: sourcePath)
        if let remote = root.remote {
            let src = try WorkspaceFS.absolutePath(root: root, relativePath: sourcePath).get()
            let dst = try WorkspaceFS.absolutePath(root: root, relativePath: destinationPath).get()
            try SSHRemoteFileClient(access: remote).move(from: src, to: dst)
            return
        }
        let source = try WorkspaceFS.resolveFile(root: root, relativePath: sourcePath).get()
        let destination = try destinationURL(root: root, relativePath: destinationPath)
        guard !fileManager.fileExists(atPath: destination.path) else { throw WorkspaceFileOperationError.destinationExists }
        try fileManager.moveItem(at: source, to: destination)
    }

    public static func delete(
        root: WorkspaceFileRoot,
        relativePath: String,
        trash: (URL) throws -> Void
    ) throws {
        try rejectSymbolicLink(root: root, relativePath: relativePath)
        if let remote = root.remote {
            let abs = try WorkspaceFS.absolutePath(root: root, relativePath: relativePath).get()
            guard abs != root.absoluteRootPath else { throw WorkspacePathError.pathEscape }
            try SSHRemoteFileClient(access: remote).delete(abs)
            return
        }
        let url = try WorkspaceFS.resolveFile(root: root, relativePath: relativePath).get()
        guard url != root.rootURL.resolvingSymlinksInPath() else { throw WorkspacePathError.pathEscape }
        try trash(url)
    }

    private static func destinationURL(root: WorkspaceFileRoot, relativePath: String) throws -> URL {
        guard !NSString(string: relativePath).isAbsolutePath, !relativePath.isEmpty else { throw WorkspacePathError.pathEscape }
        let raw = root.rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let parent = raw.deletingLastPathComponent()
        let parentRelative = parent.path.replacingOccurrences(of: root.rootURL.standardizedFileURL.path + "/", with: "")
        let safeParent = parent == root.rootURL.standardizedFileURL
            ? root.rootURL.resolvingSymlinksInPath()
            : try WorkspaceFS.resolveFile(root: root, relativePath: parentRelative).get()
        let candidate = safeParent.appendingPathComponent(raw.lastPathComponent).standardizedFileURL
        let rootComponents = root.rootURL.resolvingSymlinksInPath().pathComponents
        guard candidate.pathComponents.prefix(rootComponents.count).elementsEqual(rootComponents) else {
            throw WorkspacePathError.pathEscape
        }
        return candidate
    }

    private static func rejectSymbolicLink(root: WorkspaceFileRoot, relativePath: String) throws {
        guard !NSString(string: relativePath).isAbsolutePath else { throw WorkspacePathError.pathEscape }
        if let remote = root.remote {
            let abs = try WorkspaceFS.absolutePath(root: root, relativePath: relativePath).get()
            let st = try SSHRemoteFileClient(access: remote).stat(abs)
            if st.isSymbolicLink { throw WorkspaceFileOperationError.symbolicLinkUnsupported }
            return
        }
        let rootURL = root.rootURL.standardizedFileURL
        let lexicalURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootComponents = rootURL.pathComponents
        guard lexicalURL.pathComponents.prefix(rootComponents.count).elementsEqual(rootComponents) else {
            throw WorkspacePathError.pathEscape
        }
        if try lexicalURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw WorkspaceFileOperationError.symbolicLinkUnsupported
        }
    }

    private static func revision(data: Data, date: Date, size: Int) -> WorkspaceFileRevision {
        let fingerprint = data.reduce(UInt64(1_469_598_103_934_665_603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return WorkspaceFileRevision(modificationDate: date, byteSize: size, contentFingerprint: fingerprint)
    }

    private static func revision(of url: URL) throws -> WorkspaceFileRevision {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try revision(of: url, data: data)
    }

    private static func revision(of url: URL, data: Data) throws -> WorkspaceFileRevision {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let date = values.contentModificationDate, let size = values.fileSize else { throw WorkspacePathError.notFound }
        let fingerprint = data.reduce(UInt64(1_469_598_103_934_665_603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return WorkspaceFileRevision(
            modificationDate: date,
            byteSize: size,
            contentFingerprint: fingerprint
        )
    }
}
