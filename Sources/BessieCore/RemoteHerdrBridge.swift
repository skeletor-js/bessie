import Darwin
import Foundation

public struct RemoteHerdrBridgePlan: Equatable, Sendable {
    public let connection: BessieConnectionDefinition
    public let localSocketPath: String
    public let localClientSocketPath: String
    public let localControlPath: String
    public let remoteSocketPath: String
    public let remoteClientSocketPath: String

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
        return [
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StreamLocalBindUnlink=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "ControlMaster=yes",
            "-o", "ControlPersist=no",
            "-o", "ControlPath=\(localControlPath)",
            "-L", "\(localSocketPath):\(remoteSocketPath)",
            "-L", "\(localClientSocketPath):\(remoteClientSocketPath)",
            "-N", host,
        ]
    }

    public static func remoteStatusCommand(for connection: BessieConnectionDefinition) -> String {
        let session = connection.session.map { " --session \($0)" } ?? ""
        return "herdr\(session) status --json"
    }

    public static func remoteStatusArguments(for connection: BessieConnectionDefinition) -> [String] {
        guard let host = connection.sshHost else { return [] }
        return [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            host,
            remoteStatusCommand(for: connection),
        ]
    }
}

public final class RemoteHerdrBridge: @unchecked Sendable {
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
        self.cacheRoot = cacheRoot ?? URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("bessie-\(NSUserName())", isDirectory: true)
    }

    deinit { stop() }

    public func start() throws -> String {
        stop()
        let status = try remoteStatus()
        guard status.running, let remoteSocket = status.socket, !remoteSocket.isEmpty else {
            throw BessieConnectionError.remoteHerdrUnavailable(
                "Start the selected Herdr session on \(connection.sshHost ?? "the remote host"), then try again."
            )
        }

        let directory = cacheRoot.appendingPathComponent(safeID, isDirectory: true)
        stopStaleTunnel(in: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheRoot.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        for name in ["herdr.sock", "herdr-client.sock", "ssh-control.sock"] {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        let plan = try RemoteHerdrBridgePlan(
            connection: connection,
            localDirectory: directory,
            remoteSocketPath: remoteSocket
        )

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
        for _ in 0..<60 {
            if !process.isRunning {
                let reason = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "SSH exited."
                stop()
                throw BessieConnectionError.tunnelFailed(reason.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if fileManager.fileExists(atPath: plan.localSocketPath),
               fileManager.fileExists(atPath: plan.localClientSocketPath),
               (try? HerdrSocketAPI(socketPath: plan.localSocketPath).ping()) != nil {
                return plan.localSocketPath
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        stop()
        throw BessieConnectionError.tunnelFailed("Timed out waiting for local sockets.")
    }

    public func stop() {
        let state = lock.withLock { () -> (Process?, URL?) in
            defer { tunnelProcess = nil; localDirectory = nil }
            return (tunnelProcess, localDirectory)
        }
        if let process = state.0, process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { Self.killAndReap(process) }
        }
        if let directory = state.1 { try? fileManager.removeItem(at: directory) }
    }

    private var safeID: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let mapped = connection.id.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        return String(mapped)
    }

    private func stopStaleTunnel(in directory: URL) {
        let controlPath = directory.appendingPathComponent("ssh-control.sock").path
        guard fileManager.fileExists(atPath: controlPath), let host = connection.sshHost else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = ["-S", controlPath, "-O", "exit", host]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        for _ in 0..<40 where process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { Self.killAndReap(process) }
    }

    private func remoteStatus() throws -> RemoteStatus {
        let data = try runRemote(
            arguments: RemoteHerdrBridgePlan.remoteStatusArguments(for: connection),
            timeout: 12
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
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
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
