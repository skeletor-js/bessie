import XCTest
@testable import BessieCore

final class HerdListTests: XCTestCase {
    func testNeedsYouIncludesBlockedOnlyAndCountsEveryFilter() {
        let agents = [
            connected(id: "blocked", state: "blocked"),
            connected(id: "working", state: "working"),
            connected(id: "done", state: "done"),
            connected(id: "idle", state: "idle"),
            connected(id: "unknown", state: "something-new"),
        ]

        XCTAssertEqual(
            HerdListBuilder.cards(agents: agents, filter: .needsYou).map(\.state),
            [.blocked]
        )
        XCTAssertEqual(
            HerdListBuilder.counts(agents: agents),
            [.all: 5, .needsYou: 1, .working: 1, .done: 1, .idle: 1]
        )
    }

    func testCardsSortByStateConnectionAndIdentityAndKeepHonestLabels() {
        let remote = BessieConnectionDefinition(
            id: "remote", name: "SSH", kind: .ssh, sshHost: "hermes-vps", session: "bessie"
        )
        let agents = [
            connected(id: "idle", identity: "Alpha", state: "idle"),
            connected(id: "done", identity: "Zulu", state: "done"),
            connected(id: "working", identity: "Beta", state: "working"),
            connected(id: "blocked-z", identity: "Zulu", state: "blocked"),
            connected(id: "blocked-a", identity: "Alpha", state: "blocked"),
            connected(id: "remote-blocked", identity: "Remote", state: "blocked", connection: remote),
        ]

        let cards = HerdListBuilder.cards(agents: agents, filter: .all)

        XCTAssertEqual(cards.map(\.identity), ["Remote", "Alpha", "Zulu", "Beta", "Zulu", "Alpha"])
        XCTAssertEqual(cards[0].connectionLabel, "hermes-vps")
        XCTAssertEqual(cards[0].connectionDetail, "SSH · hermes-vps · bessie")
        XCTAssertEqual(cards[1].location, "Workspace · Tab")
        XCTAssertEqual(cards[1].paneTarget.connectionID, "local-bessie")
        XCTAssertNil(cards[1].activity)
    }

    private func connected(
        id: String,
        identity: String? = nil,
        state: String,
        connection: BessieConnectionDefinition = .localBessie
    ) -> ConnectedAgentProjection {
        ConnectedAgentProjection(
            connection: connection,
            agent: AgentProjection(
                id: id,
                terminalID: "term-\(id)",
                workspaceID: "workspace-\(id)",
                tabID: "tab-\(id)",
                focused: false,
                label: nil,
                agent: "codex",
                displayAgent: nil,
                name: identity ?? id,
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
