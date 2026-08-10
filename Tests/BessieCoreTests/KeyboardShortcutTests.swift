import XCTest
@testable import BessieCore

final class KeyboardShortcutTests: XCTestCase {
    func testRemovedNativeTopologyChordsReturnToAppKitOrTerminalPolicy() {
        let removedTopology: [BessieShortcutStroke] = [
            .init(key: .character("n"), command: true),
            .init(key: .character("w"), command: true),
            .init(key: .character("w"), command: true, shift: true),
            .init(key: .character("g"), command: true, shift: true),
            .init(key: .character("t"), command: true),
            .init(key: .character("1"), command: true),
            .init(key: .character("["), command: true),
            .init(key: .character("]"), command: true),
            .init(key: .character("["), command: true, shift: true),
            .init(key: .character("]"), command: true, shift: true),
            .init(key: .character("d"), command: true),
            .init(key: .character("d"), command: true, shift: true),
            .init(key: .character("t"), option: true, command: true),
            .init(key: .character("r"), option: true, command: true),
            .init(key: .character("x"), option: true, command: true),
            .init(key: .leftArrow, option: true, command: true),
            .init(key: .downArrow, option: true, command: true, shift: true),
            .init(key: .rightArrow, control: true, command: true),
        ]

        for stroke in removedTopology {
            XCTAssertEqual(
                BessieKeyboardShortcutRouter.policy(for: stroke),
                .passthrough,
                "Removed topology chord is still claimed: \(stroke)"
            )
        }
    }

