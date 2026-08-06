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

    func testRailCollapsePreferenceRoundTripsAndLegacyPreferencesStayExpanded() throws {
        let preferences = BessiePreferences(railCollapsed: true)
        XCTAssertTrue(try JSONDecoder().decode(BessiePreferences.self, from: JSONEncoder().encode(preferences)).railCollapsed)

        let legacy = Data(#"{"appearance":"dark","terminalFontSize":14}"#.utf8)
        let decoded = try JSONDecoder().decode(BessiePreferences.self, from: legacy)
        XCTAssertFalse(decoded.railCollapsed)
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.terminalFontSize, 14)
    }

    func testThemeIDsRoundTripLegacyNamedAndUnknownValuesSafely() throws {
        for id in BessieThemeID.allCases {
            let preferences = BessiePreferences(appearance: id)
            XCTAssertEqual(
                try JSONDecoder().decode(BessiePreferences.self, from: JSONEncoder().encode(preferences)).appearance,
                id
            )
        }
        for rawValue in ["system", "dark", "light"] {
            let decoded = try JSONDecoder().decode(
                BessiePreferences.self,
                from: Data("{\"appearance\":\"\(rawValue)\"}".utf8)
            )
            XCTAssertEqual(decoded.appearance.rawValue, rawValue)
        }
        let unknown = try JSONDecoder().decode(
            BessiePreferences.self,
            from: Data(#"{"appearance":"future-theme","terminalFontSize":17}"#.utf8)
        )
        XCTAssertEqual(unknown.appearance, .dark)
        XCTAssertEqual(unknown.terminalFontSize, 17)
    }

    func testPresentationStoreMigratesLegacyPreferencesAndRejectsNewerSchemaWithoutRewriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("presentation.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"last_workspace_id":"legacy","preferences":{"appearance":"light","notifications":"blockedAndDone","terminalFontSize":15,"paneGap":6}}"#.utf8).write(to: url)
        let store = BessiePresentationStore(url: url)

        let legacy = try store.load()
        XCTAssertEqual(legacy.lastWorkspaceID, "legacy")
        XCTAssertEqual(legacy.preferences.notifications, .blockedAndDone)
        XCTAssertTrue(legacy.preferences.menuBarVisible)
        XCTAssertEqual(legacy.preferences.menuBarBadgePolicy, .needsYou)
        XCTAssertEqual(legacy.preferences.menuBarRowClickBehavior, .focusPane)

        try store.save(legacy)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(envelope["schemaVersion"] as? Int, BessiePresentationStore.currentSchemaVersion)
        XCTAssertNotNil(envelope["state"])

        let newer = Data(#"{"schemaVersion":999,"state":{"preferences":{}}}"#.utf8)
        try newer.write(to: url)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? BessiePresentationPersistenceError, .unsupportedSchema(999))
        }
        XCTAssertEqual(try Data(contentsOf: url), newer)
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
            HerdrServerStatus(status: "running", running: true, version: "0.8.0", protocolVersion: 19, socketPath: "/sessions/bessie/herdr.sock"),
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
            HerdrServerStatus(status: "running", running: true, version: "0.8.0", protocolVersion: 19, socketPath: "/sessions/review/herdr.sock"),
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
            HerdrServerStatus(status: "running", running: true, version: "0.8.0", protocolVersion: 19, socketPath: "/diagnostics/herdr.sock"),
        ])
        let states = ConnectionStateRecorder()
        let inspectCounter = InspectCounter()
        let validator = HerdrRuntimeValidator(
            inspect: { _ in
                inspectCounter.increment()
                return RuntimeFileFacts(
                    exists: true,
                    regularFile: true,
                    executable: true,
                    arm64: true,
                    sha256: "deadbeef",
                    signatureValid: true
                )
            },
            identity: { _ in HerdrServerIdentity(version: "0.8.0", protocolVersion: 19) }
        )
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
            }),
            validator: validator
        )

        await runner.run { state in
            states.append(state)
            if case .connecting = state { runner.cancel() }
        }

        XCTAssertEqual(states.values.map(\.label), ["Connecting"])
        // Socket override is the source of truth: no status CLI and no local integrity inspect.
        XCTAssertEqual(statuses.environments.count, 0)
        XCTAssertEqual(inspectCounter.count, 0)
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

private final class InspectCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
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
        version: "0.8.0",
        protocolVersion: 19,
        focusedWorkspaceID: nil,
        focusedTabID: nil,
        focusedPaneID: nil,
        workspaces: [], tabs: [], panes: [], layouts: [], agents: []
    )
}
