import Foundation
#if os(macOS)
import Darwin
#endif

public struct RemoteBootstrapCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data = Data(), stderr: Data = Data()) {
        self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr
    }
}

public protocol RemoteBootstrapProcess: AnyObject, Sendable {
    var isRunning: Bool { get }
    func stop()
}

public struct RemoteBootstrapResult: Equatable, Sendable {
    public let connection: BessieConnectionDefinition
    public let workspaceID: String
    public let tabID: String
    public let paneID: String
}

public enum RemoteBootstrapError: Error, Equatable, LocalizedError {
    case collision(String), commandFailed(String), invalidPath(String), attachExited
    case statusNotReady, incompatible(String), ambiguousTopology

    public var errorDescription: String? {
        switch self {
        case .collision(let name): "A Herdr session named \(name) already exists on this host. Start setup again to use a new session name."
        case .commandFailed(let detail): "Remote validation failed. \(detail)"
        case .invalidPath(let path): "The remote folder \(path) does not exist, is not a directory, or is not usable. Choose another folder."
        case .attachExited: "The remote Herdr attach client exited before the detached server was ready. Resume setup to try again."
        case .statusNotReady: "The new remote Herdr session did not become independently ready. Resume setup to try again."
        case .incompatible(let detail): "The remote Herdr session is incompatible. \(detail)"
        case .ambiguousTopology: "Herdr did not report exactly one initial workspace, tab, and pane at the selected folder. The session was not adopted."
        }
    }
}

/// Public Herdr/OpenSSH-only lifecycle for the fresh session created by onboarding.
public final class RemoteOnboardingBootstrap: @unchecked Sendable {
    public typealias Command = @Sendable (_ arguments: [String], _ stdin: Data?) throws -> RemoteBootstrapCommandResult
    public typealias Attach = @Sendable (_ arguments: [String]) throws -> any RemoteBootstrapProcess
    public typealias Snapshot = @Sendable (_ connection: BessieConnectionDefinition) throws -> HerdrSnapshot
    public typealias Register = @Sendable (_ connection: BessieConnectionDefinition) throws -> Void
    public typealias Log = @Sendable (_ line: String) -> Void

    private let command: Command
    private let attach: Attach
    private let snapshot: Snapshot
    private let register: Register
    private let pollCount: Int
    private let sleep: @Sendable () -> Void
    private let readinessTimeout: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let log: Log

    public init(command: @escaping Command, attach: @escaping Attach, snapshot: @escaping Snapshot,
                register: @escaping Register = { _ in }, pollCount: Int = 900,
                sleep: @escaping @Sendable () -> Void = { Thread.sleep(forTimeInterval: 0.1) },
                readinessTimeout: TimeInterval = 90,
                now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                log: @escaping Log = { _ in }) {
        self.command = command; self.attach = attach; self.snapshot = snapshot
        self.register = register; self.pollCount = pollCount; self.sleep = sleep
        self.readinessTimeout = readinessTimeout; self.now = now; self.log = log
    }

