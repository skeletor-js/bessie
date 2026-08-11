import CryptoKit
import Darwin
import Foundation

public enum SSHHostKeyPolicy {
    /// Explicitly overrides unsafe user SSH configuration. Changed or unknown keys fail closed.
    public static let requiredArguments = ["-o", "StrictHostKeyChecking=yes"]
}

public struct RemoteHerdrBridgePlan: Equatable, Sendable {
    public let connection: BessieConnectionDefinition
    public let localSocketPath: String
    public let localClientSocketPath: String
    public let localControlPath: String
    public let remoteSocketPath: String
    public let remoteClientSocketPath: String

    /// Keep the multiplexed master briefly after Bessie tears down its -N helper so
    /// the next launch can skip a cold TCP/SSH handshake.
    public static let controlPersistSeconds = 600

    public init(connection: BessieConnectionDefinition, localDirectory: URL, remoteSocketPath: String) throws {
        self.connection = try connection.validated()
        guard connection.kind == .ssh, connection.sshHost != nil else {
            throw BessieConnectionError.invalidSSHHost
        }
        localSocketPath = localDirectory.appendingPathComponent("herdr.sock").path
        localClientSocketPath = localDirectory.appendingPathComponent("herdr-client.sock").path
        localControlPath = localDirectory.appendingPathComponent("ssh-control.sock").path
        self.remoteSocketPath = remoteSocketPath
        remoteClientSocketPath = URL(fileURLWithPath: remoteSocketPath)
            .deletingLastPathComponent()
            .appendingPathComponent("herdr-client.sock").path
    }

    public var sshArguments: [String] {
        guard let host = connection.sshHost else { return [] }
        return SSHHostKeyPolicy.requiredArguments + [
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StreamLocalBindUnlink=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=\(Self.controlPersistSeconds)",
            "-o", "ControlPath=\(localControlPath)",
            "-o", "ConnectTimeout=8",
            "-L", "\(localSocketPath):\(remoteSocketPath)",
            "-L", "\(localClientSocketPath):\(remoteClientSocketPath)",
            "-N", host,
        ]
    }

    public static func remoteStatusCommand(for connection: BessieConnectionDefinition) -> String {
        let session = connection.session.map { " --session \($0)" } ?? ""
        return "herdr\(session) status --json"
    }

    public static func remoteStatusArguments(
        for connection: BessieConnectionDefinition,
        controlPath: String? = nil
    ) -> [String] {
        guard let host = connection.sshHost else { return [] }
        var args = SSHHostKeyPolicy.requiredArguments + [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
        ]
        if let controlPath, !controlPath.isEmpty {
            args += [
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=\(controlPersistSeconds)",
                "-o", "ControlPath=\(controlPath)",
            ]
        }
        args += [host, remoteStatusCommand(for: connection)]
        return args
    }

    /// Bootstrap only. A forced PTY is required by Herdr attach; `cd --` is
    /// positional-shell quoted and the selected directory is validated first.
    public static func remoteAttachArguments(for connection: BessieConnectionDefinition, session: String, directory: String) throws -> [String] {
        let validated = try connection.validated()
        guard let host = validated.sshHost, BessieConnectionDefinition.isSafeSession(session) else {
            throw BessieConnectionError.invalidSession
        }
        let cwd = try OnboardingPathValidator.absolute(directory)
        let quoted = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return SSHHostKeyPolicy.requiredArguments + ["-o", "BatchMode=yes", "-tt", host, "cd -- \(quoted) && exec herdr session attach \(session)"]
    }
}

public final class RemoteHerdrBridge: @unchecked Sendable {
    private static let openSSHSuffixHeadroom = 17

    public let connection: BessieConnectionDefinition
    private let sshPath: String
    private let cacheRoot: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var tunnelProcess: Process?
    private var localDirectory: URL?

