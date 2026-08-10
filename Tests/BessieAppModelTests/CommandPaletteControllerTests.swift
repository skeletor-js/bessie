import BessieCore
import XCTest
@testable import BessieApp

@MainActor
final class CommandPaletteControllerTests: XCTestCase {
    func testBrowseUsesCuratedSectionsAndQueryUsesCompleteIndex() {
        let model = BessieCommandPaletteModel()
        model.open(input: input(panes: [
            pane("blocked", title: "Compiler", state: .blocked),
            pane("working", title: "Preview", state: .working),
        ]))

        XCTAssertEqual(model.sections.map(\.kind), [.needsYou, .workspaces, .herds, .commands])
        XCTAssertEqual(model.results.first?.id, paneID("blocked"))
        XCTAssertFalse(model.results.contains(where: { $0.id == paneID("working") }))

        model.query = "preview"
        model.queryDidChange()

        XCTAssertEqual(model.results.map(\.id), [paneID("working")])
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testSelectionPreservesStableIdentityAcrossQueryAndRebuild() {
        let model = BessieCommandPaletteModel()
        model.open(input: input(panes: [
            pane("alpha", title: "Alpine tools", state: .blocked),
            pane("beta", title: "Alpha preview", state: .blocked),
        ]), initialQuery: "al")
        model.selection = 1
        let selectedID = model.selectedEntity?.id

        model.query = "alp"
        model.queryDidChange()
        model.rebuild(input: input(panes: [
            pane("beta", title: "Alpha preview", state: .blocked, workspaceID: "moved"),
            pane("alpha", title: "Alpine tools", state: .blocked),
        ]))

        XCTAssertEqual(model.selectedEntity?.id, selectedID)
        XCTAssertEqual(model.selectedEntity?.route, .pane(
            connectionID: "local", workspaceID: "moved", tabID: "tab", paneID: "beta"
        ))
    }

    func testLiveStateChangeResectionsPaneWithoutReopening() {
        let model = BessieCommandPaletteModel()
        model.open(input: input(panes: [pane("alpha", title: "Alpha", state: .working)]))
        XCTAssertNil(model.sections.first(where: { $0.kind == .needsYou }))

        model.rebuild(input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]))

