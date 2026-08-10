import Foundation
import XCTest
@testable import BessieCore

final class AgentIntentExecutorTests: XCTestCase {
    func testRequestAndResultRoundTripWithVersionedWireFields() throws {
        let request = BessieIntentRequest(
            id: "request-1",
            intent: "pane.focus",
            params: ["connection_id": .string("local"), "pane_id": .string("p1")],
            confirmToken: "confirm-1"
        )

        let decoded = try JSONDecoder().decode(BessieIntentRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded, request)

        let object = try jsonObject(BessieIntentResult.success(id: request.id, value: .object(["focused": .bool(true)])))
        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertEqual(object["id"] as? String, "request-1")
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertNil(object["error"])
    }

    func testStrictValidationRejectsUnknownMissingAndWrongTypeParams() {
        let executor = makeExecutor()

        assertError(executor.execute(.init(id: "1", intent: "missing", params: [:])), code: .unknownIntent)
        assertError(executor.execute(.init(id: "2", intent: "pane.focus", params: [
            "connection_id": .string("local"), "pane_id": .string("p1"), "extra": .bool(true),
        ])), code: .invalidParams)
        assertError(executor.execute(.init(id: "3", intent: "pane.focus", params: ["pane_id": .string("p1")])), code: .invalidParams)
        assertError(executor.execute(.init(id: "4", intent: "pane.focus", params: [
            "connection_id": .string("local"), "pane_id": .number(1),
        ])), code: .invalidParams)
        assertError(executor.execute(.init(v: 2, id: "5", intent: "app.status", params: [:])), code: .unsupported)
        assertError(executor.execute(.init(id: String(repeating: "x", count: 257), intent: "app.status", params: [:])), code: .invalidParams)
    }

    func testLiveIntentsRequireConnectedMatchingConnection() {
        let executor = makeExecutor(live: FakeLivePort(connectedIDs: []))
        let result = executor.execute(.init(id: "1", intent: "session.projection", params: ["connection_id": .string("local")]))
        assertError(result, code: .notConnected)
    }

    func testFocusMapsToHerdrActionAndReturnsReconciledProjection() throws {
        let live = FakeLivePort(connectedIDs: ["local"])
        let executor = makeExecutor(live: live)

        let result = executor.execute(.init(id: "1", intent: "pane.focus", params: [
            "connection_id": .string("local"), "pane_id": .string("p1"),
        ]))

        XCTAssertTrue(result.ok)
        XCTAssertEqual(live.actions, [.paneFocus(id: "p1")])
        XCTAssertEqual(try result.value?.decode(BessieIntentSessionProjection.self).panes.first(where: \.focused)?.id, "p2")
    }

    func testProjectionStatusCatalogAndProjectReadsReturnStructuredValues() throws {
        let project = BessieProject(name: "Pilot", workingDirectory: "/tmp", tabs: [.init(name: "Main", panes: [.init(placement: .root)])])
        let projects = FakeProjectReadPort(projects: [project])
        let executor = makeExecutor(projects: projects)

        let projection = try executor.execute(.init(id: "1", intent: "session.projection", params: ["connection_id": .string("local")])).value?.decode(BessieIntentSessionProjection.self)
        XCTAssertEqual(projection?.connectionID, "local")
        XCTAssertEqual(projection?.workspaces.first?.id, "w1")
        XCTAssertEqual(projection?.focusedPaneID, "p2")
        XCTAssertEqual(projection?.layouts.count, 1)
        XCTAssertEqual(try executor.execute(.init(id: "2", intent: "project.list", params: [:])).value?.decode([BessieProject].self).map(\.id), [project.id])
        XCTAssertEqual(try executor.execute(.init(id: "3", intent: "project.show", params: ["project_id": .string(project.id.uuidString)])).value?.decode(BessieProject.self), project)
        XCTAssertEqual(try executor.execute(.init(id: "4", intent: "intents.list", params: [:])).value?.decode(BessieIntentCatalog.self), BessieIntentRegistry.catalog)
        XCTAssertEqual(executor.execute(.init(id: "5", intent: "app.status", params: [:])).value?["running"], .bool(true))
        XCTAssertEqual(executor.execute(.init(id: "6", intent: "connection.status", params: ["connection_id": .string("local")])).value?["connected"], .bool(true))
    }

    func testIntentListOmitsLiveConnectionIntentsWhenDisconnected() throws {
        let executor = makeExecutor(live: FakeLivePort(connectedIDs: []))

        let result = executor.execute(.init(id: "1", intent: "intents.list", params: [:]))
        let ids = try result.value?.decode(BessieIntentCatalog.self).intents.map(\.id.rawValue)

        XCTAssertEqual(Set(ids ?? []), [
            "intents.list", "app.status", "connection.status", "connection.context",
            "pane.presentation.list", "pane.pin", "pane.unpin", "pane.snooze", "pane.wake",
            "project.list", "project.show",
        ])
    }

    func testConnectionContextReportsConfiguredRolesAndLiveStateWithoutSecrets() throws {
        let contexts = [
            BessieIntentConnectionContext(
                id: "local-bessie",
                label: "This Mac",
                kind: .local,
                sshHost: nil,
                enabled: false,
                selected: false,
                defaultProjectTarget: false,
                connected: false
            ),
            BessieIntentConnectionContext(
                id: "hermes-vps",
                label: "Hermes VPS",
                kind: .ssh,
                sshHost: "hermes",
                enabled: true,
                selected: true,
                defaultProjectTarget: true,
                connected: true
            ),
        ]
        let live = FakeLivePort(connectedIDs: ["hermes-vps"], contexts: contexts)
        let executor = makeExecutor(live: live)

        let all = try executor.execute(.init(
            id: "all", intent: "connection.context", params: [:]
        )).value?.decode([BessieIntentConnectionContext].self)
        let disabled = try executor.execute(.init(
            id: "one",
            intent: "connection.context",
            params: ["connection_id": .string("local-bessie")]
        )).value?.decode([BessieIntentConnectionContext].self)

        XCTAssertEqual(all, contexts)
        XCTAssertEqual(disabled, [contexts[0]])
        let encoded = String(decoding: try JSONEncoder().encode(all), as: UTF8.self)
        XCTAssertTrue(encoded.contains("hermes"))
        XCTAssertFalse(encoded.contains("socket"))
        XCTAssertFalse(encoded.contains("password"))
        XCTAssertFalse(encoded.contains("private_key"))
    }

