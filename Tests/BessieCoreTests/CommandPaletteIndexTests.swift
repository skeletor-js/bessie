import XCTest
@testable import BessieCore

final class CommandPaletteIndexTests: XCTestCase {
    func testTypedStateDrivesPresentationAndStateWordSearch() {
        let index = build(connections: [
            connection(panes: [
                pane("blocked", title: "Compiler", state: .blocked),
                pane("done", title: "Tests", state: .done),
                pane("idle", title: "Docs", state: .idle),
                pane("unknown", title: "Shell", state: .unknown),
            ]),
        ])

        XCTAssertEqual(index.entity(id: paneID("local", "blocked"))?.semanticState, .blocked)
        XCTAssertEqual(
            index.sections.first(where: { $0.kind == .needsYou })?.entities.map(\.id),
            [paneID("local", "blocked")]
        )
        XCTAssertEqual(
            index.results(query: "needs").filter { $0.kind == .pane }.map(\.id),
            [paneID("local", "blocked")]
        )
        XCTAssertEqual(HerdPresentationStatus(state: .done), .done)
        XCTAssertEqual(HerdPresentationStatus(state: .idle), .idle)
        XCTAssertEqual(HerdPresentationStatus(state: .unknown), .unknown)
        XCTAssertEqual(index.results(query: "done").filter { $0.kind == .pane }.map(\.id), [paneID("local", "done")])
        XCTAssertEqual(index.results(query: "idle").filter { $0.kind == .pane }.map(\.id), [paneID("local", "idle")])
    }

    func testBrowseSectionsAreCuratedCompleteAndDeterministic() {
        let blocked = pane("blocked", title: "Needs input", state: .blocked)
        let ordinary = pane("ordinary", title: "Ordinary", state: .working)
        let workspace = CommandPaletteWorkspaceInput(
            id: "w", number: 1, title: "Bessie", tabCount: 2, paneCount: 2, semanticState: .blocked
        )
        let project = CommandPaletteProjectInput(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Command Center", detail: "Project · 2 panes", location: "/tmp/command-center",
            keywords: ["automation"], isRunning: false
        )
        let first = build(
            connections: [connection(panes: [ordinary, blocked], workspaces: [workspace])],
            projects: [project],
            mru: CommandPaletteMRU(ids: [paneID("local", "blocked"), paneID("local", "ordinary")])
        )
        let second = build(
            connections: [connection(panes: [blocked, ordinary], workspaces: [workspace])],
            projects: [project],
            mru: CommandPaletteMRU(ids: [paneID("local", "blocked"), paneID("local", "ordinary")])
        )

        XCTAssertEqual(first.sections.map(\.kind), [.needsYou, .recent, .workspaces, .projects, .herds, .commands])
        XCTAssertEqual(first.sections, second.sections)
        XCTAssertEqual(first.sections.first(where: { $0.kind == .needsYou })?.entities.map(\.id), [paneID("local", "blocked")])
        XCTAssertEqual(first.sections.first(where: { $0.kind == .recent })?.entities.map(\.id), [paneID("local", "ordinary")])
        XCTAssertFalse(
            first.sections.filter { ![.needsYou, .recent].contains($0.kind) }
                .flatMap(\.entities).contains(where: { $0.kind == .pane })
        )
        XCTAssertEqual(first.sections.first(where: { $0.kind == .commands })?.entities.count,
                       BessieKeyboardShortcutRouter.commands.count - 1)
    }

    func testTopologyCommandsRemainDiscoverableWithPrefixBindings() {
        let commands = BessieKeyboardShortcutRouter.commands
        let expected: [(BessieShortcutCommand, String)] = [
            (.newWorkspace, "Ctrl-B Shift-N"),
            (.newTab, "Ctrl-B c"),
            (.splitPane(.right), "Ctrl-B v"),
            (.closePane, "Ctrl-B x"),
            (.closeWorkspace, "Ctrl-B Shift-D"),
        ]

        for (command, binding) in expected {
            XCTAssertEqual(commands.first(where: { $0.command == command })?.shortcut, binding)
        }
        XCTAssertEqual(commands.first(where: { $0.command == .projectsPicker })?.shortcut, "⌥⌘P")
    }

