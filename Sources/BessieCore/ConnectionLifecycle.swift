import Foundation

public struct HerdrBootstrapResult: Sendable {
    public let snapshot: HerdrSnapshot
    public let subscription: any HerdrEventSubscription
}

public struct HerdrBootstrapper: Sendable {
    public init() {}

    public func bootstrap(api: any HerdrAPI) throws -> HerdrBootstrapResult {
        let subscription = try api.subscribe()
        var snapshot = try api.snapshot()
        if !subscription.drainBufferedEvents().isEmpty { snapshot = try api.snapshot() }
        return HerdrBootstrapResult(snapshot: snapshot, subscription: subscription)
    }
}

public struct ReconnectPolicy: Equatable, Sendable {
    public let delays: [TimeInterval]
    public init(delays: [TimeInterval] = [0.25, 0.5, 1, 2, 4]) { self.delays = delays }
    public func delay(afterFailure failure: Int) -> TimeInterval? {
        delays.indices.contains(failure) ? delays[failure] : nil
    }
}

public enum HerdrConnectionState: Equatable, Sendable {
    case notFound
    case stopped(runtime: HerdrRuntime, socketPath: String)
    case starting(runtime: HerdrRuntime)
    case startFailed(runtime: HerdrRuntime, reason: String)
    case incompatible(runtime: HerdrRuntime, identity: HerdrServerIdentity, reason: String)
    case connecting(runtime: HerdrRuntime)
    case connected(runtime: HerdrRuntime, socketPath: String, snapshot: HerdrSnapshot)
    case retrying(runtime: HerdrRuntime, attempt: Int, delay: TimeInterval, reason: String)
    case lost(runtime: HerdrRuntime, reason: String)

    public var label: String {
        switch self {
        case .notFound: "Herdr not found"
        case .stopped: "Herdr stopped"
        case .starting: "Starting Herdr"
        case .startFailed: "Herdr start failed"
        case .incompatible: "Herdr incompatible"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .retrying: "Retrying"
        case .lost: "Connection lost"
        }
    }
}

public final class HerdrConnectionRunner: @unchecked Sendable {
    private let repositoryRoot: URL
    private let environment: [String: String]
    private let locator: HerdrRuntimeLocator
    private let probe: HerdrRuntimeProbe
    private let launcher: HerdrServerLauncher
    private let policy: ReconnectPolicy
    private let cancellation = ConnectionCancellation()