    func testWorkspaceCloseRequiresExactProjectionTextAndOneShotBoundToken() {
        let live = FakeLivePort(connectedIDs: ["local"])
        let tokens = LockedTokenSource(["token-1", "token-2"])
        let executor = makeExecutor(live: live, tokenSource: { tokens.next() })
        let params: [String: JSONValue] = ["connection_id": .string("local"), "workspace_id": .string("w1")]

        let challenge = executor.execute(.init(id: "1", intent: "workspace.close", params: params))
        assertError(challenge, code: .needsConfirmation)
        XCTAssertEqual(challenge.error?.message, "This will stop processes in 2 panes. Closing Bessie alone leaves them running.")
        XCTAssertEqual(challenge.error?.confirmToken, "token-1")

        let changed = executor.execute(.init(id: "2", intent: "workspace.close", params: [
            "connection_id": .string("local"), "workspace_id": .string("other"),
        ], confirmToken: "token-1"))
        assertError(changed, code: .confirmTokenInvalid)

        let success = executor.execute(.init(id: "3", intent: "workspace.close", params: params, confirmToken: "token-1"))
        XCTAssertTrue(success.ok)
        XCTAssertEqual(live.actions, [.workspaceClose(id: "w1")])

        assertError(executor.execute(.init(id: "4", intent: "workspace.close", params: params, confirmToken: "token-1")), code: .confirmTokenInvalid)
        XCTAssertEqual(live.actions, [.workspaceClose(id: "w1")])
    }

    private func makeExecutor(
        live: FakeLivePort = FakeLivePort(connectedIDs: ["local"]),
        projects: FakeProjectReadPort = FakeProjectReadPort(projects: []),
        tokenSource: @escaping @Sendable () -> String = { UUID().uuidString }
    ) -> BessieIntentExecutor {
        BessieIntentExecutor(live: live, projects: projects, tokenSource: tokenSource)
    }

    private func assertError(_ result: BessieIntentResult, code: BessieIntentErrorCode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(result.ok, file: file, line: line)
        XCTAssertEqual(result.error?.code, code, file: file, line: line)
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}

private final class FakeLivePort: BessieIntentLivePort, @unchecked Sendable {
    private let connectedIDs: Set<String>
    private let contexts: [BessieIntentConnectionContext]
    private let lock = NSLock()
    private(set) var actions: [HerdrAction] = []

    init(
        connectedIDs: Set<String>,
        contexts: [BessieIntentConnectionContext] = []
    ) {
        self.connectedIDs = connectedIDs
        self.contexts = contexts
    }
    func isConnected(connectionID: String?) -> Bool { connectionID.map(connectedIDs.contains) ?? !connectedIDs.isEmpty }
    func connectionContexts(connectionID: String?) -> [BessieIntentConnectionContext] {
        contexts.filter { connectionID == nil || $0.id == connectionID }
    }
    func projection(connectionID: String) throws -> HerdrSessionProjection { try .init(snapshot: .intentFixture) }
    func perform(_ action: HerdrAction, connectionID: String) throws -> HerdrSessionProjection {
        lock.withLock { actions.append(action) }
        return try projection(connectionID: connectionID)
    }
}

private struct FakeProjectReadPort: BessieIntentProjectReadPort {
    let projects: [BessieProject]
    func listProjects() throws -> [BessieProject] { projects }
    func project(id: UUID) throws -> BessieProject? { projects.first { $0.id == id } }
}

private final class LockedTokenSource: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]
    init(_ values: [String]) { self.values = values }
    func next() -> String { lock.withLock { values.removeFirst() } }
}

private extension HerdrSnapshot {
    static let intentFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p2",
        workspaces: [.object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("main"), "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(1), "active_tab_id": .string("t1"), "agent_status": .string("idle")])],
        tabs: [.object(["tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1), "label": .string("shell"), "focused": .bool(true), "pane_count": .number(2), "agent_status": .string("idle")])],
        panes: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("term1"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1)]),
            .object(["pane_id": .string("p2"), "terminal_id": .string("term2"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1)]),
        ], layouts: [.object([
            "workspace_id": .string("w1"), "tab_id": .string("t1"), "zoomed": .bool(false),
            "focused_pane_id": .string("p2"),
            "area": .object(["x": .number(0), "y": .number(0), "width": .number(100), "height": .number(40)]),
            "panes": .array([
                .object(["pane_id": .string("p1"), "focused": .bool(false), "rect": .object(["x": .number(0), "y": .number(0), "width": .number(49), "height": .number(40)])]),
                .object(["pane_id": .string("p2"), "focused": .bool(true), "rect": .object(["x": .number(51), "y": .number(0), "width": .number(49), "height": .number(40)])]),
            ]),
            "splits": .array([.object(["id": .string("split_0_root"), "direction": .string("right"), "ratio": .number(0.5), "rect": .object(["x": .number(0), "y": .number(0), "width": .number(100), "height": .number(40)])])]),
        ])], agents: []
    )
}
