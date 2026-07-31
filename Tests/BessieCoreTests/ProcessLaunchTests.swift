import XCTest
@testable import BessieCore

final class ProcessLaunchTests: XCTestCase {
    func testManifestCatalogUsesServerKindsAndExplainsMissingExecutables() throws {
        let value: JSONValue = .object([
            "type": .string("agent_manifest_status"),
            "manifests": .array([
                .object(["agent": .string("codex"), "source": .string("bundled"), "source_kind": .string("bundled"), "active_version": .string("2026.07.18.1"), "local_override_shadowing_remote": .bool(false)]),
                .object(["agent": .string("claude"), "source": .string("bundled"), "source_kind": .string("bundled"), "local_override_shadowing_remote": .bool(false)]),
            ]),
        ])
        let checker = FixtureAvailability(paths: ["codex": "/opt/bin/codex"])

        let catalog = try AgentCatalog(serverResult: value, availability: checker)

        XCTAssertEqual(catalog.items.map(\.kind), ["claude", "codex"])
        XCTAssertEqual(catalog.items[0].availability, .unavailable(reason: "claude is not installed or is not on PATH"))
        XCTAssertEqual(catalog.items[1].availability, .available(executablePath: "/opt/bin/codex"))
        XCTAssertEqual(catalog.items[1].version, "2026.07.18.1")
    }

    func testAgentStartUsesExactProtocol17PayloadWithOptionalArgs() {
        let action = HerdrAction.agentStart(
            paneID: "w1:p2", kind: "codex", name: "codex-2",
            args: ["--model", "gpt-5"], timeoutMilliseconds: 45_000
        )

        XCTAssertEqual(action.request.method, "agent.start")
        XCTAssertEqual(action.request.params, [
            "pane_id": .string("w1:p2"), "kind": .string("codex"), "name": .string("codex-2"),
            "args": .array([.string("--model"), .string("gpt-5")]), "timeout_ms": .number(45_000),
        ])
        XCTAssertEqual(
            HerdrAction.agentStart(paneID: "p", kind: "claude", name: "claude", args: [], timeoutMilliseconds: nil).request.params,
            ["pane_id": .string("p"), "kind": .string("claude"), "name": .string("claude")]
        )
    }

    func testSemanticNameAllocatorProducesUniqueStableLabels() {
        XCTAssertEqual(AgentSemanticName.unique(kind: "codex", existing: []), "codex")
        XCTAssertEqual(AgentSemanticName.unique(kind: "codex", existing: ["codex", "codex-2", "worker"]), "codex-3")
    }

    func testAgentFailureKeepsCreatedShellPaneAndNeverClosesIt() throws {
        let api = LaunchRecordingAPI(snapshots: [.launchBefore, .launchAfterShell])
        api.failMethod = "agent.start"
        let launcher = HerdrProcessLauncher(api: api)

        let result = try launcher.launch(
            placement: .split(targetPaneID: "p1", direction: .right, cwd: "/tmp"),
            process: .agent(kind: "codex", name: "codex", args: [], timeoutMilliseconds: 30_000)
        )

        XCTAssertEqual(result.paneID, "p2")
        XCTAssertFalse(result.agentStarted)
        XCTAssertEqual(result.agentError, "agent executable missing")
        XCTAssertEqual(api.calls, ["session.snapshot", "pane.split", "session.snapshot", "agent.start"])
        XCTAssertFalse(api.calls.contains("pane.close"))
        XCTAssertEqual(result.projection.panes.map(\.id).sorted(), ["p1", "p2"])
    }
}

private struct FixtureAvailability: AgentAvailabilityChecking {
    let paths: [String: String]
    func executablePath(for kind: String) -> String? { paths[kind] }
}

private final class LaunchRecordingAPI: HerdrMutationAPI, @unchecked Sendable {
    var calls: [String] = []
    var failMethod: String?
    private var snapshots: [HerdrSnapshot]
    init(snapshots: [HerdrSnapshot]) { self.snapshots = snapshots }
    func request(method: String, params: [String: JSONValue]) throws -> JSONValue {
        calls.append(method)
        if method == failMethod { throw HerdrClientError.server(code: "agent_start_failed", message: "agent executable missing") }
        return .object([:])
    }
    func snapshot() throws -> HerdrSnapshot {
        calls.append("session.snapshot")
        return snapshots.removeFirst()
    }
}

private extension HerdrSnapshot {
    static let launchBefore = launchFixture(panes: ["p1"])
    static let launchAfterShell = launchFixture(panes: ["p1", "p2"])
    static func launchFixture(panes paneIDs: [String]) -> HerdrSnapshot {
        HerdrSnapshot(
            version: "0.7.5", protocolVersion: 17,
            focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: paneIDs.last,
            workspaces: [.object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("main"), "focused": .bool(true), "pane_count": .number(Double(paneIDs.count)), "tab_count": .number(1), "active_tab_id": .string("t1"), "agent_status": .string("idle")])],
            tabs: [.object(["tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1), "label": .string("shell"), "focused": .bool(true), "pane_count": .number(Double(paneIDs.count)), "agent_status": .string("idle")])],
            panes: paneIDs.enumerated().map { index, id in .object(["pane_id": .string(id), "terminal_id": .string("term\(index)"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(index == paneIDs.count - 1), "agent_status": .string("idle"), "revision": .number(1)]) },
            layouts: [], agents: []
        )
    }
}