    /// Active multiplexed SSH file access while the tunnel is up.
    public var fileAccess: SSHRemoteFileAccess? {
        lock.withLock {
            guard let directory = localDirectory,
                  let host = connection.sshHost else { return nil }
            let control = directory.appendingPathComponent("ssh-control.sock").path
            guard fileManager.fileExists(atPath: control) else { return nil }
            return SSHRemoteFileAccess(host: host, controlPath: control, sshExecutablePath: sshPath)
        }
    }

    public init(
        connection: BessieConnectionDefinition,
        sshPath: String = "/usr/bin/ssh",
        cacheRoot: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.connection = try connection.validated()
        guard connection.kind == .ssh else { throw BessieConnectionError.invalidSSHHost }
        self.sshPath = sshPath
        self.fileManager = fileManager
        self.cacheRoot = cacheRoot ?? Self.defaultCacheRootURL
        let controlPath = Self.localDirectoryURL(connectionID: connection.id, cacheRoot: self.cacheRoot)
            .appendingPathComponent("ssh-control.sock").path
        guard controlPath.utf8.count + Self.openSSHSuffixHeadroom < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw BessieConnectionError.tunnelFailed("The local SSH control path is too long.")
        }
    }

    deinit { stop(removeCacheDirectory: false) }

    public func start() throws -> String {
        let directory = Self.localDirectoryURL(connectionID: connection.id, cacheRoot: cacheRoot)
        try prepareDirectory(directory)

        // 1) Healthy existing forwards (same process or ControlPersist master) — no SSH spawn.
        if let ready = readySocketPath(in: directory) {
            lock.withLock { localDirectory = directory }
            return ready
        }

        // 2) Cached remote socket: open/reuse tunnel without a status round-trip.
        if let cachedRemote = cachedRemoteSocketPath(in: directory) {
            do {
                if let ready = try openTunnel(remoteSocketPath: cachedRemote, directory: directory) {
                    return ready
                }
            } catch {
                // Stale cache or flaky master — fall through to a fresh status probe.
            }
        }

        // 3) Cold path: status (multiplexed when a control master already exists), then tunnel.
        let status = try remoteStatus(controlPath: directory.appendingPathComponent("ssh-control.sock").path)
        guard status.running, let remoteSocket = status.socket, !remoteSocket.isEmpty else {
            throw BessieConnectionError.remoteHerdrUnavailable(
                "Start the selected Herdr session on \(connection.sshHost ?? "the remote host"), then try again."
            )
        }
        storeCachedRemoteSocketPath(remoteSocket, in: directory)
        if let ready = try openTunnel(remoteSocketPath: remoteSocket, directory: directory) {
            return ready
        }
        throw BessieConnectionError.tunnelFailed("Timed out waiting for local sockets.")
    }

    public func stop() {
        stop(removeCacheDirectory: false)
    }

    /// Tears down the local -N helper. Keeps the ControlPersist master and cached remote
    /// socket path so the next connect can skip status + cold handshake.
    private func stop(removeCacheDirectory: Bool) {
        let state = lock.withLock { () -> (Process?, URL?) in
            defer {
                tunnelProcess = nil
                if removeCacheDirectory { localDirectory = nil }
            }
            return (tunnelProcess, localDirectory)
        }
        if let process = state.0, process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { Self.killAndReap(process) }
        }
        if removeCacheDirectory, let directory = state.1 {
            try? fileManager.removeItem(at: directory)
        }
    }

    public static var defaultCacheRootURL: URL {
        URL(fileURLWithPath: "/private/tmp/.bessie-\(getuid())", isDirectory: true)
    }

    public static func localDirectoryURL(connectionID: String, cacheRoot: URL) -> URL {
        let digest = SHA256.hash(data: Data(connectionID.utf8))
        let token = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return cacheRoot.appendingPathComponent(".r-\(token)", isDirectory: true)
    }

    private func prepareDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheRoot.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        lock.withLock { localDirectory = directory }
    }

    private func readySocketPath(in directory: URL) -> String? {
        let localSocketPath = directory.appendingPathComponent("herdr.sock").path
        let localClientSocketPath = directory.appendingPathComponent("herdr-client.sock").path
        guard fileManager.fileExists(atPath: localSocketPath),
              fileManager.fileExists(atPath: localClientSocketPath),
              (try? HerdrSocketAPI(socketPath: localSocketPath).ping()) != nil
        else { return nil }
        return localSocketPath
    }

    private func openTunnel(remoteSocketPath: String, directory: URL) throws -> String? {
        let plan = try RemoteHerdrBridgePlan(
            connection: connection,
            localDirectory: directory,
            remoteSocketPath: remoteSocketPath
        )

        // Drop only stale local socket nodes; keep control master when ControlPersist holds it.
        for name in ["herdr.sock", "herdr-client.sock"] {
            let path = directory.appendingPathComponent(name).path
            if fileManager.fileExists(atPath: path) {
                try? fileManager.removeItem(atPath: path)
            }
        }

        // If a master is already up, a short-lived -N with ControlMaster=auto attaches forwards.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = plan.sshArguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        do { try process.run() }
        catch { throw BessieConnectionError.sshFailed(error.localizedDescription) }

        lock.withLock {
            tunnelProcess = process
            localDirectory = directory
        }

        // Tight early poll; ping only once both local sockets exist.
        let intervals: [TimeInterval] = [
            0.0, 0.02, 0.02, 0.03, 0.05, 0.05, 0.05,
            0.1, 0.1, 0.1, 0.1, 0.1, 0.1,
            0.15, 0.15, 0.2, 0.2, 0.25, 0.25, 0.3, 0.3, 0.4, 0.5, 0.5,
        ]
        for delay in intervals {
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            if !process.isRunning {
                // ControlPersist master may still own forwards after helper exits — check sockets.
                if fileManager.fileExists(atPath: plan.localSocketPath),
                   fileManager.fileExists(atPath: plan.localClientSocketPath),
                   (try? HerdrSocketAPI(socketPath: plan.localSocketPath).ping()) != nil {
                    return plan.localSocketPath
                }
                let reason = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "SSH exited."
                lock.withLock { tunnelProcess = nil }
                throw BessieConnectionError.tunnelFailed(reason.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if fileManager.fileExists(atPath: plan.localSocketPath),
               fileManager.fileExists(atPath: plan.localClientSocketPath),
               (try? HerdrSocketAPI(socketPath: plan.localSocketPath).ping()) != nil {
                return plan.localSocketPath
            }
        }
        stop(removeCacheDirectory: false)
        return nil
    }

    private func cachedRemoteSocketPath(in directory: URL) -> String? {
        let url = directory.appendingPathComponent("remote-socket.path")
        guard let value = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.hasPrefix("/")
        else { return nil }
        return value
    }

    private func storeCachedRemoteSocketPath(_ path: String, in directory: URL) {
        let url = directory.appendingPathComponent("remote-socket.path")
        try? path.write(to: url, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func remoteStatus(controlPath: String?) throws -> RemoteStatus {
        let data = try runRemote(
            arguments: RemoteHerdrBridgePlan.remoteStatusArguments(for: connection, controlPath: controlPath),
            timeout: 10
        )
        do { return try JSONDecoder().decode(RemoteStatusEnvelope.self, from: data).server }
        catch { throw BessieConnectionError.remoteHerdrUnavailable("Invalid status response: \(error.localizedDescription)") }
    }

    private func runRemote(arguments: [String], timeout: TimeInterval) throws -> Data {
        guard !arguments.isEmpty else { throw BessieConnectionError.invalidSSHHost }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = arguments
        let output = Pipe(); let errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        do { try process.run() }
        catch { throw BessieConnectionError.sshFailed(error.localizedDescription) }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { Self.killAndReap(process) }
            throw BessieConnectionError.sshFailed("Timed out waiting for SSH.")
        }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let reason = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BessieConnectionError.sshFailed(reason?.isEmpty == false ? reason! : "SSH exited \(process.terminationStatus).")
        }
        return stdout
    }

    private static func killAndReap(_ process: Process) {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }
}

private struct RemoteStatusEnvelope: Decodable { let server: RemoteStatus }
private struct RemoteStatus: Decodable {
    let running: Bool
    let socket: String?
}
