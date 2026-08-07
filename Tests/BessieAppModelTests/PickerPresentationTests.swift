import XCTest
@testable import BessieApp
@testable import BessieCore

final class PickerPresentationTests: XCTestCase {
    func testHerdPickerPresentsAllLocalAndSSHHealthWithoutTreatingDisconnectedAsLive() throws {
        let remote = try BessieConnectionDefinition(
            id: "remote", name: "CI box", kind: .ssh, sshHost: "ci-box", session: "main"
        ).validated()
        let rows = HerdPickerPresentation.rows(
            connections: [.localBessie, remote],
            health: [
                ConnectionHealth(
                    connection: .localBessie,
                    presentation: .init(title: "Connected", detail: "Fresh snapshot", status: .connected)
                ),
                ConnectionHealth(
                    connection: remote,
                    presentation: .init(title: "Couldn't reconnect", detail: "Work is still running", status: .lost)
                ),
            ],
            selection: .connection(id: "remote")
        )

        XCTAssertEqual(rows.map(\.title), ["All herds", "local", "CI box"])
        XCTAssertEqual(rows.map(\.kind), [.all, .local, .ssh])
        XCTAssertEqual(rows.map(\.isSelected), [false, false, true])
        XCTAssertEqual(rows.map(\.isFresh), [true, true, false])
        XCTAssertEqual(rows.map(\.canRetry), [false, false, true])
    }

    func testHierarchyHerdRowsExcludeAggregateScopeAndKeepUnavailableConnectionsHonest() throws {
        let remote = try BessieConnectionDefinition(
            id: "remote", name: "CI box", kind: .ssh, sshHost: "ci-box", session: "main"
        ).validated()
        let rows = HerdPickerPresentation.hierarchyRows(
            connections: [.localBessie, remote],
            health: [
                ConnectionHealth(
                    connection: .localBessie,
                    presentation: .init(title: "Connected", detail: "Fresh snapshot", status: .connected)
                ),
                ConnectionHealth(
                    connection: remote,
                    presentation: .init(title: "Couldn't reconnect", detail: "Work is still running", status: .lost)
                ),
            ],
            selectedConnectionID: "local-bessie"
        )

        XCTAssertEqual(rows.map(\.title), ["local", "CI box"])
        XCTAssertEqual(rows.map(\.isSelected), [true, false])
        XCTAssertEqual(rows.map(\.isFresh), [true, false])
        XCTAssertEqual(rows.map(\.canRetry), [false, true])
        XCTAssertFalse(rows.contains { $0.scope == .all })
    }

    func testHerdPickerExcludesDisabledConnections() throws {
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        let remote = try BessieConnectionDefinition(
            id: "remote", name: "CI box", kind: .ssh, sshHost: "ci-box", session: "main"
        ).validated()

        let rows = HerdPickerPresentation.rows(
            connections: [local, remote],
            health: [],
            selection: .connection(id: remote.id)
        )

        XCTAssertEqual(rows.map(\.id), ["all", remote.id])
        XCTAssertFalse(rows.contains { $0.id == local.id })
    }

    func testBindingPickersAreCompactArrowlessPanelContracts() {
        XCTAssertEqual(HerdPickerPresentation.panelCornerRadius, 4)
        XCTAssertEqual(HerdPickerPresentation.rowHeight, 31)
        XCTAssertEqual(HerdPickerPresentation.panelHeight(rowCount: 3), 145)
        XCTAssertEqual(HerdPickerPresentation.captureRows.map(\.title), ["All herds", "local", "ci-box"])
        XCTAssertEqual(WorkspacePickerPresentation.defaultLabel, "All workspaces")
        XCTAssertEqual(WorkspacePickerPresentation.panelCornerRadius, 4)
        XCTAssertEqual(WorkspacePickerPresentation.rowHeight, 31)
        XCTAssertEqual(WorkspacePickerPresentation.panelHeight(rowCount: 2), 145)
    }

    func testWorkspacePickerUsesOnlyFreshAuthoritativeWorkspacesInSelectedScope() throws {
        let local = ConnectionTopologyProjection(
            connection: .localBessie,
            projection: try HerdrSessionProjection(snapshot: .pickerLocalFixture)
        )
        let remoteConnection = try BessieConnectionDefinition(
            id: "remote", name: "CI box", kind: .ssh, sshHost: "ci-box", session: "main"
        ).validated()
        let remote = ConnectionTopologyProjection(
            connection: remoteConnection,
            projection: try HerdrSessionProjection(snapshot: .pickerRemoteFixture)
        )

        let rows = WorkspacePickerPresentation.rows(
            topology: ScopedTopologyProjection(connections: [local, remote], scope: .connection(id: "remote")),
            selectedConnectionID: "remote",
            selectedWorkspaceID: "remote-workspace"
        )

        XCTAssertEqual(rows.map(\.id.connectionID), ["remote"])
        XCTAssertEqual(rows.map(\.title), ["remote"])
        XCTAssertEqual(rows.map(\.isSelected), [true])
    }