    public func bootstrap(definition: BessieConnectionDefinition, path: String, sessionName: String,
                          expectedIDs: (String, String, String)? = nil) throws -> RemoteBootstrapResult {
        let started = now()
        let elapsed: @Sendable () -> String = { [now] in String(format: "%.1fs", now() - started) }
        let base = try definition.validated()
        guard base.kind == .ssh, let host = base.sshHost,
              BessieConnectionDefinition.isSafeSession(sessionName) else { throw BessieConnectionError.invalidSession }
        let selectedPath = try OnboardingPathValidator.absolute(path)
        let connection = try BessieConnectionDefinition(id: sessionName, name: base.name, kind: .ssh,
                                                        sshHost: host, session: sessionName).validated()

        // A resumed attempt with authoritative exact IDs must only reconcile; it must never attach twice.
        if let expectedIDs, let accepted = try? accept(snapshot(connection), connection: connection,
                                                       path: selectedPath, expectedIDs: expectedIDs) {
            log("bootstrap session=\(sessionName): reconciled existing materialized session without attach (\(elapsed()))")
            return accepted
        }

        log("bootstrap session=\(sessionName): session-list start")
        let initial = try command(Self.sessionListArguments(host: host), nil)
        log("bootstrap session=\(sessionName): session-list exit=\(initial.exitCode) (\(elapsed()))")
        guard initial.exitCode == 0 else { throw commandFailure(initial) }
        let listed: RemoteSessionList
        do { listed = try JSONDecoder().decode(RemoteSessionList.self, from: initial.stdout) }
        catch { throw RemoteBootstrapError.commandFailed("Herdr returned invalid session-list JSON: \(error.localizedDescription)") }
        if listed.sessions.contains(where: { $0.name == sessionName }) {
            let existing = try command(Self.statusArguments(host: host, session: sessionName), nil)
            guard existing.exitCode == 0 else { throw RemoteBootstrapError.collision(sessionName) }
            let status = try Self.decodeStatus(existing.stdout)
            guard status.running,
                  status.session == sessionName,
                  status.detachedServerDaemon,
                  status.version == BessieCompatibility.herdrVersion,
                  status.protocolVersion == BessieCompatibility.protocolVersion else {
                throw RemoteBootstrapError.collision(sessionName)
            }
            let accepted = try accept(
                snapshot(connection),
                connection: connection,
                path: selectedPath,
                expectedIDs: expectedIDs
            )
            try register(connection)
            return accepted
        }

        log("bootstrap session=\(sessionName): path-check start")
        let pathCheck = try command(Self.pathValidationArguments(host: host), Data("\(selectedPath)\n".utf8))
        log("bootstrap session=\(sessionName): path-check exit=\(pathCheck.exitCode) (\(elapsed()))")
        guard pathCheck.exitCode == 0 else {
            if pathCheck.exitCode == 20 { throw RemoteBootstrapError.invalidPath(selectedPath) }
            throw commandFailure(pathCheck)
        }

        log("bootstrap session=\(sessionName): attach spawn")
        let process = try attach(try RemoteHerdrBridgePlan.remoteAttachArguments(
            for: connection, session: sessionName, directory: selectedPath
        ))
        defer {
            if process.isRunning { process.stop() }
        }
        // Readiness is bounded by wall clock: the loop must surface an
        // actionable failure instead of leaving onboarding spinning forever.
        let attachStarted = now()
        var polls = 0
        var detached = false
        while polls < pollCount, now() - attachStarted < readinessTimeout {
            polls += 1
            guard process.isRunning else {
                log("bootstrap session=\(sessionName): attach exited before readiness at poll #\(polls) (\(elapsed()))")
                throw RemoteBootstrapError.attachExited
            }
            let result = try command(Self.statusArguments(host: host, session: sessionName), nil)
            if result.exitCode == 0 {
                let status = try Self.decodeStatus(result.stdout)
                log("bootstrap session=\(sessionName): status poll #\(polls) running=\(status.running) detached=\(status.detachedServerDaemon) (\(elapsed()))")
                if status.running {
                    guard status.session == nil || status.session == sessionName else { throw RemoteBootstrapError.statusNotReady }
                    let identity = HerdrServerIdentity(version: status.version ?? "unknown", protocolVersion: status.protocolVersion ?? -1)
                    if let reason = HerdrCompatibility.incompatibility(for: identity) { throw RemoteBootstrapError.incompatible(reason) }
                    if status.detachedServerDaemon { detached = true; break }
                }
            } else {
                log("bootstrap session=\(sessionName): status poll #\(polls) exit=\(result.exitCode) (\(elapsed()))")
                throw commandFailure(result)
            }
            sleep()
        }
        guard detached else {
            log("bootstrap session=\(sessionName): readiness deadline expired after \(polls) polls (\(elapsed()))")
            throw RemoteBootstrapError.statusNotReady
        }
        log("bootstrap session=\(sessionName): detached proof after \(polls) polls; stopping attach (\(elapsed()))")
        process.stop() // Stop only the bootstrap SSH client, after detached proof.

        let continued = try command(Self.statusArguments(host: host, session: sessionName), nil)
        log("bootstrap session=\(sessionName): continued-status exit=\(continued.exitCode) (\(elapsed()))")
        guard continued.exitCode == 0 else { throw commandFailure(continued) }
        let continuedStatus = try Self.decodeStatus(continued.stdout)
        guard continuedStatus.running, continuedStatus.session == sessionName, continuedStatus.detachedServerDaemon,
              continuedStatus.version == BessieCompatibility.herdrVersion,
              continuedStatus.protocolVersion == BessieCompatibility.protocolVersion else {
            throw RemoteBootstrapError.statusNotReady
        }
        log("bootstrap session=\(sessionName): snapshot and topology acceptance start (\(elapsed()))")
        let accepted = try accept(snapshot(connection), connection: connection, path: selectedPath, expectedIDs: expectedIDs)
        try register(connection)
        log("bootstrap session=\(sessionName): accepted workspace=\(accepted.workspaceID) pane=\(accepted.paneID) (\(elapsed()))")
        return accepted
    }

