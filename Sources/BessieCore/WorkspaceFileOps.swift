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
