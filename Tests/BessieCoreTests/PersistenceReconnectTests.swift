import Foundation
import XCTest
@testable import BessieCore

final class PersistenceReconnectTests: XCTestCase {
    func testReconnectPolicyIsBounded() {
        let policy = ReconnectPolicy(delays: [0.25, 0.5, 1.0])

        XCTAssertEqual(policy.delay(afterFailure: 0), 0.25)
        XCTAssertEqual(policy.delay(afterFailure: 2), 1.0)
        XCTAssertNil(policy.delay(afterFailure: 3))
    }

    func testPresentationPersistenceContainsOnlyPreferencesAndWorkspaceHint() throws {
        let state = BessiePresentationState(
            lastWorkspaceID: "workspace-hint",
            preferences: BessiePreferences(terminalFontSize: 14, paneGap: 7)
        )
        let encoded = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["last_workspace_id", "preferences"])
        XCTAssertNil(object["snapshot"])
        XCTAssertNil(object["workspaces"])
        XCTAssertEqual(try JSONDecoder().decode(BessiePresentationState.self, from: encoded), state)
    }

    func testConnectionStatesRepresentEveryApprovedRecoverySurface() {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/herdr"), source: .path)
        let identity = HerdrServerIdentity(version: "0.7.4", protocolVersion: 16)

        let states: [HerdrConnectionState] = [
            .notFound,
            .resolutionFailed(.systemMissing),
            .validationFailed(runtime: runtime, failure: .bundledIntegrity),
            .stopped(runtime: runtime, socketPath: "/tmp/herdr.sock"),
            .starting(runtime: runtime),
            .startFailed(runtime: runtime, reason: "spawn failed"),
            .incompatible(runtime: runtime, identity: identity, reason: "protocol 16 is unsupported"),
            .connecting(runtime: runtime),
            .apiUnavailable(runtime: runtime, reason: "socket unavailable"),
            .connected(runtime: runtime, socketPath: "/tmp/herdr.sock", snapshot: .fixture),
            .retrying(runtime: runtime, attempt: 2, delay: 0.5, reason: "socket closed"),
            .lost(runtime: runtime, reason: "retry budget exhausted"),
        ]

        XCTAssertEqual(states.map(\.label), ["Herdr not found", "Runtime selection failed", "Runtime validation failed", "Herdr stopped", "Starting Herdr", "Herdr start failed", "Herdr incompatible", "Connecting", "Herdr API unavailable", "Connected", "Retrying", "Connection lost"])
    }

    func testCanceledConnectionRunnerStopsBeforeDiscovery() async {
        let runner = HerdrConnectionRunner(repositoryRoot: URL(fileURLWithPath: "/unused"))
        let states = ConnectionStateRecorder()
        runner.cancel()

        await runner.run { states.append($0) }

        XCTAssertTrue(states.values.isEmpty)
    }

    func testStoppedRuntimeStartsNamedBessieSessionAndRechecksStatus() async {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/approved/herdr"), source: .explicitOverride)
        let statuses = ServerStatusSequence([
            HerdrServerStatus(status: "stopped", running: false, version: nil, protocolVersion: nil, socketPath: "/sessions/bessie/herdr.sock"),
            HerdrServerStatus(status: "running", running: true, version: "0.7.5", protocolVersion: 17, socketPath: "/sessions/bessie/herdr.sock"),
        ])
        let launch = ServerLaunchRecorder()
        let states = ConnectionStateRecorder()
        let runner = HerdrConnectionRunner(
            repositoryRoot: URL(fileURLWithPath: "/repo"),
            environment: [
                "BESSIE_HERDR_PATH": runtime.url.path,
                "HOME": "/Users/tester",
                "PATH": "",
            ],
            locator: HerdrRuntimeLocator(isExecutable: { $0 == runtime.url }),
            probe: HerdrRuntimeProbe(statusProvider: { _, environment in
                statuses.record(environment: environment)
                return try statuses.next()
            }),
            launcher: HerdrServerLauncher(startOperation: { launchedRuntime, environment in
                launch.record(runtime: launchedRuntime, environment: environment)
            }),
            policy: ReconnectPolicy(delays: [0])
        )

        await runner.run { state in
            states.append(state)
            if case .connecting = state { runner.cancel() }
        }

        XCTAssertEqual(states.values.map(\.label), ["Starting Herdr", "Connecting"])
        XCTAssertEqual(launch.runtime, runtime)
        XCTAssertEqual(launch.environment?["HERDR_SESSION"], "bessie")
        XCTAssertEqual(launch.environment?["HERDR_STARTUP_CWD"], "/Users/tester")
        XCTAssertEqual(statuses.environments.count, 2)
        XCTAssertTrue(statuses.environments.allSatisfy { $0["HERDR_SESSION"] == "bessie" })
    }

    func testInheritedHerdrSocketCannotBypassBessieSessionIsolation() async {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/approved/herdr"), source: .explicitOverride)
        let statuses = ServerStatusSequence([
            HerdrServerStatus(status: "running", running: true, version: "0.7.5", protocolVersion: 17, socketPath: "/sessions/review/herdr.sock"),
        ])
        let states = ConnectionStateRecorder()
        let runner = HerdrConnectionRunner(
            repositoryRoot: URL(fileURLWithPath: "/repo"),
            environment: [
                "BESSIE_HERDR_PATH": runtime.url.path,
                "BESSIE_HERDR_SESSION": " review ",
                "HERDR_SOCKET_PATH": "/sessions/default/herdr.sock",
                "PATH": "",
            ],
            locator: HerdrRuntimeLocator(isExecutable: { $0 == runtime.url }),
            probe: HerdrRuntimeProbe(statusProvider: { _, environment in
                statuses.record(environment: environment)
                return try statuses.next()
            })
        )

        await runner.run { state in
            states.append(state)
            if case .connecting = state { runner.cancel() }
        }

        XCTAssertEqual(states.values.map(\.label), ["Connecting"])
        XCTAssertEqual(statuses.environments.count, 1)
        XCTAssertEqual(statuses.environments[0]["HERDR_SESSION"], "review")
        XCTAssertNil(statuses.environments[0]["HERDR_SOCKET_PATH"])
    }

    func testBessieSpecificSocketOverrideReplacesGenericHerdrSocketForDiagnostics() async {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/approved/herdr"), source: .explicitOverride)
        let statuses = ServerStatusSequence([
            HerdrServerStatus(status: "running", running: true, version: "0.7.5", protocolVersion: 17, socketPath: "/diagnostics/herdr.sock"),
        ])
        let states = ConnectionStateRecorder()
        let runner = HerdrConnectionRunner(
            repositoryRoot: URL(fileURLWithPath: "/repo"),
            environment: [
                "BESSIE_HERDR_PATH": runtime.url.path,
                "BESSIE_HERDR_SOCKET_PATH": " /diagnostics/herdr.sock ",
                "HERDR_SOCKET_PATH": "/sessions/default/herdr.sock",
                "PATH": "",
            ],
            locator: HerdrRuntimeLocator(isExecutable: { $0 == runtime.url }),
            probe: HerdrRuntimeProbe(statusProvider: { _, environment in
                statuses.record(environment: environment)
                return try statuses.next()
            })
        )

        await runner.run { state in
            states.append(state)
            if case .connecting = state { runner.cancel() }
        }

        XCTAssertEqual(states.values.map(\.label), ["Connecting"])
        XCTAssertEqual(statuses.environments.count, 1)
        XCTAssertEqual(statuses.environments[0]["HERDR_SESSION"], "bessie")
        XCTAssertEqual(statuses.environments[0]["HERDR_SOCKET_PATH"], "/diagnostics/herdr.sock")
    }

    func testAutoStartCanBeDisabledForDiagnostics() async {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/approved/herdr"), source: .explicitOverride)
        let launch = ServerLaunchRecorder()
        let states = ConnectionStateRecorder()
        let runner = HerdrConnectionRunner(
            repositoryRoot: URL(fileURLWithPath: "/repo"),
            environment: [
                "BESSIE_HERDR_AUTOSTART": "0",
                "BESSIE_HERDR_PATH": runtime.url.path,
                "PATH": "",
            ],
            locator: HerdrRuntimeLocator(isExecutable: { $0 == runtime.url }),
            probe: HerdrRuntimeProbe(statusProvider: { _, _ in
                HerdrServerStatus(status: "stopped", running: false, version: nil, protocolVersion: nil, socketPath: "/sessions/bessie/herdr.sock")
            }),
            launcher: HerdrServerLauncher(startOperation: { launchedRuntime, environment in
                launch.record(runtime: launchedRuntime, environment: environment)
            })
        )

        await runner.run { states.append($0) }

        XCTAssertEqual(states.values.map(\.label), ["Herdr stopped"])
        XCTAssertNil(launch.runtime)
    }
}