    public init(
        repositoryRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        locator: HerdrRuntimeLocator = HerdrRuntimeLocator(),
        probe: HerdrRuntimeProbe = HerdrRuntimeProbe(),
        launcher: HerdrServerLauncher = HerdrServerLauncher(),
        policy: ReconnectPolicy = ReconnectPolicy()
    ) {
        self.repositoryRoot = repositoryRoot
        var managedEnvironment = environment
        let requestedSession = managedEnvironment["BESSIE_HERDR_SESSION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedSocketPath = managedEnvironment["BESSIE_HERDR_SOCKET_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // A generic Herdr socket override may belong to an unrelated shell or session.
        // Bessie manages a named session unless its own diagnostic socket override is explicit.
        managedEnvironment.removeValue(forKey: "HERDR_SOCKET_PATH")
        managedEnvironment["HERDR_SESSION"] = requestedSession?.isEmpty == false
            ? requestedSession
            : BessieCompatibility.sessionName
        if requestedSocketPath?.isEmpty == false {
            managedEnvironment["HERDR_SOCKET_PATH"] = requestedSocketPath
        }
        self.environment = managedEnvironment
        self.locator = locator
        self.probe = probe
        self.launcher = launcher
        self.policy = policy
    }

    public func run(onState: @escaping @Sendable (HerdrConnectionState) -> Void) async {
        await Task.detached { [self] in runBlocking(onState: onState) }.value
    }

    public func cancel() { cancellation.cancel() }

    private func runBlocking(onState: @escaping @Sendable (HerdrConnectionState) -> Void) {
        guard !cancellation.isCancelled else { return }
        guard let runtime = locator.locate(
            explicitPath: environment["BESSIE_HERDR_PATH"],
            path: environment["PATH"],
            repositoryRoot: repositoryRoot
        ) else { onState(.notFound); return }

        var status: HerdrServerStatus
        do { status = try probe.status(runtime: runtime, environment: environment) }
        catch { onState(.lost(runtime: runtime, reason: error.localizedDescription)); return }
        if !status.running {
            guard autoStartEnabled else {
                onState(.stopped(runtime: runtime, socketPath: status.socketPath))
                return
            }
            onState(.starting(runtime: runtime))
            do {
                try launcher.start(
                    runtime: runtime,
                    environment: environment,
                    startupDirectory: startupDirectory
                )
            } catch {
                onState(.startFailed(runtime: runtime, reason: error.localizedDescription))
                return
            }

            var startupFailure = "Herdr did not become ready."
            for delay in policy.delays {
                guard cancellation.wait(for: delay) else { return }
                do {
                    status = try probe.status(runtime: runtime, environment: environment)
                    if status.running { break }
                } catch {
                    startupFailure = error.localizedDescription
                }
            }
            guard status.running else {
                onState(.startFailed(runtime: runtime, reason: startupFailure))
                return
            }
        }

        let statusIdentity = HerdrServerIdentity(version: status.version ?? "unknown", protocolVersion: status.protocolVersion ?? -1)
        if let reason = HerdrCompatibility.incompatibility(for: statusIdentity) {
            onState(.incompatible(runtime: runtime, identity: statusIdentity, reason: reason))
            return
        }

        var failure = 0
        while !cancellation.isCancelled {
            onState(.connecting(runtime: runtime))
            do {
                let api = HerdrSocketAPI(socketPath: status.socketPath)
                let identity = try api.ping()
                if let reason = HerdrCompatibility.incompatibility(for: identity) {
                    onState(.incompatible(runtime: runtime, identity: identity, reason: reason))
                    return
                }
                let bootstrapped = try HerdrBootstrapper().bootstrap(api: api)
                guard cancellation.attach(bootstrapped.subscription) else {
                    bootstrapped.subscription.close()
                    return
                }
                defer {
                    bootstrapped.subscription.close()
                    cancellation.detach(bootstrapped.subscription)
                }
                var latestSnapshot = bootstrapped.snapshot
                onState(.connected(runtime: runtime, socketPath: status.socketPath, snapshot: bootstrapped.snapshot))
                while !cancellation.isCancelled, try bootstrapped.subscription.nextEvent() != nil {
                    guard cancellation.wait(for: 0.03) else { return }
                    _ = bootstrapped.subscription.drainBufferedEvents()
                    let snapshot = try api.snapshot()
                    if snapshot != latestSnapshot {
                        latestSnapshot = snapshot
                        onState(.connected(runtime: runtime, socketPath: status.socketPath, snapshot: snapshot))
                    }
                }
                guard !cancellation.isCancelled else { return }
                throw HerdrClientError.connectionClosed
            } catch {
                guard !cancellation.isCancelled else { return }
                guard let delay = policy.delay(afterFailure: failure) else {
                    onState(.lost(runtime: runtime, reason: error.localizedDescription))
                    return
                }
                failure += 1
                onState(.retrying(runtime: runtime, attempt: failure, delay: delay, reason: error.localizedDescription))
                guard cancellation.wait(for: delay) else { return }
            }
        }
    }

    private var autoStartEnabled: Bool {
        guard let configured = environment["BESSIE_HERDR_AUTOSTART"]?.lowercased() else { return true }
        return !["0", "false", "no"].contains(configured)
    }

    private var startupDirectory: URL {
        if let configured = environment["BESSIE_HERDR_STARTUP_CWD"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

private final class ConnectionCancellation: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    private var subscription: (any HerdrEventSubscription)?

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    func attach(_ subscription: any HerdrEventSubscription) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !cancelled else { return false }
        self.subscription = subscription
        return true
    }

    func detach(_ subscription: any HerdrEventSubscription) {
        condition.lock()
        if self.subscription === subscription { self.subscription = nil }
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        cancelled = true
        let subscription = self.subscription
        self.subscription = nil
        condition.broadcast()
        condition.unlock()
        subscription?.close()
    }

    func wait(for interval: TimeInterval) -> Bool {
        condition.lock()
        if !cancelled { condition.wait(until: Date(timeIntervalSinceNow: interval)) }
        let shouldContinue = !cancelled
        condition.unlock()
        return shouldContinue
    }
}