    func testTerminalAndAppKitOwnershipAfterPrefixMigration() {
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("b"), command: true)),
            .passthrough
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("c"), command: true)),
            .terminalShortcut(.copy)
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("v"), command: true)),
            .terminalShortcut(.paste)
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("c"), control: true)),
            .passthrough
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("q"), command: true)),
            .passthrough
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("p"), option: true, command: true)),
            .appCommand(.projectsPicker)
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("p"), option: true)),
            .passthrough
        )
    }

    func testNonCommandInputAlwaysPassesThroughToTerminal() {
        let router = BessieKeyboardShortcutRouter()
        XCTAssertEqual(router.handle(.init(key: .character("b"), control: true)), .passthrough)
        XCTAssertEqual(router.handle(.init(key: .character("d"))), .passthrough)
        // Option+arrows are Ghostty word-motion terminal shortcuts (ESC b / ESC f).
        XCTAssertEqual(
            router.handle(.init(key: .leftArrow, option: true)),
            .terminalShortcut(.sendBytes(Data([0x1b, 0x62])))
        )
        XCTAssertEqual(router.handle(.init(key: .character("x"), option: true)), .passthrough)
    }

    func testSystemCommandShortcutsPassThroughToAppKit() {
        let systemKeys = ["q", "H", "m", "`"]
        for key in systemKeys {
            XCTAssertEqual(
                BessieKeyboardShortcutRouter.policy(for: .init(key: .character(key), command: true)),
                .passthrough,
                "Command-\(key.uppercased()) must remain owned by AppKit"
            )
        }
    }

    func testCommandBIsUnclaimedAndPaletteUsesShiftCommandP() {
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("b"), command: true)),
            .passthrough
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("p"), command: true, shift: true)),
            .appCommand(.showCommandPalette)
        )
    }

    func testCommandCIsCopyOnlyAndControlCRemainsTerminalInput() {
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("c"), command: true)),
            .terminalShortcut(.copy)
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("c"), control: true)),
            .passthrough
        )
    }

    func testGhosttyMacOSTerminalShortcutMatrix() {
        let cases: [(BessieShortcutStroke, BessieTerminalShortcutAction)] = [
            (.init(key: .character("c"), command: true), .copy),
            (.init(key: .character("v"), command: true), .paste),
            (.init(key: .character("k"), command: true), .clearScrollback),
            (.init(key: .character("a"), command: true), .selectAll),
            (.init(key: .character("a"), command: true, shift: true), .selectPreviousCommandOutput),
            (.init(key: .character("g"), command: true), .sendBytes(Data([0x01, 0x0b]))),
            (.init(key: .backspace, command: true), .sendBytes(Data([0x15]))),
            (.init(key: .leftArrow, command: true), .sendBytes(Data([0x01]))),
            (.init(key: .rightArrow, command: true), .sendBytes(Data([0x05]))),
            (.init(key: .leftArrow, option: true), .sendBytes(Data([0x1b, 0x62]))),
            (.init(key: .rightArrow, option: true), .sendBytes(Data([0x1b, 0x66]))),
            (.init(key: .upArrow, command: true), .jumpToPrompt(-1)),
            (.init(key: .downArrow, command: true), .jumpToPrompt(1)),
            (.init(key: .upArrow, command: true, shift: true), .jumpToPrompt(-1)),
            (.init(key: .downArrow, command: true, shift: true), .jumpToPrompt(1)),
        ]

        for (stroke, action) in cases {
            XCTAssertEqual(
                BessieKeyboardShortcutRouter.policy(for: stroke),
                .terminalShortcut(action),
                "Unexpected policy for \(stroke)"
            )
        }
    }

    func testTerminalShortcutsRequireExactModifiers() {
        let passthrough: [BessieShortcutStroke] = [
            .init(key: .character("b"), option: true, command: true),
            .init(key: .character("c"), command: true, shift: true),
            .init(key: .character("v"), command: true, shift: true),
            .init(key: .character("k"), control: true, command: true),
            .init(key: .rightArrow, control: true, option: true, command: true),
        ]

        for stroke in passthrough {
            XCTAssertEqual(BessieKeyboardShortcutRouter.policy(for: stroke), .passthrough)
        }
    }

    func testNativeApplicationAllowlistRemainsAvailable() {
        let cases: [(BessieShortcutStroke, BessieShortcutCommand)] = [
            (.init(key: .character("p"), command: true, shift: true), .showCommandPalette),
            (.init(key: .character("b"), command: true, shift: true), .toggleSidebar),
            (.init(key: .character("j"), command: true, shift: true), .nextRailPane),
            (.init(key: .character("k"), command: true, shift: true), .previousRailPane),
            (.init(key: .character("p"), option: true, command: true), .projectsPicker),
            (.init(key: .character(","), command: true), .showSettings),
            (.init(key: .character("n"), option: true, command: true), .openNextNeedsYou),
            (.init(key: .character("z"), command: true, shift: true), .toggleZen),
            (.init(key: .character("["), option: true, command: true, shift: true), .previousAgent),
            (.init(key: .character("]"), option: true, command: true, shift: true), .nextAgent),
        ]
        let router = BessieKeyboardShortcutRouter()
        for (stroke, command) in cases {
            XCTAssertEqual(router.handle(stroke), .command(command))
        }
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("w"), command: true)),
            .passthrough,
            "Command-W must retain standard AppKit window-close ownership"
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("p"), option: true)),
            .passthrough
        )
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.commands.first(where: { $0.command == .closeTab })?.shortcut,
            "Ctrl-B Shift-X"
        )
    }

    func testZenCommandsDoNotConsumeOrdinaryTerminalInput() {
        let router = BessieKeyboardShortcutRouter()
        for stroke in [
            BessieShortcutStroke(key: .character("z")),
            BessieShortcutStroke(key: .character("z"), shift: true),
            BessieShortcutStroke(key: .character("["), option: true, shift: true),
            BessieShortcutStroke(key: .character("]"), option: true, shift: true),
            BessieShortcutStroke(key: .character("n"), option: true),
        ] {
            XCTAssertEqual(router.handle(stroke), .passthrough)
        }
    }

    func testZenPresentationTransitionsPreservePaneAndRequestTerminalFocusWithoutHerdrMutation() {
        var state = BessieZenPresentationState.inactive

        state.enter(paneID: "pane-2", railCollapsed: false)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.selectedPaneID, "pane-2")
        XCTAssertEqual(state.focusIntent, .terminal(paneID: "pane-2", revision: 1))
        XCTAssertEqual(BessieZenPresentationState.transitionEffect, .presentationOnly)

        XCTAssertFalse(state.exit())
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.selectedPaneID, "pane-2")
        // Focus is deferred to the shell after detach — exit must not poke the
        // terminal while the Zen surface is tearing down.
        XCTAssertNil(state.focusIntent)
        XCTAssertEqual(BessieZenPresentationState.transitionEffect, .presentationOnly)

        state.enter(paneID: "pane-2", railCollapsed: true)
        XCTAssertFalse(state.exit(expandRail: true))
        state.enter(paneID: "pane-2", railCollapsed: true)
        XCTAssertTrue(state.exit())
    }

    func testZenAgentRoutingUsesAuthoritativeOrderAndWraps() {
        let agents = [
            Self.agent(connectionID: "local", paneID: "p2", status: "working"),
            Self.agent(connectionID: "local", paneID: "p1", status: "idle"),
            Self.agent(connectionID: "remote", paneID: "p3", status: "done"),
        ]
        let current = RoutedPaneTarget(connectionID: "local", workspaceID: "w", tabID: "t", paneID: "p1")

        XCTAssertEqual(
            BessieZenAgentRouter.target(
                direction: .next,
                from: current,
                agents: agents,
                connectedConnectionIDs: ["local", "remote"]
            )?.paneID,
            "p3"
        )
        XCTAssertEqual(
            BessieZenAgentRouter.target(
                direction: .previous,
                from: current,
                agents: agents,
                connectedConnectionIDs: ["local", "remote"]
            )?.paneID,
            "p2"
        )
    }

    func testZenNextNeedsYouUsesSharedBlockedPredicateAndConnectedScope() {
        let agents = [
            Self.agent(connectionID: "local", paneID: "working", status: "working"),
            Self.agent(connectionID: "remote", paneID: "stale-blocked", status: "blocked"),
            Self.agent(connectionID: "local", paneID: "blocked", status: "blocked"),
        ]

        let target = BessieZenAgentRouter.nextNeedsYou(
            from: nil,
            agents: agents,
            connectedConnectionIDs: ["local"],
            scope: .all
        )

        XCTAssertEqual(target?.paneID, "blocked")
        XCTAssertTrue(AgentSemanticState.blocked.requiresUserAction)
        XCTAssertFalse(AgentSemanticState.done.requiresUserAction)
    }

    func testZenElsewhereCountExcludesFocusedPaneAndDisconnectedRows() {
        let agents = [
            Self.agent(connectionID: "local", paneID: "focused", status: "blocked"),
            Self.agent(connectionID: "local", paneID: "elsewhere", status: "blocked"),
            Self.agent(connectionID: "local", paneID: "working", status: "working"),
            Self.agent(connectionID: "remote", paneID: "stale", status: "blocked"),
        ]
        let focused = RoutedPaneTarget(connectionID: "local", workspaceID: "w", tabID: "t", paneID: "focused")

        XCTAssertEqual(
            BessieZenAgentRouter.needsYouElsewhereCount(
                focused: focused,
                agents: agents,
                connectedConnectionIDs: ["local"],
                scope: .all
            ),
            1
        )
        XCTAssertEqual(
            BessieZenAgentRouter.needsYouElsewhereCount(
                focused: focused,
                agents: Array(agents.prefix(1)),
                connectedConnectionIDs: ["local"],
                scope: .all
            ),
            0
        )
    }

    func testRemovedModifiedArrowTopologyShortcutsPassThrough() {
        let router = BessieKeyboardShortcutRouter()
        XCTAssertEqual(router.handle(.init(key: .leftArrow, option: true, command: true)), .passthrough)
        XCTAssertEqual(router.handle(.init(key: .rightArrow, option: true, command: true)), .passthrough)
        XCTAssertEqual(router.handle(.init(key: .upArrow, option: true, command: true)), .passthrough)
        XCTAssertEqual(router.handle(.init(key: .downArrow, option: true, command: true, shift: true)), .passthrough)
        XCTAssertEqual(router.handle(.init(key: .rightArrow, control: true, command: true)), .passthrough)
    }

    func testCommandPaletteSearchesTitlesDetailsAndKeywords() {
        let commands = BessieKeyboardShortcutRouter.commands
        XCTAssertEqual(commands.filter { $0.matches("split below") }.map(\.title), ["Split pane down"])
        XCTAssertEqual(commands.filter { $0.matches("needs you") }.map(\.title), ["Open next agent that needs you"])
        XCTAssertTrue(commands.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
        XCTAssertEqual(commands.first(where: { $0.command == .showSettings })?.shortcut, "⌘,")
        XCTAssertEqual(commands.first(where: { $0.command == .splitPane(.right) })?.shortcut, "Ctrl-B v")
        XCTAssertEqual(commands.first(where: { $0.command == .closePane })?.shortcut, "Ctrl-B x")
        XCTAssertEqual(commands.first(where: { $0.command == .projectsPicker })?.shortcut, "⌥⌘P")
        XCTAssertFalse(commands.compactMap(\.shortcut).contains("⌘B"))
    }

    func testDirectionalNavigationUsesProjectedPaneGeometry() throws {
        let projection = try HerdrSessionProjection(snapshot: Self.layoutFixture)
        let layout = try XCTUnwrap(projection.layouts["t1"])
        XCTAssertEqual(BessiePaneNavigation.target(from: "p1", direction: .right, in: layout.root), "p2")
        XCTAssertEqual(BessiePaneNavigation.target(from: "p2", direction: .left, in: layout.root), "p1")
        XCTAssertEqual(BessiePaneNavigation.target(from: "p2", direction: .down, in: layout.root), "p3")
        XCTAssertNil(BessiePaneNavigation.target(from: "p1", direction: .left, in: layout.root))
    }

    private static let layoutFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p1",
        workspaces: [.object([
            "workspace_id": .string("w1"), "number": .number(1), "label": .string("main"),
            "focused": .bool(true), "pane_count": .number(3), "tab_count": .number(1),
            "active_tab_id": .string("t1"), "agent_status": .string("idle"),
        ])],
        tabs: [.object([
            "tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1),
            "label": .string("shell"), "focused": .bool(true), "pane_count": .number(3),
            "agent_status": .string("idle"),
        ])],
        panes: ["p1", "p2", "p3"].enumerated().map { index, id in .object([
            "pane_id": .string(id), "terminal_id": .string("term\(index)"),
            "workspace_id": .string("w1"), "tab_id": .string("t1"),
            "focused": .bool(id == "p1"), "agent_status": .string("idle"), "revision": .number(1),
        ]) },
        layouts: [.object([
            "workspace_id": .string("w1"), "tab_id": .string("t1"), "zoomed": .bool(false),
            "focused_pane_id": .string("p1"),
            "area": .object(["x": .number(0), "y": .number(0), "width": .number(120), "height": .number(80)]),
            "panes": .array([
                .object(["pane_id": .string("p1"), "focused": .bool(true), "rect": .object(["x": .number(0), "y": .number(0), "width": .number(59), "height": .number(80)])]),
                .object(["pane_id": .string("p2"), "focused": .bool(false), "rect": .object(["x": .number(61), "y": .number(0), "width": .number(59), "height": .number(39)])]),
                .object(["pane_id": .string("p3"), "focused": .bool(false), "rect": .object(["x": .number(61), "y": .number(41), "width": .number(59), "height": .number(39)])]),
            ]),
            "splits": .array([
                .object(["id": .string("root"), "direction": .string("right"), "ratio": .number(0.5), "rect": .object(["x": .number(0), "y": .number(0), "width": .number(120), "height": .number(80)])]),
                .object(["id": .string("split_1"), "direction": .string("down"), "ratio": .number(0.5), "rect": .object(["x": .number(61), "y": .number(0), "width": .number(59), "height": .number(80)])]),
            ]),
        ])],
        agents: []
    )

    private static func agent(connectionID: String, paneID: String, status: String) -> ConnectedAgentProjection {
        ConnectedAgentProjection(
            connection: BessieConnectionDefinition(
                id: connectionID,
                name: connectionID,
                kind: connectionID == "local" ? .local : .ssh,
                sshHost: connectionID == "local" ? nil : "example.test",
                session: "bessie"
            ),
            agent: AgentProjection(
                id: paneID,
                terminalID: "terminal-\(paneID)",
                workspaceID: "w",
                tabID: "t",
                focused: false,
                label: nil,
                agent: "codex",
                displayAgent: nil,
                name: paneID,
                title: nil,
                agentStatus: status,
                revision: 1,
                launchPending: false
            )
        )
    }
}
