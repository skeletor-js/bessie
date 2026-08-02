import XCTest
@testable import BessieCore

final class KeyboardShortcutTests: XCTestCase {
    func testNonCommandInputAlwaysPassesThroughToTerminal() {
        let router = BessieKeyboardShortcutRouter()
        XCTAssertEqual(router.handle(.init(key: .character("b"), control: true)), .passthrough)
        XCTAssertEqual(router.handle(.init(key: .character("d"))), .passthrough)
        XCTAssertEqual(router.handle(.init(key: .leftArrow, option: true)), .passthrough)
    }

    func testSystemCommandShortcutsPassThroughToAppKit() {
        let systemKeys = ["q", "H", "m"]
        for key in systemKeys {
            XCTAssertEqual(
                BessieKeyboardShortcutRouter.policy(for: .init(key: .character(key), command: true)),
                .passthrough,
                "Command-\(key.uppercased()) must remain owned by AppKit"
            )
        }
    }

    func testCommandBOpensCommandPalette() {
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("b"), command: true)),
            .appCommand(.showCommandPalette)
        )
    }

    func testNativeWorkspaceTabAndPaneShortcuts() {
        let cases: [(BessieShortcutStroke, BessieShortcutCommand)] = [
            (.init(key: .character("n"), command: true), .newWorkspace),
            (.init(key: .character("t"), command: true), .newTab),
            (.init(key: .character("3"), command: true), .switchTab(3)),
            (.init(key: .character("["), command: true), .previousTab),
            (.init(key: .character("]"), command: true), .nextTab),
            (.init(key: .character("d"), command: true), .splitPane(.right)),
            (.init(key: .character("D"), command: true, shift: true), .splitPane(.down)),
            (.init(key: .character("b"), command: true, shift: true), .toggleSidebar),
            (.init(key: .character(","), command: true), .showSettings),
            (.init(key: .character("n"), option: true, command: true), .openNotificationTarget),
        ]
        let router = BessieKeyboardShortcutRouter()
        for (stroke, command) in cases {
            XCTAssertEqual(router.handle(stroke), .command(command))
        }
        XCTAssertEqual(
            BessieKeyboardShortcutRouter.policy(for: .init(key: .character("w"), command: true)),
            .appCommand(.closeTab)
        )
    }

    func testModifiedArrowShortcutsFocusSwapAndResizePanes() {
        let router = BessieKeyboardShortcutRouter()
        XCTAssertEqual(router.handle(.init(key: .leftArrow, option: true, command: true)), .command(.focusPane(.left)))
        XCTAssertEqual(router.handle(.init(key: .downArrow, option: true, command: true, shift: true)), .command(.swapPane(.down)))
        XCTAssertEqual(router.handle(.init(key: .rightArrow, control: true, command: true)), .command(.resizePane(.right)))
    }

    func testCommandPaletteSearchesTitlesDetailsAndKeywords() {
        let commands = BessieKeyboardShortcutRouter.commands
        XCTAssertEqual(commands.filter { $0.matches("split below") }.map(\.title), ["Split pane down"])
        XCTAssertEqual(commands.filter { $0.matches("notification") }.map(\.title), ["Open next attention item"])
        XCTAssertTrue(commands.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
        XCTAssertEqual(commands.first(where: { $0.command == .showSettings })?.shortcut, "⌘,")
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
        version: "0.7.5", protocolVersion: 17,
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
}