    func testWorkspacePickerCreationUsesOrdinaryHerdrWorkspaceAction() {
        XCTAssertEqual(
            WorkspacePickerPresentation.creationAction,
            .workspaceCreate(cwd: nil, label: nil, focus: true)
        )
    }

    func testHierarchyTabRowsUseProjectionOrderSelectedPaneFallbackAndAuthoritativeCount() throws {
        let projection = try HerdrSessionProjection(snapshot: .hierarchyTabsFixture)
        let presentation = WorkspaceHierarchyPresentation(
            connectionLabel: "local",
            projection: projection,
            selectedWorkspaceID: "workspace",
            selectedPaneID: "pane-b"
        )

        XCTAssertEqual(presentation.workspaceLabel, "workspace")
        XCTAssertEqual(presentation.tabLabel, "tests")
        XCTAssertEqual(presentation.paneCount, 1)
        XCTAssertEqual(presentation.tabs.map(\.title), ["dev", "tests"])
        XCTAssertEqual(presentation.tabs.map(\.paneCount), [2, 1])
        XCTAssertEqual(presentation.tabs.map(\.isSelected), [false, true])
    }

    func testHierarchyPresentationKeepsChromeOutOfTheWorkspaceCard() {
        XCTAssertEqual(WorkspaceHierarchyPresentation.inCardChromeHeight, 0)
        XCTAssertEqual(BessieDesign.controlRadius, BessieDesign.paneRadius)
    }

    func testHierarchyAllOptionsSelectWorkspaceScopesInPlace() {
        XCTAssertEqual(WorkspaceHierarchySection.herd.allTitle, "All Herds")
        XCTAssertEqual(WorkspaceHierarchySection.workspace.allTitle, "All Workspaces")
        XCTAssertEqual(WorkspaceHierarchySection.tab.allTitle, "All Tabs")
        XCTAssertNil(WorkspaceHierarchySection.herd.allIcon)
        XCTAssertNil(WorkspaceHierarchySection.workspace.allIcon)
        XCTAssertNil(WorkspaceHierarchySection.tab.allIcon)
        XCTAssertEqual(WorkspaceScopeReducer.selectingAll(.herd, connectionID: "c", workspaceID: "w"), .allHerds)
        XCTAssertEqual(WorkspaceScopeReducer.selectingAll(.workspace, connectionID: "c", workspaceID: "w"), .allWorkspaces(connectionID: "c"))
        XCTAssertEqual(WorkspaceScopeReducer.selectingAll(.tab, connectionID: "c", workspaceID: "w"), .allTabs(connectionID: "c", workspaceID: "w"))
        XCTAssertFalse(ProductDestination.visible(flags: .v1).contains(.workspaces))
        XCTAssertFalse(ProductDestination.visible(flags: .v1).contains(.tabs))
    }

    func testSidebarPaneSelectionPreservesTheCurrentHierarchyFilters() {
        let target = RoutedPaneTarget(
            connectionID: "other-herd",
            workspaceID: "other-workspace",
            tabID: "other-tab",
            paneID: "pane"
        )
        let scopes: [WorkspaceScope] = [
            .selectedTab(connectionID: "herd", workspaceID: "workspace", tabID: "tab"),
            .allTabs(connectionID: "herd", workspaceID: "workspace"),
            .allWorkspaces(connectionID: "herd"),
            .allHerds,
        ]

        for scope in scopes {
            XCTAssertEqual(
                WorkspaceScopeReducer.selectingSidebarPane(target, preserving: scope),
                scope
            )
        }
        XCTAssertEqual(
            WorkspaceScopeReducer.selectingSidebarPane(target, preserving: nil),
            .selectedTab(
                connectionID: target.connectionID,
                workspaceID: target.workspaceID,
                tabID: target.tabID
            )
        )
    }

