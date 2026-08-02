import Foundation

public enum DiffPreviewKind: String, Equatable, Sendable {
    case text
    case binary
    case unavailable
}

public struct DiffPreview: Equatable, Sendable {
    public let relativePath: String
    public let kind: DiffPreviewKind
    public let text: String?
    public let banner: String?

    public init(relativePath: String, kind: DiffPreviewKind, text: String? = nil, banner: String? = nil) {
        self.relativePath = relativePath
        self.kind = kind
        self.text = text
        self.banner = banner
    }
}

public struct GitDiffService: Sendable {
    public static let defaultMaximumTextBytes = 1_500_000

    private let gitExecutableURL: URL
    private let timeout: TimeInterval
    private let maximumTextBytes: Int

    public init(
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        timeout: TimeInterval = 3,
        maximumTextBytes: Int = defaultMaximumTextBytes
    ) {
        self.gitExecutableURL = gitExecutableURL
        self.timeout = timeout
        self.maximumTextBytes = maximumTextBytes
    }

    public func preview(root: WorkspaceFileRoot, relativePath: String) -> DiffPreview {
        let target: URL
        switch WorkspaceFS.resolvePath(root: root, relativePath: relativePath) {
        case let .success(url): target = url
        case .failure:
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: "Path is outside the workspace")
        }

        guard let gitTopLevel = root.gitTopLevel else {
            return fullFilePreview(target: target, relativePath: relativePath, banner: "No git baseline")
        }
        let gitRoot = gitTopLevel.standardizedFileURL.resolvingSymlinksInPath()
        guard let gitPath = WorkspaceFS.relativePath(of: target, under: gitRoot) else {
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: "Git baseline is unavailable")
        }

        let status = runGit(["-C", gitRoot.path, "status", "--porcelain=v1", "--untracked-files=all", "--", gitPath])
        guard status.succeeded, let statusText = String(data: status.data, encoding: .utf8) else {
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: status.timedOut ? "Git diff timed out" : "Git baseline is unavailable")
        }
        guard !statusText.isEmpty else {
            return DiffPreview(relativePath: relativePath, kind: .text, text: "", banner: "No changes from git HEAD")
        }
        if statusText.hasPrefix("??") {
            return fullFilePreview(target: target, relativePath: relativePath, banner: "Untracked file; shown as added")
        }

        let diff = runGit(["-C", gitRoot.path, "diff", "--no-ext-diff", "--no-textconv", "HEAD", "--", gitPath])
        guard diff.succeeded else {
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: diff.timedOut ? "Git diff timed out" : "Git diff is unavailable")
        }
        guard diff.data.count <= maximumTextBytes else {
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: "Diff exceeds the text preview limit")
        }
        guard let text = String(data: diff.data, encoding: .utf8) else {
            return DiffPreview(relativePath: relativePath, kind: .binary, banner: "Binary file")
        }
        if text.contains("Binary files ") || text.contains("GIT binary patch") {
            return DiffPreview(relativePath: relativePath, kind: .binary, banner: "Binary file")
        }
        return DiffPreview(relativePath: relativePath, kind: .text, text: text, banner: "Compared with git HEAD")
    }

    private func fullFilePreview(target: URL, relativePath: String, banner: String) -> DiffPreview {
        guard let values = try? target.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: "File is unavailable")
        }
        guard fileSize <= maximumTextBytes else {
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: "File exceeds the text preview limit")
        }
        guard let data = try? Data(contentsOf: target, options: [.mappedIfSafe]) else {
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: "File is unavailable")
        }
        guard data.count <= maximumTextBytes else {
            return DiffPreview(relativePath: relativePath, kind: .unavailable, banner: "File exceeds the text preview limit")
        }
        guard !data.contains(0), let content = String(data: data, encoding: .utf8) else {
            return DiffPreview(relativePath: relativePath, kind: .binary, banner: "Binary file")
        }
        let added = content.split(separator: "\n", omittingEmptySubsequences: false).map { "+\($0)" }.joined(separator: "\n")
        return DiffPreview(relativePath: relativePath, kind: .text, text: "--- /dev/null\n+++ \(relativePath)\n\(added)", banner: banner)
    }

    private func runGit(_ arguments: [String]) -> (succeeded: Bool, timedOut: Bool, data: Data) {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("bessie-git-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else { return (false, false, Data()) }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = gitExecutableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { return (false, false, Data()) }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let timedOut = process.isRunning
        if timedOut { process.terminate() }
        process.waitUntilExit()
        try? output.synchronize()
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return (!timedOut && process.terminationStatus == 0, timedOut, data)
    }
}
