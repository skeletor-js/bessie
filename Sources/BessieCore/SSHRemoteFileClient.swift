import Foundation

/// Multiplexed OpenSSH access reusing Bessie ControlMaster tunnel.
/// Shell-only remote helper (no Python requirement).
public struct SSHRemoteFileAccess: Equatable, Sendable, Hashable {
    public let host: String
    public let controlPath: String
    public let sshExecutablePath: String

    public init(host: String, controlPath: String, sshExecutablePath: String = "/usr/bin/ssh") {
        self.host = host
        self.controlPath = controlPath
        self.sshExecutablePath = sshExecutablePath
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
        let st = try stat(absolutePath)
        guard st.exists else { throw WorkspacePathError.notFound }
        guard st.isRegularFile else { throw WorkspacePathError.notFound }
        guard st.byteSize <= maximumByteSize else { throw WorkspacePathError.tooLarge }
        let q = shQuote(absolutePath)
        let script = "p=" + q + "; (base64 < \"$p\" 2>/dev/null || base64 < \"$p\")"
        let b64 = try runRemote(script).filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: b64) else { throw WorkspacePathError.unreadable }
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-remote-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "bin" : ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func runRemote(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: access.sshExecutablePath)
        process.arguments = [
            "-S", access.controlPath,
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            access.host,
            "/bin/sh", "-s",
        ]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() }
        catch { throw BessieConnectionError.sshFailed(error.localizedDescription) }
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
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
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