    func testGlobalHierarchyPresentationShowsAggregateLabelsAndPaneCount() throws {
        let presentation = WorkspaceHierarchyPresentation(
            connectionLabel: "local",
            projection: try HerdrSessionProjection(snapshot: .hierarchyTabsFixture),
            selectedWorkspaceID: "workspace",
            selectedPaneID: "pane-b",
            globalSection: .tab,
            globalPaneCount: 9
        )

        XCTAssertEqual(presentation.connectionLabel, "local")
        XCTAssertEqual(presentation.workspaceLabel, "workspace")
        XCTAssertEqual(presentation.tabLabel, "All Tabs")
        XCTAssertEqual(presentation.paneCount, 9)
        XCTAssertEqual(presentation.globalSection, .tab)
    }

    func testHierarchyMutationsShareOneAvailabilityGate() {
        XCTAssertTrue(WorkspaceHierarchyActionAvailability.canMutate(false))
        XCTAssertFalse(WorkspaceHierarchyActionAvailability.canMutate(true))
    }

    func testProjectCaptureWaitsForNavigationAndMutationToSettle() {
        XCTAssertTrue(WorkspaceProjectCaptureGate.isSettled(actionInFlight: false, navigationInFlight: false))
        XCTAssertFalse(WorkspaceProjectCaptureGate.isSettled(actionInFlight: true, navigationInFlight: false))
        XCTAssertFalse(WorkspaceProjectCaptureGate.isSettled(actionInFlight: false, navigationInFlight: true))
        XCTAssertFalse(WorkspaceProjectCaptureGate.isSettled(actionInFlight: true, navigationInFlight: true))
    }
}

private extension HerdrSnapshot {
    static let pickerLocalFixture = pickerFixture(
        workspaceID: "local-workspace", tabID: "local-tab", paneID: "local-pane", label: "local"
    )
    static let pickerRemoteFixture = pickerFixture(
        workspaceID: "remote-workspace", tabID: "remote-tab", paneID: "remote-pane", label: "remote"
    )
    static let hierarchyTabsFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "workspace", focusedTabID: "tab-a", focusedPaneID: "pane-a",
        workspaces: [.object([
            "workspace_id": .string("workspace"), "number": .number(1), "label": .string("workspace"),
            "focused": .bool(true), "pane_count": .number(3), "tab_count": .number(2),
            "active_tab_id": .string("tab-a"), "agent_status": .string("blocked"),
        ])],
        tabs: [
            .object([
                "tab_id": .string("tab-a"), "workspace_id": .string("workspace"), "number": .number(1),
                "label": .string("dev"), "focused": .bool(true), "pane_count": .number(2),
                "agent_status": .string("blocked"),
            ]),
            .object([
                "tab_id": .string("tab-b"), "workspace_id": .string("workspace"), "number": .number(2),
                "label": .string("tests"), "focused": .bool(false), "pane_count": .number(1),
                "agent_status": .string("working"),
            ]),
        ],
        panes: [
            .object([
                "pane_id": .string("pane-a"), "terminal_id": .string("terminal-a"),
                "workspace_id": .string("workspace"), "tab_id": .string("tab-a"),
                "focused": .bool(true), "agent_status": .string("blocked"), "revision": .number(1),
            ]),
            .object([
                "pane_id": .string("pane-a2"), "terminal_id": .string("terminal-a2"),
                "workspace_id": .string("workspace"), "tab_id": .string("tab-a"),
                "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1),
            ]),
            .object([
                "pane_id": .string("pane-b"), "terminal_id": .string("terminal-b"),
                "workspace_id": .string("workspace"), "tab_id": .string("tab-b"),
                "focused": .bool(false), "agent_status": .string("working"), "revision": .number(1),
            ]),
        ],
        layouts: [], agents: []
    )

    static func pickerFixture(workspaceID: String, tabID: String, paneID: String, label: String) -> HerdrSnapshot {
        HerdrSnapshot(
            version: "0.8.0", protocolVersion: 19,
            focusedWorkspaceID: workspaceID, focusedTabID: tabID, focusedPaneID: paneID,
            workspaces: [.object([
                "workspace_id": .string(workspaceID), "number": .number(1), "label": .string(label),
                "focused": .bool(true), "pane_count": .number(1), "tab_count": .number(1),
                "active_tab_id": .string(tabID), "agent_status": .string("idle"),
            ])],
            tabs: [.object([
                "tab_id": .string(tabID), "workspace_id": .string(workspaceID), "number": .number(1),
                "label": .string(label), "focused": .bool(true), "pane_count": .number(1), "agent_status": .string("idle"),
            ])],
            panes: [.object([
                "pane_id": .string(paneID), "terminal_id": .string("terminal-\(paneID)"),
                "workspace_id": .string(workspaceID), "tab_id": .string(tabID),
                "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1),
            ])],
            layouts: [], agents: []
        )
    }
}
