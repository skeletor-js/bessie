import Foundation

private final class SSHOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Multiplexed OpenSSH access reusing Bessie ControlMaster tunnel.
/// Shell-only remote helper (no Python requirement).
public struct SSHRemoteFileAccess: Equatable, Sendable, Hashable {
    public let host: String
    public let controlPath: String
    public let sshExecutablePath: String
    /// Require the existing mux socket and make direct SSH fallback fail closed.
    public let requireControlMaster: Bool

    public init(
        host: String,
        controlPath: String,
        sshExecutablePath: String = "/usr/bin/ssh",
        requireControlMaster: Bool = false
    ) {
        self.host = host
        self.controlPath = controlPath
        self.sshExecutablePath = sshExecutablePath
        self.requireControlMaster = requireControlMaster
    }

    public var commandArguments: [String] {
        var arguments = SSHHostKeyPolicy.requiredArguments + [
            "-S", controlPath,
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
        ]
        if requireControlMaster {
            arguments += [
                "-o", "ControlMaster=no",
                "-o", "ProxyCommand=/usr/bin/false",
            ]
        }
        arguments.append(host)
        return arguments
    }
}

public struct SSHRemoteFileClient: Sendable {
    public let access: SSHRemoteFileAccess
    private let timeout: TimeInterval

    public init(access: SSHRemoteFileAccess, timeout: TimeInterval = 25) {
        self.access = access
        self.timeout = timeout
    }

    public struct Entry: Equatable, Sendable {
        public let name: String
        public let isDirectory: Bool
        public let isSymbolicLink: Bool
    }

    public struct Stat: Equatable, Sendable {
        public let exists: Bool
        public let isDirectory: Bool
        public let isSymbolicLink: Bool
        public let isRegularFile: Bool
        public let byteSize: Int
        public let modificationDate: Date?
    }

    public func homeDirectory() throws -> String {
        let out = try runRemote("printf '%s\\n' \"$HOME\"").trimmingCharacters(in: .whitespacesAndNewlines)
        guard out.hasPrefix("/") else { throw WorkspacePathError.unreadable }
        return out
    }

    public func canonicalPath(_ absolutePath: String) throws -> String {
        let q = shQuote(absolutePath)
        let script =
            "p=" + q + "; " +
            "if [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then echo __ERR_NOT_FOUND; exit 0; fi; " +
            "realpath \"$p\" 2>/dev/null || readlink -f \"$p\" 2>/dev/null || echo __ERR_UNREADABLE"
        let out = try runRemote(script).trimmingCharacters(in: .whitespacesAndNewlines)
        if out == "__ERR_NOT_FOUND" { throw WorkspacePathError.notFound }
        guard out.hasPrefix("/"), !out.contains("__ERR_UNREADABLE") else {
            throw WorkspacePathError.unreadable
        }
        return out
    }