private final class ConnectionStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HerdrConnectionState] = []
    var values: [HerdrConnectionState] { lock.withLock { storage } }
    func append(_ state: HerdrConnectionState) { lock.withLock { storage.append(state) } }
}

private final class ServerStatusSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [HerdrServerStatus]
    private var recordedEnvironments: [[String: String]] = []

    init(_ statuses: [HerdrServerStatus]) {
        self.statuses = statuses
    }

    var environments: [[String: String]] { lock.withLock { recordedEnvironments } }

    func record(environment: [String: String]) {
        lock.withLock { recordedEnvironments.append(environment) }
    }

    func next() throws -> HerdrServerStatus {
        try lock.withLock {
            guard !statuses.isEmpty else {
                throw HerdrClientError.unexpectedResponse("status sequence exhausted")
            }
            return statuses.removeFirst()
        }
    }
}

private final class ServerLaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRuntime: HerdrRuntime?
    private var recordedEnvironment: [String: String]?

    var runtime: HerdrRuntime? { lock.withLock { recordedRuntime } }
    var environment: [String: String]? { lock.withLock { recordedEnvironment } }

    func record(runtime: HerdrRuntime, environment: [String: String]) {
        lock.withLock {
            recordedRuntime = runtime
            recordedEnvironment = environment
        }
    }
}

private extension HerdrSnapshot {
    static let fixture = HerdrSnapshot(
        version: "0.7.5",
        protocolVersion: 17,
        focusedWorkspaceID: nil,
        focusedTabID: nil,
        focusedPaneID: nil,
        workspaces: [], tabs: [], panes: [], layouts: [], agents: []
    )
}
