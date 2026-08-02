import XCTest
@testable import BessieCore

final class AttentionListTests: XCTestCase {
    func testAttentionIncludesBlockedAndDoneWithCompositeIDsAndStableOrdering() {
        let remote = BessieConnectionDefinition(
            id: "remote", name: "VPS", kind: .ssh, sshHost: "hermes", session: "bessie"
        )
        let agents = [
            connected(id: "done", identity: "Zulu", state: "done"),
            connected(id: "shared", identity: "Alpha", state: "blocked"),
            connected(id: "shared", identity: "Remote", state: "blocked", connection: remote),
            connected(id: "working", identity: "Ignored", state: "working"),
        ]

        let items = AttentionListBuilder.items(from: agents)

        XCTAssertEqual(items.map(\.state), [.blocked, .blocked, .done])
        XCTAssertEqual(items.map(\.identity), ["Alpha", "Remote", "Zulu"])
        XCTAssertEqual(items.map(\.id), ["local-bessie::shared", "remote::shared", "local-bessie::done"])
        XCTAssertEqual(items[1].connectionLabel, "VPS")
        XCTAssertEqual(
            items[1].target,
            RoutedPaneTarget(
                connectionID: "remote",
                workspaceID: "workspace-shared",
                tabID: "tab-shared",
                paneID: "shared"
            )
        )
    }

    private func connected(
        id: String,
        identity: String,
        state: String,
        connection: BessieConnectionDefinition = .localBessie
    ) -> ConnectedAgentProjection {
        ConnectedAgentProjection(
            connection: connection,
            agent: AgentProjection(
                id: id,
                terminalID: "term-\(connection.id)-\(id)",
                workspaceID: "workspace-\(id)",
                tabID: "tab-\(id)",
                focused: false,
                label: nil,
                agent: "codex",
                displayAgent: nil,
                name: identity,
                title: nil,
                agentStatus: state,
                revision: 1,
                launchPending: false
            ),
            workspaceLabel: "Workspace",
            tabLabel: "Tab"
        )
    }
}
