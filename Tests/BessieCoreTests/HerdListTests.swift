import XCTest
@testable import BessieCore

final class HerdListTests: XCTestCase {
    func testPresentationStatusesKeepIdleAndDoneDistinctAndExposeUnknown() {
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
            [.all: 5, .needsYou: 1, .working: 1, .done: 1, .idle: 1, .unknown: 1]
        )
        XCTAssertEqual(
            HerdListBuilder.cards(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"],
                filter: .done
            ).map(\.state),
            [.done]
        )
        XCTAssertEqual(
            HerdListBuilder.cards(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"],
                filter: .idle
            ).map(\.state),
            [.idle]
        )
        XCTAssertEqual(
            HerdListBuilder.cards(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"],
                filter: .unknown
            ).map(\.state),
            [.unknown]
        )
        XCTAssertEqual(HerdListFilter.allCases.map(\.rawValue), ["All", "Needs you", "Working", "Done", "Idle", "Unknown"])
        XCTAssertEqual(HerdPresentationStatus(state: .done), .done)
        XCTAssertEqual(HerdPresentationStatus(state: .idle), .idle)
        XCTAssertTrue(AgentSemanticState.blocked.requiresUserAction)
        XCTAssertFalse(AgentSemanticState.done.requiresUserAction)
    }

    func testUnknownControlsHideAtZeroAndSelectedUnknownNormalizesToAll() {
        XCTAssertEqual(
            HerdListFilter.visibleCases(unknownCount: 0),
            [.all, .needsYou, .working, .done, .idle]
        )
        XCTAssertEqual(
            HerdListFilter.visibleCases(unknownCount: 1),
            [.all, .needsYou, .working, .done, .idle, .unknown]
        )
        XCTAssertEqual(HerdListFilter.unknown.normalized(unknownCount: 0), .all)
        XCTAssertEqual(HerdListFilter.unknown.normalized(unknownCount: 1), .unknown)
        XCTAssertEqual(HerdListFilter.done.normalized(unknownCount: 0), .done)
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
             "local-bessie::working", "local-bessie::done", "local-bessie::idle"]
        )
        XCTAssertEqual(cards.suffix(2).map(\.presentationStatus), [.done, .idle])
        XCTAssertEqual(cards[0].connectionLabel, "example.test")
        XCTAssertEqual(cards[0].connectionDetail, "SSH · example.test · bessie")
        XCTAssertEqual(cards[1].location, "Alpha · Tab")
        XCTAssertEqual(cards[1].paneTarget.connectionID, "local-bessie")
        XCTAssertEqual(cards[1].paneTarget.workspaceID, "workspace-blocked-a")
        XCTAssertEqual(cards[1].paneTarget.tabID, "tab-blocked-a")
        XCTAssertEqual(cards[1].paneTarget.paneID, "blocked-a")
        XCTAssertNil(cards[1].activity)
    }

    func testPaneLabelIsPrimaryAndAgentSessionNameIsSecondary() {
        let connected = connected(
            id: "p3N",
            identity: "amp_mouse_investigation",
            state: "working",
            paneLabel: "Mouse Investigation"
        )

        XCTAssertEqual(connected.primaryTitle, "Mouse Investigation")
        XCTAssertEqual(connected.secondaryIdentity, "amp_mouse_investigation")

        let card = HerdListBuilder.cards(
            agents: [connected],
            connectedConnectionIDs: ["local-bessie"],
            filter: .all
        ).first
        XCTAssertEqual(card?.identity, "Mouse Investigation")
        XCTAssertEqual(card?.secondaryIdentity, "amp_mouse_investigation")
        XCTAssertEqual(card?.announcedIdentity, "Mouse Investigation, amp_mouse_investigation")
    }

    func testAgentIdentityIsHonestFallbackWithoutMatchingPaneProjectionAndIsNotDuplicated() {
        let connected = connected(id: "p3N", identity: "amp_mouse_investigation", state: "working")

        XCTAssertEqual(connected.primaryTitle, "amp_mouse_investigation")
        XCTAssertNil(connected.secondaryIdentity)

        let card = HerdListBuilder.cards(
            agents: [connected],
            connectedConnectionIDs: ["local-bessie"],
            filter: .all
        ).first
        XCTAssertEqual(card?.identity, "amp_mouse_investigation")
        XCTAssertNil(card?.secondaryIdentity)
        XCTAssertEqual(card?.announcedIdentity, "amp_mouse_investigation")
    }

    func testPanePresentationJoinRemainsConnectionScopedForCollidingPaneIDs() {
        let remote = BessieConnectionDefinition(
            id: "remote", name: "SSH", kind: .ssh, sshHost: "example.test", session: "bessie"
        )
        let local = connected(
            id: "p1", identity: "local-agent", state: "working", paneLabel: "Local pane"
        )
        let remoteAgent = connected(
            id: "p1", identity: "remote-agent", state: "working", connection: remote,
            paneLabel: "Remote pane"
        )

        let cards = HerdListBuilder.cards(
            agents: [local, remoteAgent],
            connectedConnectionIDs: ["local-bessie", "remote"],
            filter: .all
        )
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: cards.map { ($0.connectionID, $0.identity) }), [
            "local-bessie": "Local pane",
            "remote": "Remote pane",
        ])
        XCTAssertEqual(Set(cards.map(\.id)).count, 2)
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
            [.all: 1, .needsYou: 1, .working: 0, .done: 0, .idle: 0, .unknown: 0]
        )
        XCTAssertEqual(
            HerdListBuilder.counts(
                agents: agents,
                connectedConnectionIDs: ["local-bessie"]
            ),
            [.all: 1, .needsYou: 0, .working: 1, .done: 0, .idle: 0, .unknown: 0]
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
        XCTAssertEqual(rail.rows.map(\.group), [.needsYou, .working, .done, .idle, .unknown, .shells])
        XCTAssertEqual(rail.rows(in: .done).map(\.rawState), [.done])
        XCTAssertEqual(rail.rows(in: .idle).map(\.rawState), [.idle])
        XCTAssertEqual(Set(rail.rows.map(\.id)).count, 6)
        let blocked = try XCTUnwrap(rail.rows.first { $0.id.paneID == "blocked" })
        XCTAssertEqual(blocked.title, "Blocked pane")
        XCTAssertEqual(blocked.secondaryIdentity, "blocked-agent")
        XCTAssertEqual(blocked.accessibilityDescription, "Blocked pane, blocked-agent, Needs you, This Mac · bessie · build")
        XCTAssertEqual(rail.rows(in: .shells).first?.title, "tools")
        XCTAssertNil(rail.rows(in: .shells).first?.secondaryIdentity)
    }

    func testRailExcludesDisabledConnectionEvenWithFreshProjection() throws {
        let projection = try HerdrSessionProjection(snapshot: .railFixture)
        var disabled = BessieConnectionDefinition.localBessie
        disabled.enabled = false

        let rail = HerdRailProjection(connections: [
            HerdRailConnectionInput(connection: disabled, projection: projection, isFresh: true),
        ])

        XCTAssertTrue(rail.rows.isEmpty)
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

    func testPanePresentationRoutesEveryRowOnceWithPinnedPrecedence() throws {
        let base = HerdRailProjection(connections: [
            HerdRailConnectionInput(
                connection: .localBessie,
                projection: try HerdrSessionProjection(snapshot: .railFixture),
                isFresh: true
            ),
        ])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ledger = try BessiePanePresentationLedger(records: [
            BessiePanePresentationPreference(
                connectionID: "local-bessie", paneID: "blocked", terminalID: "term-blocked",
                pinned: true
            ),
            BessiePanePresentationPreference(
                connectionID: "local-bessie", paneID: "working", terminalID: "term-working",
                snooze: .indefinite
            ),
            BessiePanePresentationPreference(
                connectionID: "local-bessie", paneID: "done", terminalID: "term-done",
                pinned: true, snooze: .until(now.addingTimeInterval(3_600), provenance: .oneHour)
            ),
            BessiePanePresentationPreference(
                connectionID: "local-bessie", paneID: "shell", terminalID: "term-shell",
                snooze: .indefinite
            ),
        ], now: now)

        let routed = HerdRailPresentation(base: base, ledger: ledger, now: now)

        XCTAssertEqual(routed.pinnedRows.map(\.base.id.paneID), ["blocked", "done"])
        XCTAssertEqual(routed.snoozedRows.map(\.base.id.paneID), ["working", "shell"])
        XCTAssertTrue(routed.rows(in: .done).isEmpty)
        XCTAssertEqual(routed.rows(in: .idle).map(\.base.id.paneID), ["idle"])
        XCTAssertEqual(routed.rows(in: .unknown).map(\.base.id.paneID), ["unknown"])
        XCTAssertTrue(routed.shellRows.isEmpty)
        XCTAssertEqual(Set(routed.allRows.map(\.base.id)), Set(base.rows.map(\.id)))
        XCTAssertEqual(routed.allRows.count, base.rows.count)
        XCTAssertEqual(routed.awakeAttentionCount, 1)
        XCTAssertFalse(routed.navigationRows.contains { $0.isSnoozed })
        XCTAssertEqual(routed.navigationRows.first?.base.id.paneID, "blocked")
        XCTAssertFalse(routed.navigationRows.contains { $0.base.id.paneID == "done" })
        XCTAssertEqual(routed.pinnedRows.last?.snooze?.provenance, .oneHour)
        XCTAssertTrue(routed.navigationRows.contains { $0.base.id.paneID == "unknown" })
    }

    func testPanePresentationIgnoresStaleIncarnationAndExpiredSnooze() throws {
        let base = HerdRailProjection(connections: [
            HerdRailConnectionInput(
                connection: .localBessie,
                projection: try HerdrSessionProjection(snapshot: .railFixture),
                isFresh: true
            ),
        ])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ledger = try BessiePanePresentationLedger(records: [
            BessiePanePresentationPreference(
                connectionID: "local-bessie", paneID: "blocked", terminalID: "reused-terminal",
                pinned: true
            ),
            BessiePanePresentationPreference(
                connectionID: "local-bessie", paneID: "working", terminalID: "term-working",
                snooze: .until(now.addingTimeInterval(-1), provenance: .oneHour)
            ),
        ], now: .distantPast)

        let routed = HerdRailPresentation(base: base, ledger: ledger, now: now)

        XCTAssertTrue(routed.pinnedRows.isEmpty)
        XCTAssertTrue(routed.snoozedRows.isEmpty)
        XCTAssertEqual(routed.rows(in: .needsYou).map(\.base.id.paneID), ["blocked"])
        XCTAssertEqual(routed.rows(in: .working).map(\.base.id.paneID), ["working"])
        XCTAssertEqual(routed.awakeAttentionCount, 1)
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
        workspaceLabel: String = "Workspace",
        paneLabel: String? = nil
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
            tabLabel: "Tab",
            pane: paneLabel.map {
                PaneProjection(
                    id: id,
                    terminalID: "term-\(id)",
                    workspaceID: "workspace-\(id)",
                    tabID: "tab-\(id)",
                    focused: false,
                    label: $0,
                    cwd: nil,
                    foregroundCWD: nil,
                    agent: "amp",
                    title: nil,
                    agentStatus: state,
                    revision: 1
                )
            }
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
            .object(["pane_id": .string(id), "terminal_id": .string("term-\(id)"), "workspace_id": .string("w"), "tab_id": .string("t"), "focused": .bool(id == "blocked"), "label": .string(id == "shell" ? "tools" : (id == "blocked" ? "Blocked pane" : id)), "agent_status": .string(id), "revision": .number(1)])
        },
        layouts: [],
        agents: ["blocked", "working", "done", "idle", "unknown"].map { id in
            .object(["pane_id": .string(id), "terminal_id": .string("term-\(id)"), "workspace_id": .string("w"), "tab_id": .string("t"), "agent": .string("codex"), "name": .string(id == "blocked" ? "blocked-agent" : id), "agent_status": .string(id), "revision": .number(2)])
        }
    )
}