    func testKeyboardReferenceIsDiscoverableWithoutANativeAccelerator() throws {
        let command = try XCTUnwrap(
            BessieKeyboardShortcutRouter.commands.first { $0.command == .showKeyboardReference }
        )

        XCTAssertEqual(command.title, "Keyboard reference")
        XCTAssertNil(command.shortcut)
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.commands.filter { $0.command == .showKeyboardReference }.count,
            1
        )
    }

    func testQueryTieBreaksByAttentionActiveConnectionKindAndStableID() {
        let remote = CommandPaletteConnectionInput(
            connection: .init(id: "remote", name: "Remote", kind: .ssh, sshHost: "remote.test"),
            freshness: .fresh,
            healthDetail: "Connected",
            panes: [pane("same", title: "map", state: .blocked)],
            workspaces: []
        )
        let local = connection(panes: [
            pane("settled", title: "map", state: .done),
            pane("blocked-z", title: "map", state: .blocked),
            pane("blocked-a", title: "map", state: .blocked),
        ])
        let index = build(connections: [local, remote], activeConnectionID: "local")

        XCTAssertEqual(index.results(query: "map").filter { $0.kind == .pane }.map(\.id), [
            paneID("local", "blocked-a"),
            paneID("local", "blocked-z"),
            paneID("remote", "same"),
            paneID("local", "settled"),
        ])
    }

    func testConnectionScopeOnlyInfluencesRankingAndNeverFiltersOtherFreshHerds() {
        let local = connection(panes: [pane("same", title: "scratch")])
        let remote = CommandPaletteConnectionInput(
            connection: .init(id: "remote", name: "Remote", kind: .ssh, sshHost: "remote.test"),
            freshness: .fresh,
            healthDetail: "Connected",
            panes: [pane("same", title: "scratch")],
            workspaces: []
        )
        let index = build(
            connections: [local, remote],
            activeConnectionID: "local",
            scope: .connection(id: "remote")
        )

        XCTAssertEqual(index.results(query: "scratch").filter { $0.kind == .pane }.map(\.id), [
            paneID("remote", "same"), paneID("local", "same"),
        ])
    }

    func testCrossHerdIdentitySurvivesMovesAndDisconnectedTopologyIsExcluded() {
        let local = connection(panes: [pane("same", title: "scratch", workspaceID: "w1", tabID: "t1")])
        let remote = CommandPaletteConnectionInput(
            connection: .init(id: "remote", name: "CI", kind: .ssh, sshHost: "ci.test"),
            freshness: .fresh,
            healthDetail: "Connected",
            panes: [pane("same", title: "scratch", workspaceID: "w2", tabID: "t2")],
            workspaces: []
        )
        let stale = CommandPaletteConnectionInput(
            connection: .init(id: "stale", name: "Stale", kind: .ssh, sshHost: "stale.test"),
            freshness: .disconnected,
            healthDetail: "Connection lost",
            panes: [pane("ghost", title: "ghost")],
            workspaces: [.init(id: "ghost-w", number: 1, title: "Ghost", tabCount: 1, paneCount: 1, semanticState: .unknown)]
        )
        let first = build(connections: [local, remote, stale])
        let moved = build(connections: [
            connection(panes: [pane("same", title: "scratch", workspaceID: "moved-w", tabID: "moved-t")]),
            remote,
            stale,
        ])

        XCTAssertEqual(
            first.results(query: "scratch").filter { $0.kind == .pane }.map(\.id),
            [paneID("local", "same"), paneID("remote", "same")]
        )
        XCTAssertEqual(first.entity(id: paneID("local", "same"))?.id, moved.entity(id: paneID("local", "same"))?.id)
        XCTAssertEqual(moved.entity(id: paneID("local", "same"))?.route,
                       .pane(connectionID: "local", workspaceID: "moved-w", tabID: "moved-t", paneID: "same"))
        XCTAssertNil(first.entity(id: paneID("stale", "ghost")))
        let staleEntity = first.entity(id: .init(kind: .connection, components: ["stale"]))
        XCTAssertEqual(staleEntity?.freshness, .disconnected)
        XCTAssertEqual(staleEntity?.detail, "Connection lost")
    }

    func testMRUCapsDeduplicatesDropsMissingAndKeepsMovedPaneIdentity() {
        var mru = CommandPaletteMRU()
        for number in 0..<8 {
            mru.record(.init(kind: .pane, components: ["local", "p\(number)"]))
        }
        mru.record(.init(kind: .pane, components: ["local", "p3"]))
        XCTAssertEqual(mru.ids.count, 6)
        XCTAssertEqual(mru.ids.first, paneID("local", "p3"))

        let live = (2..<8).map { pane("p\($0)", title: "Pane \($0)", workspaceID: "moved", tabID: "new") }
        let index = build(connections: [connection(panes: live)], mru: mru)
        let recent = index.sections.first(where: { $0.kind == .recent })?.entities ?? []

        XCTAssertEqual(recent.first?.id, paneID("local", "p3"))
        XCTAssertFalse(recent.contains(where: { $0.id == paneID("local", "p1") }))
        XCTAssertTrue(recent.allSatisfy { $0.route.descriptionForTest.contains("moved") })
    }

    func testDuplicateInputsMergeWithoutTrappingAndHaveDeterministicWinner() {
        let sparse = pane("duplicate", title: "Duplicate", detail: "Pane", location: nil)
        let rich = pane("duplicate", title: "Duplicate", detail: "Agent pane", location: "Local / Bessie / Main")
        let first = build(connections: [connection(panes: [sparse, rich])])
        let second = build(connections: [connection(panes: [rich, sparse])])

        XCTAssertEqual(first.allEntities, second.allEntities)
        XCTAssertEqual(first.allEntities.filter { $0.id == paneID("local", "duplicate") }.count, 1)
        XCTAssertEqual(first.entity(id: paneID("local", "duplicate"))?.location, "Local / Bessie / Main")
    }

    private func build(
        connections: [CommandPaletteConnectionInput],
        projects: [CommandPaletteProjectInput] = [],
        activeConnectionID: String = "local",
        scope: ConnectionScope = .all,
        mru: CommandPaletteMRU = .init()
    ) -> CommandPaletteIndex {
        CommandPaletteIndexBuilder().build(.init(
            connections: connections,
            projects: projects,
            commands: BessieKeyboardShortcutRouter.commands,
            context: .init(
                activeConnectionID: activeConnectionID,
                scope: scope,
                focusedWorkspaceID: "w",
                focusedPaneID: nil,
                mru: mru
            )
        ))
    }

    private func connection(
        panes: [CommandPalettePaneInput] = [],
        workspaces: [CommandPaletteWorkspaceInput] = []
    ) -> CommandPaletteConnectionInput {
        .init(
            connection: .init(id: "local", name: "Local", kind: .local),
            freshness: .fresh,
            healthDetail: "Connected",
            panes: panes,
            workspaces: workspaces
        )
    }

    private func pane(
        _ id: String,
        title: String,
        detail: String = "Agent pane",
        state: AgentSemanticState = .working,
        workspaceID: String = "w",
        tabID: String = "t",
        location: String? = "Local / Bessie / Main"
    ) -> CommandPalettePaneInput {
        .init(
            id: id,
            workspaceID: workspaceID,
            workspaceTitle: "Bessie",
            tabID: tabID,
            tabTitle: "Main",
            title: title,
            detail: detail,
            semanticState: state,
            provider: "codex",
            location: location,
            keywords: ["codex"]
        )
    }

    private func paneID(_ connectionID: String, _ paneID: String) -> CommandPaletteEntityID {
        .init(kind: .pane, components: [connectionID, paneID])
    }
}

private extension CommandPaletteRouteIntent {
    var descriptionForTest: String {
        switch self {
        case .pane(_, let workspaceID, _, _): workspaceID
        default: ""
        }
    }
}
