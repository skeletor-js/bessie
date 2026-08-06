import XCTest
@testable import BessieCore

final class HerdListTests: XCTestCase {
    func testPresentationBucketsAggregateSettledAndExposeUnknown() {
        let agents = [
            connected(id: "blocked", state: "blocked"),
            connected(id: "working", state: "working"),
            connected(id: "done", state: "done"),
            connected(id: "idle", state: "idle"),
            connected(id: "unknown", state: "something-new"),
        ]

        XCTAssertEqual(
            HerdListBuilder.cards(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"],
                filter: .needsYou
            ).map(\.state),
            [.blocked]
        )
        XCTAssertEqual(
            HerdListBuilder.counts(agents: agents, connectedConnectionIDs: ["local-bessie"]),
            [.all: 5, .needsYou: 1, .working: 1, .settled: 2, .unknown: 1]
        )
        XCTAssertEqual(
            HerdListBuilder.cards(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"],
                filter: .settled
            ).map(\.state),
            [.done, .idle]
        )
        XCTAssertEqual(
            HerdListBuilder.cards(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"],
                filter: .unknown
            ).map(\.state),
            [.unknown]
        )
        XCTAssertEqual(HerdListFilter.allCases.map(\.rawValue), ["All", "Needs you", "Working", "Settled", "Unknown"])
        XCTAssertEqual(HerdPresentationStatus(state: .done), .settled)
        XCTAssertEqual(HerdPresentationStatus(state: .idle), .settled)
        XCTAssertTrue(AgentSemanticState.blocked.requiresUserAction)
        XCTAssertFalse(AgentSemanticState.done.requiresUserAction)
    }

    func testCardsSortByStateConnectionLocationAndIdentityAndKeepExactTarget() {
        let remote = BessieConnectionDefinition(
            id: "remote", name: "SSH", kind: .ssh, sshHost: "example.test", session: "bessie"
        )
        let agents = [
            connected(id: "idle", identity: "Alpha", state: "idle"),
            connected(id: "done", identity: "Zulu", state: "done"),
            connected(id: "working", identity: "Beta", state: "working"),
            connected(id: "blocked-z", identity: "Zulu", state: "blocked", workspaceLabel: "Zulu"),
            connected(id: "blocked-a", identity: "Alpha", state: "blocked", workspaceLabel: "Alpha"),
            connected(id: "identity-z", identity: "Zulu", state: "blocked", workspaceLabel: "Same"),
            connected(id: "identity-a-2", identity: "Alpha", state: "blocked", workspaceLabel: "Same"),
            connected(id: "identity-a-1", identity: "Alpha", state: "blocked", workspaceLabel: "Same"),
            connected(id: "remote-blocked", identity: "Remote", state: "blocked", connection: remote),
        ]

        let cards = HerdListBuilder.cards(
            agents: agents,
            connectedConnectionIDs: ["local-bessie", "remote"],
            filter: .all
        )

        XCTAssertEqual(
            cards.map(\.id),
            ["remote::remote-blocked", "local-bessie::blocked-a", "local-bessie::identity-a-1",
             "local-bessie::identity-a-2", "local-bessie::identity-z", "local-bessie::blocked-z",
             "local-bessie::working", "local-bessie::idle", "local-bessie::done"]
        )
        XCTAssertEqual(cards.suffix(2).map(\.presentationStatus), [.settled, .settled])
        XCTAssertEqual(cards[0].connectionLabel, "example.test")
        XCTAssertEqual(cards[0].connectionDetail, "SSH · example.test · bessie")
        XCTAssertEqual(cards[1].location, "Alpha · Tab")
        XCTAssertEqual(cards[1].paneTarget.connectionID, "local-bessie")
        XCTAssertEqual(cards[1].paneTarget.workspaceID, "workspace-blocked-a")
        XCTAssertEqual(cards[1].paneTarget.tabID, "tab-blocked-a")
        XCTAssertEqual(cards[1].paneTarget.paneID, "blocked-a")
        XCTAssertNil(cards[1].activity)
    }

    func testScopeAndConnectionAvailabilityApplyBeforeCardsAndCounts() {
        let remote = BessieConnectionDefinition(
            id: "remote", name: "Remote", kind: .ssh, sshHost: "example.test", session: nil
        )
        let agents = [
            connected(id: "local", state: "working"),
            connected(id: "remote-blocked", state: "blocked", connection: remote),
        ]

        XCTAssertEqual(
            HerdListBuilder.cards(
                agents: agents,
                connectedConnectionIDs: ["local-bessie", "remote"],
                scope: .connection(id: "remote"),
                filter: .all
            ).map(\.paneTarget.connectionID),
            ["remote"]
        )
        XCTAssertEqual(
            HerdListBuilder.counts(
                agents: agents,
                connectedConnectionIDs: ["local-bessie", "remote"],
                scope: .connection(id: "remote")
            ),
            [.all: 1, .needsYou: 1, .working: 0, .settled: 0, .unknown: 0]
        )
        XCTAssertEqual(
            HerdListBuilder.counts(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"]
            ),
            [.all: 1, .needsYou: 0, .working: 1, .settled: 0, .unknown: 0]
        )
        XCTAssertTrue(
            HerdListBuilder.cards(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"],
                filter: .needsYou
            ).isEmpty,
            "A stale blocked agent from a disconnected connection must not remain live Needs you"
        )
    }