        XCTAssertTrue(model.isOpen)
        XCTAssertEqual(
            model.sections.first(where: { $0.kind == .needsYou })?.entities.map(\.id),
            [paneID("alpha")]
        )
        XCTAssertEqual(model.results.first?.semanticState, .blocked)
    }

    func testPrintableInputBuffersUntilTheSearchFieldActuallyOwnsFocus() {
        let model = BessieCommandPaletteModel()
        model.open(input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]))

        model.bufferPrintableCharacters("al")
        XCTAssertEqual(model.query, "al")
        XCTAssertEqual(model.results.filter { $0.kind == .pane }.map(\.id), [paneID("alpha")])

        model.markSearchMounted()
        model.bufferPrintableCharacters("p")
        XCTAssertEqual(model.query, "alp")
    }

    func testDuplicateBrowseEntityIDsKeepDistinctRowIdentityAndExactSelection() throws {
        let model = BessieCommandPaletteModel()
        let workspaceID = CommandPaletteEntityID(
            kind: .workspace,
            components: ["local", "workspace"]
        )
        model.open(input: input(
            panes: [],
            mru: CommandPaletteMRU(ids: [workspaceID])
        ))

        let recentWorkspace = try XCTUnwrap(
            model.sections.first(where: { $0.kind == .recent })?.entities.first
        )
        let completeWorkspace = try XCTUnwrap(
            model.sections.first(where: { $0.kind == .workspaces })?.entities.first
        )
        let recentRowID = model.rowID(for: recentWorkspace, section: .recent)
        let completeRowID = model.rowID(for: completeWorkspace, section: .workspaces)
        let completeIndex = try XCTUnwrap(
            model.resultIndex(for: completeWorkspace, section: .workspaces)
        )

        XCTAssertEqual(recentWorkspace.id, completeWorkspace.id)
        XCTAssertNotEqual(recentRowID, completeRowID)
        model.selection = completeIndex
        XCTAssertFalse(model.isSelected(recentWorkspace, section: .recent))
        XCTAssertTrue(model.isSelected(completeWorkspace, section: .workspaces))
        XCTAssertEqual(model.selectedScrollID, completeRowID)
    }

    func testActivationDispatchesExactlyOnceAndRecordsMRUOnlyAfterSuccess() {
        let model = BessieCommandPaletteModel()
        var dispatched: [CommandPaletteRouteIntent] = []
        var recorded: [CommandPaletteEntityID] = []
        var dismissals: [Bool] = []
        model.configure(
            onDispatch: { dispatched.append($0); return true },
            onSuccessfulDispatch: { recorded.append($0) },
            onDismiss: { dismissals.append($0) }
        )
        model.open(input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]), initialQuery: "alpha")

        model.activate(alternate: false)
        model.activate(alternate: false)

        XCTAssertEqual(dispatched, [.pane(connectionID: "local", workspaceID: "workspace", tabID: "tab", paneID: "alpha")])
        XCTAssertEqual(recorded, [paneID("alpha")])
        XCTAssertEqual(dismissals, [false])
        XCTAssertFalse(model.isOpen)

        model.open(
            input: input(
                panes: [pane("alpha", title: "Alpha", state: .working)],
                mru: CommandPaletteMRU(ids: recorded)
            )
        )
        XCTAssertEqual(
            model.sections.first(where: { $0.kind == .recent })?.entities.map(\.id),
            [paneID("alpha")]
        )
    }

    func testEnterOnProjectResultDispatchesDirectProjectRoute() {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let model = BessieCommandPaletteModel()
        var dispatched: [CommandPaletteRouteIntent] = []
        model.configure(
            onDispatch: { dispatched.append($0); return true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )

        model.open(
            input: input(
                panes: [],
                projects: [
                    .init(
                        id: projectID,
                        title: "Launchable project",
                        detail: "Project · 1 pane",
                        isRunning: false
                    ),
                ]
            ),
            initialQuery: "Launchable project"
        )
        model.activate(alternate: false)

        XCTAssertEqual(dispatched, [.project(projectID)])
    }

    func testClickOnProjectResultDispatchesDirectProjectRoute() throws {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let model = BessieCommandPaletteModel()
        var dispatched: [CommandPaletteRouteIntent] = []
        model.configure(
            onDispatch: { dispatched.append($0); return true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )
        model.open(
            input: input(
                panes: [],
                projects: [
                    .init(
                        id: projectID,
                        title: "Launchable project",
                        detail: "Project · 1 pane",
                        isRunning: false
                    ),
                ]
            ),
            initialQuery: "Launchable project"
        )

        model.activate(entity: try XCTUnwrap(model.results.first), alternate: false)

        XCTAssertEqual(dispatched, [.project(projectID)])
    }

    func testProjectManagementCommandsRemainSeparateFromProjectRoutes() {
        let model = BessieCommandPaletteModel()
        var dispatched: [CommandPaletteRouteIntent] = []
        model.configure(
            onDispatch: { dispatched.append($0); return true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )

        model.open(input: input(panes: []), initialQuery: "Manage projects")
        model.activate(alternate: false)
        model.open(input: input(panes: []), initialQuery: "Create project")
        model.activate(alternate: false)

        XCTAssertEqual(dispatched, [
            .command(.projectsPicker),
            .command(.newProject),
        ])
    }

    func testKeyboardReferenceCommandDispatchesTheTypedAction() {
        let model = BessieCommandPaletteModel()
        var dispatched: [CommandPaletteRouteIntent] = []
        model.configure(
            onDispatch: { dispatched.append($0); return true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )

        model.open(input: input(panes: []), initialQuery: "Keyboard reference")
        model.activate(alternate: false)

        XCTAssertEqual(dispatched, [.command(.showKeyboardReference)])
    }

    func testFailedDispatchRestoresOriginAndDoesNotRecordMRU() {
        let model = BessieCommandPaletteModel()
        var recorded: [CommandPaletteEntityID] = []
        var dismissals: [Bool] = []
        model.configure(
            onDispatch: { _ in false },
            onSuccessfulDispatch: { recorded.append($0) },
            onDismiss: { dismissals.append($0) }
        )
        model.open(
            input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]),
            initialQuery: "alpha"
        )

        model.activate(alternate: false)

        XCTAssertTrue(recorded.isEmpty)
        XCTAssertEqual(dismissals, [true])
        XCTAssertFalse(model.isOpen)
    }

    func testIndexDoesNotRebuildOutsideOpenLifecycle() {
        let model = BessieCommandPaletteModel()
        let firstInput = input(panes: [pane("alpha", title: "Alpha", state: .blocked)])
        let secondInput = input(panes: [pane("beta", title: "Beta", state: .blocked)])

        model.rebuild(input: firstInput)
        XCTAssertTrue(model.index.allEntities.isEmpty)

        model.open(input: firstInput)
        model.dismiss()
        model.rebuild(input: secondInput)

        XCTAssertNotNil(model.index.entity(id: paneID("alpha")))
        XCTAssertNil(model.index.entity(id: paneID("beta")))
    }

    func testMovedPaneClickResolvesStableIdentityToCurrentRoute() {
        let model = BessieCommandPaletteModel()
        var dispatched: [CommandPaletteRouteIntent] = []
        model.configure(
            onDispatch: { dispatched.append($0); return true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )
        model.open(input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]), initialQuery: "alpha")
        let staleRow = model.results[0]
        model.rebuild(input: input(panes: [
            pane("alpha", title: "Alpha", state: .blocked, workspaceID: "moved")
        ]))

        model.activate(entity: staleRow, alternate: false)

        XCTAssertEqual(dispatched, [
            .pane(connectionID: "local", workspaceID: "moved", tabID: "tab", paneID: "alpha"),
        ])
    }

    func testMissingPaneWaitsForExistingSnapshotRefreshThenDispatchesRecoveredTarget() {
        let model = BessieCommandPaletteModel()
        var dispatched: [CommandPaletteRouteIntent] = []
        model.configure(
            onDispatch: { dispatched.append($0); return true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )
        model.open(input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]), initialQuery: "alpha")
        let staleRow = model.results[0]
        model.rebuild(input: input(panes: []))

        model.activate(entity: staleRow, alternate: false)
        model.activate(entity: staleRow, alternate: false)
        XCTAssertEqual(model.recoveryNotice, .waiting)
        XCTAssertTrue(dispatched.isEmpty)

        model.rebuild(input: input(panes: [
            pane("alpha", title: "Alpha", state: .blocked, workspaceID: "fresh")
        ]))
        XCTAssertEqual(dispatched, [
            .pane(connectionID: "local", workspaceID: "fresh", tabID: "tab", paneID: "alpha"),
        ])
    }

    func testDisconnectedHerdRejectsStalePaneWithoutDispatchOrRedirect() {
        let model = BessieCommandPaletteModel()
        var dispatched: [CommandPaletteRouteIntent] = []
        model.configure(
            onDispatch: { dispatched.append($0); return true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )
        model.open(input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]), initialQuery: "alpha")
        let staleRow = model.results[0]
        model.rebuild(input: input(panes: [], freshness: .disconnected))

        model.activate(entity: staleRow, alternate: false)

        XCTAssertTrue(dispatched.isEmpty)
        XCTAssertTrue(model.isOpen)
        guard case .failed(let message) = model.recoveryNotice else {
            return XCTFail("Expected a visible disconnected-target failure")
        }
        XCTAssertTrue(message.contains("disconnected"))
    }

    func testQueryChangeCancelsPendingRecovery() {
        let model = BessieCommandPaletteModel()
        model.configure(
            onDispatch: { _ in true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )
        model.open(input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]), initialQuery: "alpha")
        let staleRow = model.results[0]
        model.rebuild(input: input(panes: []))
        model.activate(entity: staleRow, alternate: false)
        XCTAssertEqual(model.recoveryNotice, .waiting)

        model.query = "different"
        model.queryDidChange()

        XCTAssertNil(model.recoveryNotice)
        XCTAssertTrue(model.isOpen)
    }

    func testMissingPaneRecoveryTimesOutToInlineFailureWithQueryPreserved() async {
        let model = BessieCommandPaletteModel(recoveryDelayNanoseconds: 10_000_000)
        model.configure(
            onDispatch: { _ in true },
            onSuccessfulDispatch: { _ in },
            onDismiss: { _ in }
        )
        model.open(input: input(panes: [pane("alpha", title: "Alpha", state: .blocked)]), initialQuery: "alpha")
        let staleRow = model.results[0]
        model.rebuild(input: input(panes: []))
        model.activate(entity: staleRow, alternate: false)

        try? await Task.sleep(nanoseconds: 50_000_000)

        guard case .failed(let message) = model.recoveryNotice else {
            return XCTFail("Expected bounded recovery to fail visibly")
        }
        XCTAssertTrue(message.contains("no longer available"))
        XCTAssertEqual(model.query, "alpha")
        XCTAssertTrue(model.isOpen)
    }

    private func input(
        panes: [CommandPalettePaneInput],
        freshness: CommandPaletteFreshness = .fresh,
        projects: [CommandPaletteProjectInput] = [],
        mru: CommandPaletteMRU = .init()
    ) -> CommandPaletteIndexInput {
        .init(
            connections: [
                .init(
                    connection: .init(id: "local", name: "Local", kind: .local),
                    freshness: freshness,
                    healthDetail: freshness == .fresh ? "Connected" : "Disconnected",
                    panes: panes,
                    workspaces: freshness == .fresh ? [
                        .init(
                            id: "workspace", number: 1, title: "Bessie", tabCount: 1,
                            paneCount: panes.count, semanticState: .working
                        ),
                    ] : []
                ),
            ],
            projects: projects,
            commands: BessieKeyboardShortcutRouter.commands,
            context: .init(
                activeConnectionID: "local",
                scope: .all,
                focusedWorkspaceID: "workspace",
                focusedPaneID: nil,
                mru: mru
            )
        )
    }

    private func pane(
        _ id: String,
        title: String,
        state: AgentSemanticState,
        workspaceID: String = "workspace"
    ) -> CommandPalettePaneInput {
        .init(
            id: id,
            workspaceID: workspaceID,
            workspaceTitle: "Bessie",
            tabID: "tab",
            tabTitle: "Main",
            title: title,
            detail: "Agent pane",
            semanticState: state,
            provider: "codex",
            keywords: ["codex"]
        )
    }

    private func paneID(_ id: String) -> CommandPaletteEntityID {
        .init(kind: .pane, components: ["local", id])
    }
}