    public func listDirectory(_ absolutePath: String, limit: Int) throws -> [Entry] {
        let q = shQuote(absolutePath)
        let script =
            "p=" + q + "; " +
            "if [ ! -d \"$p\" ]; then echo __ERR_NOT_DIR; exit 0; fi; " +
            "ls -1A \"$p\" 2>/dev/null | while IFS= read -r name; do " +
            "case \"$name\" in .*|'') continue ;; esac; " +
            "full=\"$p/$name\"; " +
            "if [ -L \"$full\" ]; then k=L; elif [ -d \"$full\" ]; then k=D; else k=F; fi; " +
            "printf '%s\\t%s\\n' \"$k\" \"$name\"; done | head -n " + String(max(0, limit))
        let out = try runRemote(script)
        if out.contains("__ERR_NOT_DIR") { throw WorkspacePathError.notDirectory }
        return out.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return Entry(name: parts[1], isDirectory: parts[0] == "D", isSymbolicLink: parts[0] == "L")
        }
    }

    public func stat(_ absolutePath: String) throws -> Stat {
        let q = shQuote(absolutePath)
        let script =
            "p=" + q + "; " +
            "if [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then echo MISSING; exit 0; fi; " +
            "if [ -L \"$p\" ]; then k=L; elif [ -d \"$p\" ]; then k=D; elif [ -f \"$p\" ]; then k=F; else k=O; fi; " +
            "if stat -f%z / >/dev/null 2>&1; then " +
            "sz=$(stat -f%z \"$p\" 2>/dev/null || echo 0); mt=$(stat -f%m \"$p\" 2>/dev/null || echo 0); " +
            "else sz=$(stat -c%s \"$p\" 2>/dev/null || echo 0); mt=$(stat -c%Y \"$p\" 2>/dev/null || echo 0); fi; " +
            "printf '%s %s %s\\n' \"$k\" \"$sz\" \"$mt\""
        let out = try runRemote(script).trimmingCharacters(in: .whitespacesAndNewlines)
        if out == "MISSING" {
            return Stat(exists: false, isDirectory: false, isSymbolicLink: false, isRegularFile: false, byteSize: 0, modificationDate: nil)
        }
        let parts = out.split(separator: " ")
        guard parts.count >= 3 else { throw WorkspacePathError.unreadable }
        let kind = String(parts[0])
        let size = Int(parts[1]) ?? 0
        let mtime = TimeInterval(parts[2]) ?? 0
        return Stat(
            exists: true,
            isDirectory: kind == "D",
            isSymbolicLink: kind == "L",
            isRegularFile: kind == "F",
            byteSize: size,
            modificationDate: mtime > 0 ? Date(timeIntervalSince1970: mtime) : nil
        )
    }

    public func readFile(_ absolutePath: String, maximumByteSize: Int) throws -> Data {
        let q = shQuote(absolutePath)
        let script =
            "p=" + q + "; " +
            "if [ ! -f \"$p\" ]; then echo __ERR_NOT_FOUND; exit 0; fi; " +
            "head -c " + String(maximumByteSize + 1) + " \"$p\" | (base64 2>/dev/null || base64)"
        let b64 = try runRemote(script).filter { !$0.isWhitespace }
        if b64 == "__ERR_NOT_FOUND" { throw WorkspacePathError.notFound }
        guard let data = Data(base64Encoded: b64) else { throw WorkspacePathError.unreadable }
        guard data.count <= maximumByteSize else { throw WorkspacePathError.tooLarge }
        return data
    }

    public func readContainedFile(
        rootPath: String,
        relativePath: String,
        maximumByteSize: Int
    ) throws -> Data {
        guard !relativePath.hasPrefix("/") else { throw WorkspacePathError.pathEscape }
        let script =
            "root=" + shQuote(rootPath) + "; rel=" + shQuote(relativePath) + "; " +
            "root=$(realpath \"$root\" 2>/dev/null || readlink -f \"$root\" 2>/dev/null) || { echo __ERR_UNREADABLE; exit 0; }; " +
            "candidate=$(realpath \"$root/$rel\" 2>/dev/null || readlink -f \"$root/$rel\" 2>/dev/null) || { echo __ERR_NOT_FOUND; exit 0; }; " +
            "case \"$candidate\" in \"$root\"|\"$root\"/*) ;; *) echo __ERR_ESCAPE; exit 0 ;; esac; " +
            "if [ ! -f \"$candidate\" ]; then echo __ERR_NOT_FOUND; exit 0; fi; " +
            "exec 3< \"$candidate\" || { echo __ERR_UNREADABLE; exit 0; }; " +
            "head -c " + String(maximumByteSize + 1) + " <&3 | (base64 2>/dev/null || base64)"
        let output = try runRemote(script).filter { !$0.isWhitespace }
        switch output {
        case "__ERR_ESCAPE": throw WorkspacePathError.pathEscape
        case "__ERR_NOT_FOUND": throw WorkspacePathError.notFound
        case "__ERR_UNREADABLE": throw WorkspacePathError.unreadable
        default: break
        }
        guard let data = Data(base64Encoded: output) else { throw WorkspacePathError.unreadable }
        guard data.count <= maximumByteSize else { throw WorkspacePathError.tooLarge }
        return data
    }

    public func writeFile(_ absolutePath: String, data: Data) throws {
        let q = shQuote(absolutePath)
        let b64q = shQuote(data.base64EncodedString())
        let script =
            "p=" + q + "; parent=$(dirname \"$p\"); " +
            "if [ ! -d \"$parent\" ]; then echo __ERR_NOT_FOUND; exit 0; fi; " +
            "tmp=\"$p.bessie-tmp-$$\"; " +
            "printf %s " + b64q + " | (base64 -d 2>/dev/null || base64 -D) > \"$tmp\" || { echo __ERR_UNREADABLE; exit 0; }; " +
            "mv -f \"$tmp\" \"$p\"; echo OK"
        let out = try runRemote(script)
        if out.contains("__ERR_NOT_FOUND") { throw WorkspacePathError.notFound }
        if out.contains("__ERR_UNREADABLE") { throw WorkspacePathError.unreadable }
    }

    public func move(from source: String, to destination: String) throws {
        let script =
            "s=" + shQuote(source) + "; d=" + shQuote(destination) + "; " +
            "if [ -L \"$s\" ]; then echo __ERR_SYMLINK; exit 0; fi; " +
            "if [ -e \"$d\" ] || [ -L \"$d\" ]; then echo __ERR_EXISTS; exit 0; fi; " +
            "mkdir -p \"$(dirname \"$d\")\" 2>/dev/null || true; " +
            "mv -f \"$s\" \"$d\" && echo OK || echo __ERR_UNREADABLE"
        let out = try runRemote(script)
        if out.contains("__ERR_SYMLINK") { throw WorkspaceFileOperationError.symbolicLinkUnsupported }
        if out.contains("__ERR_EXISTS") { throw WorkspaceFileOperationError.destinationExists }
        if out.contains("__ERR_") { throw WorkspacePathError.unreadable }
    }

    public func delete(_ absolutePath: String) throws {
        let script =
            "p=" + shQuote(absolutePath) + "; " +
            "if [ -L \"$p\" ]; then echo __ERR_SYMLINK; exit 0; fi; " +
            "if [ ! -e \"$p\" ]; then echo __ERR_NOT_FOUND; exit 0; fi; " +
            "rm -rf \"$p\" && echo OK || echo __ERR_UNREADABLE"
        let out = try runRemote(script)
        if out.contains("__ERR_SYMLINK") { throw WorkspaceFileOperationError.symbolicLinkUnsupported }
        if out.contains("__ERR_NOT_FOUND") { throw WorkspacePathError.notFound }
        if out.contains("__ERR_") { throw WorkspacePathError.unreadable }
    }

    public func findGitTopLevel(from absolutePath: String) throws -> String? {
        let script =
            "cur=" + shQuote(absolutePath) + "; " +
            "while [ -n \"$cur\" ] && [ \"$cur\" != / ]; do " +
            "if [ -e \"$cur/.git\" ]; then printf '%s\\n' \"$cur\"; exit 0; fi; " +
            "cur=$(dirname \"$cur\"); done; printf '\\n'"
        let out = try runRemote(script).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    public func snapshotFiles(root absolutePath: String, ignore: Set<String>, limit: Int = 5000) throws -> [String: (mtime: Date?, size: Int)] {
        let q = shQuote(absolutePath)
        let script =
            "p=" + q + "; if [ ! -d \"$p\" ]; then echo __ERR_NOT_DIR; exit 0; fi; " +
            "find \"$p\" -type f 2>/dev/null | head -n " + String(limit) + " | while IFS= read -r f; do " +
            "rel=${f#\"$p\"/}; case \"$rel\" in .git/*|*/.git/*|node_modules/*|*/node_modules/*|.build/*|*/.build/*) continue ;; esac; " +
            "if stat -f%z / >/dev/null 2>&1; then sz=$(stat -f%z \"$f\" 2>/dev/null||echo 0); mt=$(stat -f%m \"$f\" 2>/dev/null||echo 0); " +
            "else sz=$(stat -c%s \"$f\" 2>/dev/null||echo 0); mt=$(stat -c%Y \"$f\" 2>/dev/null||echo 0); fi; " +
            "printf '%s\\t%s\\t%s\\n' \"$rel\" \"$sz\" \"$mt\"; done"
        let out = try runRemote(script)
        if out.contains("__ERR_NOT_DIR") { throw WorkspacePathError.notDirectory }
        var result: [String: (Date?, Int)] = [:]
        for line in out.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            let mt = TimeInterval(parts[2]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            result[parts[0]] = (mt, Int(parts[1]) ?? 0)
        }
        return result
    }

    public func runGit(arguments: [String], maximumBytes: Int) throws -> (status: Int32, data: Data) {
        let joined = arguments.map(shQuote).joined(separator: " ")
        let script =
            "if ! command -v git >/dev/null 2>&1; then echo STATUS:127; echo; exit 0; fi; " +
            "tmp=$(mktemp 2>/dev/null || echo /tmp/bessie-git-$$); set +e; git " + joined + " >\"$tmp\" 2>&1; st=$?; set -e; " +
            "echo STATUS:$st; head -c " + String(maximumBytes) + " \"$tmp\" | (base64 2>/dev/null || base64); rm -f \"$tmp\""
        let out = try runRemote(script)
        let parts = out.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let statusLine = parts.first, statusLine.hasPrefix("STATUS:") else { throw WorkspacePathError.unreadable }
        let status = Int32(statusLine.dropFirst(7)) ?? 1
        let b64 = parts.count > 1 ? parts[1].filter { !$0.isWhitespace } : ""
        return (status, Data(base64Encoded: b64) ?? Data())
    }

    public func downloadToTemporaryFile(_ absolutePath: String, maximumByteSize: Int = 40 * 1_024 * 1_024) throws -> URL {
        let data = try readFile(absolutePath, maximumByteSize: maximumByteSize)
        let ext = URL(fileURLWithPath: absolutePath).pathExtension
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-remote-media-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "bin" : ext)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private func runRemote(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: access.sshExecutablePath)
        process.arguments = access.commandArguments + ["/bin/sh", "-s"]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() }
        catch { throw BessieConnectionError.sshFailed(error.localizedDescription) }
        let stdoutCapture = SSHOutputCapture()
        let stderrCapture = SSHOutputCapture()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutCapture.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrCapture.append(handle.availableData)
        }
        let body = script.hasSuffix("\n") ? script : script + "\n"
        if let data = body.data(using: .utf8) { stdin.fileHandleForWriting.write(data) }
        try? stdin.fileHandleForWriting.close()
        let deadline = Date(timeIntervalSinceNow: timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw BessieConnectionError.sshFailed("Timed out waiting for remote file operation.")
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutCapture.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrCapture.append(stderr.fileHandleForReading.readDataToEndOfFile())
        let out = stdoutCapture.data
        let err = stderrCapture.data
        guard process.terminationStatus == 0 else {
            let reason = String(data: err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BessieConnectionError.sshFailed(reason?.isEmpty == false ? reason! : "Remote file command failed (\(process.terminationStatus)).")
        }
        return String(data: out, encoding: .utf8) ?? ""
    }

    private func shQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