    func testRailProjectsEveryFreshPaneExactlyOnceAndSeparatesShells() throws {
        let projection = try HerdrSessionProjection(snapshot: .railFixture)
        let fresh = HerdRailConnectionInput(connection: .localBessie, projection: projection, isFresh: true)
        let stale = HerdRailConnectionInput(
            connection: BessieConnectionDefinition(id: "stale", name: "Stale", kind: .ssh, sshHost: "stale.test", session: nil),
            projection: projection,
            isFresh: false
        )
        let rail = HerdRailProjection(connections: [fresh, stale])

        XCTAssertEqual(rail.rows.map(\.id), [
            HerdPaneIdentity(connectionID: "local-bessie", paneID: "blocked"),
            HerdPaneIdentity(connectionID: "local-bessie", paneID: "working"),
            HerdPaneIdentity(connectionID: "local-bessie", paneID: "done"),
            HerdPaneIdentity(connectionID: "local-bessie", paneID: "idle"),
            HerdPaneIdentity(connectionID: "local-bessie", paneID: "unknown"),
            HerdPaneIdentity(connectionID: "local-bessie", paneID: "shell"),
        ])
        XCTAssertEqual(rail.rows.map(\.group), [.needsYou, .working, .settled, .settled, .unknown, .shells])
        XCTAssertEqual(rail.rows(in: .settled).map(\.rawState), [.done, .idle])
        XCTAssertEqual(Set(rail.rows.map(\.id)).count, 6)
        XCTAssertEqual(rail.rows(in: .shells).first?.title, "tools")
    }

    func testRailWorkspaceFilterIsIndependentOfOpenPaneSelection() throws {
        let projection = try HerdrSessionProjection(snapshot: .railFixture)
        let fresh = HerdRailConnectionInput(connection: .localBessie, projection: projection, isFresh: true)
        let rail = HerdRailProjection(connections: [fresh])
        XCTAssertEqual(rail.filtered(connectionID: nil, workspaceID: nil).rows.count, 6)

        let filtered = rail.filtered(connectionID: "local-bessie", workspaceID: "w")
        // railFixture uses one workspace ("w") for all panes — filter keeps them all when IDs match.
        XCTAssertEqual(filtered.rows.count, 6)
        XCTAssertTrue(filtered.rows.allSatisfy { $0.target.workspaceID == "w" })

        let empty = rail.filtered(connectionID: "local-bessie", workspaceID: "other")
        XCTAssertTrue(empty.rows.isEmpty)
    }

    func testRailTraversalHandlesZeroOneManyAndBidirectionalWrap() {
        let a = HerdPaneIdentity(connectionID: "local", paneID: "a")
        let b = HerdPaneIdentity(connectionID: "remote", paneID: "a")
        let c = HerdPaneIdentity(connectionID: "local", paneID: "c")

        XCTAssertNil(HerdPaneTraversal([]).target(from: nil, direction: .next))
        XCTAssertEqual(HerdPaneTraversal([a]).target(from: a, direction: .previous), a)
        let traversal = HerdPaneTraversal([a, b, c])
        XCTAssertEqual(traversal.target(from: c, direction: .next), a)
        XCTAssertEqual(traversal.target(from: a, direction: .previous), c)
        XCTAssertEqual(traversal.target(from: b, direction: .next), c)
        XCTAssertEqual(traversal.target(from: nil, direction: .previous), c)
    }

    private func connected(
        id: String,
        identity: String? = nil,
        state: String,
        connection: BessieConnectionDefinition = .localBessie,
        workspaceLabel: String = "Workspace"
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
            workspaceLabel: workspaceLabel,
            tabLabel: "Tab"
        )
    }
}

private extension HerdrSnapshot {
    static let railFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "w", focusedTabID: "t", focusedPaneID: "blocked",
        workspaces: [.object(["workspace_id": .string("w"), "number": .number(1), "label": .string("bessie"), "focused": .bool(true), "pane_count": .number(6), "tab_count": .number(1), "active_tab_id": .string("t"), "agent_status": .string("blocked")])],
        tabs: [.object(["tab_id": .string("t"), "workspace_id": .string("w"), "number": .number(1), "label": .string("build"), "focused": .bool(true), "pane_count": .number(6), "agent_status": .string("blocked")])],
        panes: ["blocked", "working", "done", "idle", "unknown", "shell"].map { id in
            .object(["pane_id": .string(id), "terminal_id": .string("term-\(id)"), "workspace_id": .string("w"), "tab_id": .string("t"), "focused": .bool(id == "blocked"), "label": .string(id == "shell" ? "tools" : id), "agent_status": .string(id), "revision": .number(1)])
        },
        layouts: [],
        agents: ["blocked", "working", "done", "idle", "unknown"].map { id in
            .object(["pane_id": .string(id), "terminal_id": .string("term-\(id)"), "workspace_id": .string("w"), "tab_id": .string("t"), "agent": .string("codex"), "name": .string(id), "agent_status": .string(id), "revision": .number(2)])
        }
    )
}