    public static func statusArguments(host: String, session: String) -> [String] {
        SSHHostKeyPolicy.requiredArguments + ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host,
                                               "herdr --session \(session) status --json"]
    }

    public static func sessionListArguments(host: String) -> [String] {
        SSHHostKeyPolicy.requiredArguments + ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host,
                                               "herdr session list --json"]
    }

    /// Path bytes travel on stdin, not in the remote command. The fixed script reads one line and
    /// checks directory, search, read, and write usability without evaluating the value as shell.
    public static func pathValidationArguments(host: String) -> [String] {
        SSHHostKeyPolicy.requiredArguments + ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host,
            "IFS= read -r p || exit 20; if IFS= read -r _; then exit 20; fi; [ -d \"$p\" ] && [ -r \"$p\" ] && [ -w \"$p\" ] && [ -x \"$p\" ] || exit 20",
        ]
    }

    private func accept(_ snapshot: HerdrSnapshot, connection: BessieConnectionDefinition, path: String,
                        expectedIDs: (String, String, String)?) throws -> RemoteBootstrapResult {
        guard snapshot.version == BessieCompatibility.herdrVersion,
              snapshot.protocolVersion == BessieCompatibility.protocolVersion,
              let projection = try? HerdrSessionProjection(snapshot: snapshot),
              projection.workspaces.count == 1, projection.tabs.count == 1, projection.panes.count == 1 else {
            throw RemoteBootstrapError.ambiguousTopology
        }
        let workspace = projection.workspaces[0], tab = projection.tabs[0], pane = projection.panes[0]
        guard tab.workspaceID == workspace.id, pane.workspaceID == workspace.id, pane.tabID == tab.id,
              pane.effectiveCWD == path,
              expectedIDs.map({ $0.0 == workspace.id && $0.1 == tab.id && $0.2 == pane.id }) ?? true else {
            throw RemoteBootstrapError.ambiguousTopology
        }
        return RemoteBootstrapResult(connection: connection, workspaceID: workspace.id, tabID: tab.id, paneID: pane.id)
    }

    private func commandFailure(_ result: RemoteBootstrapCommandResult) -> RemoteBootstrapError {
        let detail = String(data: result.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .commandFailed(detail?.isEmpty == false ? detail! : "SSH/Herdr exited \(result.exitCode). Check authentication, host keys, and Herdr availability.")
    }

    private static func decodeStatus(_ data: Data) throws -> RemoteBootstrapStatus {
        do { return try JSONDecoder().decode(RemoteBootstrapStatusEnvelope.self, from: data).server }
        catch { throw RemoteBootstrapError.commandFailed("Herdr returned invalid status JSON: \(error.localizedDescription)") }
    }
}

public extension RemoteOnboardingBootstrap {
    static func production(register: @escaping Register, log: @escaping Log = { _ in }) -> RemoteOnboardingBootstrap {
        RemoteOnboardingBootstrap(command: { arguments, input in
            do {
                let result = try FoundationProcessCommandRunner.run(
                    executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
                    arguments: arguments,
                    standardInput: input,
                    timeout: 30
                )
                return RemoteBootstrapCommandResult(
                    exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr
                )
            } catch FoundationProcessCommandError.timedOut {
                throw RemoteBootstrapError.commandFailed("SSH command timed out.")
            }
        }, attach: { arguments in
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh"); process.arguments = arguments
            // A GUI app has no usable stdin for the forced-PTY attach client;
            // inheriting one can stall ssh before it runs the remote command.
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; try process.run()
            return FoundationRemoteBootstrapProcess(process)
        }, snapshot: { connection in
            let bridge = try RemoteHerdrBridge(connection: connection)
            let socket = try bridge.start()
            let api = HerdrSocketAPI(socketPath: socket)
            _ = try api.ping()
            return try api.snapshot()
        }, register: register, log: log)
    }
}

private final class FoundationRemoteBootstrapProcess: RemoteBootstrapProcess, @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    var isRunning: Bool { process.isRunning }
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 where process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
    }
}

private struct RemoteSessionList: Decodable {
    struct Session: Decodable { let name: String; let running: Bool }
    let sessions: [Session]
}
private struct RemoteBootstrapStatusEnvelope: Decodable { let server: RemoteBootstrapStatus }
private struct RemoteBootstrapStatus: Decodable {
    let running: Bool
    let version: String?
    let protocolVersion: Int?
    let session: String?
    let capabilities: Capabilities?
    var detachedServerDaemon: Bool { capabilities?.detachedServerDaemon == true }
    struct Capabilities: Decodable {
        let detachedServerDaemon: Bool
        enum CodingKeys: String, CodingKey { case detachedServerDaemon = "detached_server_daemon" }
    }
    enum CodingKeys: String, CodingKey {
        case running, version, session
        case protocolVersion = "protocol"
        case capabilities
    }
}
