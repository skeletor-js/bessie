import XCTest
@testable import BessieApp
@testable import BessieCore

final class IntentActionDispatcherTests: XCTestCase {
    @MainActor
    func testConnectionModelSurfacesObsoleteGenerationMutationUncertainty() async throws {
        let connection = BessieConnectionDefinition.localBessie
        let live = AppIntentLivePort()
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let dispatcher = BessieIntentActionDispatcher(
            live: live,
            projects: BessieProjectStore(
                rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
        )
        let model = ConnectionViewModel(intentDispatcher: dispatcher)
        let oldProjection = try HerdrSessionProjection(snapshot: .prefixDispatchFixture)
        let replacementProjection = try HerdrSessionProjection(snapshot: .prefixReplacementFixture)
        let mutationStarted = DispatchSemaphore(value: 0)
        let releaseMutation = DispatchSemaphore(value: 0)
        let oldAPI = BlockingDispatchMutationAPI(
            snapshot: .prefixDispatchFixture,
            mutationStarted: mutationStarted,
            releaseMutation: releaseMutation,
            mutationOutcome: .failure(.init(
                disposition: .mutationOutcomeUnknown,
                underlying: HerdrClientError.connectionClosed
            ))
        )
        model.installHerdrActionClient(
            HerdrActionClient(api: oldAPI),
            projection: oldProjection
        )
        let oldGeneration = try XCTUnwrap(model.herdrConnectionGeneration)
        var completionCalled = false
        var failureCalled = false

        model.dispatchHerdrDefault(.splitPane(.right)) { _ in
            completionCalled = true
        } failure: {
            failureCalled = true
        }
        let started = await Task.detached {
            waitForDispatchSemaphore(mutationStarted)
        }.value
        XCTAssertTrue(started)
        model.installHerdrActionClient(
            HerdrActionClient(api: RecordingDispatchMutationAPI(snapshot: .prefixReplacementFixture)),
            projection: replacementProjection
        )
        let replacementGeneration = try XCTUnwrap(model.herdrConnectionGeneration)
        releaseMutation.signal()

        for _ in 0..<100 where model.actionError == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotEqual(oldGeneration, replacementGeneration)
        XCTAssertEqual(
            model.actionError,
            "Herdr may have applied a command on the previous connection, but Bessie could not confirm the result. The command was not retried."
        )
        XCTAssertEqual(model.projection, replacementProjection)
        XCTAssertFalse(model.actionInFlight)
        XCTAssertFalse(completionCalled)
        XCTAssertFalse(failureCalled)
        XCTAssertEqual(oldAPI.mutationMethods, ["pane.split"])
    }

    func testHerdrDefaultResolverUsesFreshFocusedTargetsAndExactPublicActions() throws {
        let projection = try HerdrSessionProjection(snapshot: .prefixDispatchFixture)

        XCTAssertEqual(
            try HerdrDefaultTopologyResolver.resolve(.beginResize, in: projection),
            .noOp
        )
        XCTAssertEqual(
            try HerdrDefaultTopologyResolver.resolve(.splitPane(.right), in: projection),
            .actions([.paneSplit(
                targetPaneID: "p2",
                direction: .right,
                ratio: nil,
                cwd: nil,
                focus: true
            )])
        )
        XCTAssertEqual(
            try HerdrDefaultTopologyResolver.resolve(
                .splitPaneTarget(id: "p1", direction: .down),
                in: projection
            ),
            .actions([.paneSplit(
                targetPaneID: "p1",
                direction: .down,
                ratio: nil,
                cwd: nil,
                focus: true
            )])
        )
        XCTAssertEqual(
            try HerdrDefaultTopologyResolver.resolve(.focusPane(.left), in: projection),
            .actions([.paneFocusDirection(sourcePaneID: "p2", direction: .left)])
        )
        XCTAssertEqual(
            try HerdrDefaultTopologyResolver.resolve(.focusTab(1), in: projection),
            .actions([.tabFocus(id: "t1")])
        )
        XCTAssertEqual(
            try HerdrDefaultTopologyResolver.resolve(.focusTab(9), in: projection),
            .noOp
        )
    }

    func testPaletteDirectionalFocusDefersStaleGeometryToFreshResolver() async throws {
        let freshProjection = try HerdrSessionProjection(snapshot: .prefixDispatchFixture)
        let paletteContext = BessiePaletteTopologyContext(
            workspace: freshProjection.focusedWorkspace,
            tab: freshProjection.focusedTab,
            paneID: nil,
            projection: freshProjection
        )
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "c1", name: "Test", kind: .ssh, sshHost: "test")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let api = RecordingDispatchMutationAPI(snapshot: .prefixDispatchFixture)
        live.connect(
            client: HerdrActionClient(api: api),
            connectionID: connection.id,
            projection: nil
        )

        XCTAssertNil(paletteContext.failure(for: .focusPane(.left)))
        let result = await live.dispatchHerdrDefault(.focusPane(.left), connectionID: connection.id)

        guard case .applied = result else {
            return XCTFail("Directional palette focus should reach the fresh shared resolver")
        }
        XCTAssertEqual(api.mutationMethods, ["pane.focus_direction"])
        XCTAssertEqual(freshProjection.focusedPane?.id, "p2")
    }

    func testHerdrDefaultResolverValidatesCapturedModalTargetWithoutRetargeting() throws {
        let projection = try HerdrSessionProjection(snapshot: .prefixDispatchFixture)

        XCTAssertEqual(
            try HerdrDefaultTopologyResolver.resolve(.closePane(id: "p1"), in: projection),
            .actions([.paneClose(id: "p1")])
        )
        XCTAssertThrowsError(
            try HerdrDefaultTopologyResolver.resolve(.closePane(id: "deleted"), in: projection)
        )
    }

    func testRegisteredPilotActionsMapToIntentRequests() {
        XCTAssertEqual(
            BessiePilotIntentMapping.request(for: .paneFocus(id: "p1"), connectionID: "c1")?.intent,
            BessieIntentID("pane.focus")
        )
        XCTAssertEqual(
            BessiePilotIntentMapping.request(for: .workspaceFocus(id: "w1"), connectionID: "c1")?.params,
            ["connection_id": .string("c1"), "workspace_id": .string("w1")]
        )
        XCTAssertEqual(
            BessiePilotIntentMapping.request(for: .workspaceClose(id: "w1"), connectionID: "c1")?.intent,
            BessieIntentID("workspace.close")
        )
    }

    func testNonPilotActionsAreNotIntercepted() {
        XCTAssertNil(BessiePilotIntentMapping.request(for: .tabFocus(id: "t1"), connectionID: "c1"))
        XCTAssertNil(BessiePilotIntentMapping.request(
            for: .paneSplit(targetPaneID: "p1", direction: .right, ratio: 0.5, cwd: nil, focus: true),
            connectionID: "c1"
        ))
    }

    func testSharedLivePortRoutesConnectionStatusByExplicitID() {
        let live = AppIntentLivePort()
        let clientA = HerdrActionClient(api: HerdrSocketAPI(socketPath: "/tmp/herdr-a.sock"))
        let clientB = HerdrActionClient(api: HerdrSocketAPI(socketPath: "/tmp/herdr-b.sock"))
        live.update(client: clientA, connectionID: "connection-a", projection: nil)
        live.update(client: clientB, connectionID: "connection-b", projection: nil)
        let dispatcher = BessieIntentActionDispatcher(live: live, projects: BessieProjectStore(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ))

        let second = dispatcher.execute(BessieIntentRequest(
            id: "second", intent: "connection.status", params: ["connection_id": .string("connection-b")]
        ))
        let missing = dispatcher.execute(BessieIntentRequest(
            id: "missing", intent: "connection.status", params: ["connection_id": .string("connection-c")]
        ))

        XCTAssertEqual(second.value?["connected"], .bool(true))
        XCTAssertEqual(missing.value?["connected"], .bool(false))
    }

    func testSharedLivePortExposesConfiguredDisabledAndDisconnectedContext() throws {
        let live = AppIntentLivePort()
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        let remote = BessieConnectionDefinition(
            id: "hermes-vps",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes"
        )
        live.updateConnectionContext(
            connections: [local, remote],
            selectedConnectionID: remote.id,
            defaultProjectConnectionID: remote.id
        )
        let dispatcher = BessieIntentActionDispatcher(
            live: live,
            projects: BessieProjectStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        )

        let result = dispatcher.execute(BessieIntentRequest(
            id: "context", intent: "connection.context", params: [:]
        ))
        let contexts = try result.value?.decode([BessieIntentConnectionContext].self)

        XCTAssertEqual(contexts?.map(\.id), [local.id, remote.id])
        XCTAssertEqual(contexts?.first?.enabled, false)
        XCTAssertEqual(contexts?.last?.selected, true)
        XCTAssertEqual(contexts?.last?.defaultProjectTarget, true)
        XCTAssertEqual(contexts?.last?.connected, false)
        XCTAssertEqual(contexts?.last?.sshHost, "hermes")
    }

    func testDisablingConfiguredConnectionInvalidatesRetainedLiveActionStateSynchronously() throws {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "remote", name: "Remote", kind: .ssh, sshHost: "hermes")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        live.update(
            client: HerdrActionClient(api: HerdrSocketAPI(socketPath: "/tmp/herdr-disabled-test.sock")),
            connectionID: connection.id,
            projection: nil
        )
        XCTAssertTrue(live.isConnected(connectionID: connection.id))
        var disabled = connection
        disabled.enabled = false

        live.updateConnectionContext(
            connections: [disabled],
            selectedConnectionID: "",
            defaultProjectConnectionID: ""
        )

        XCTAssertFalse(live.isConnected(connectionID: connection.id))
        XCTAssertThrowsError(try live.projection(connectionID: connection.id))
    }

    func testInstallProjectionDoesNotRequireClientReconnect() throws {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(
            id: "c1",
            name: "Test",
            kind: .ssh,
            sshHost: "example.test"
        )
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let snapshot = HerdrSnapshot(
            version: "0.8.0",
            protocolVersion: 19,
            focusedWorkspaceID: "w1",
            focusedTabID: "t1",
            focusedPaneID: "p2",
            workspaces: [
                .object([
                    "workspace_id": .string("w1"), "number": .number(1), "label": .string("alpha"),
                    "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(1),
                    "active_tab_id": .string("t1"), "agent_status": .string("idle"),
                ]),
            ],
            tabs: [
                .object([
                    "tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1),
                    "label": .string("build"), "focused": .bool(true), "pane_count": .number(2),
                    "agent_status": .string("idle"),
                ]),
            ],
            panes: [
                .object([
                    "pane_id": .string("p1"), "terminal_id": .string("term1"),
                    "workspace_id": .string("w1"), "tab_id": .string("t1"),
                    "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1),
                ]),
                .object([
                    "pane_id": .string("p2"), "terminal_id": .string("term2"),
                    "workspace_id": .string("w1"), "tab_id": .string("t1"),
                    "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1),
                ]),
            ],
            layouts: [
                .object([
                    "workspace_id": .string("w1"), "tab_id": .string("t1"), "zoomed": .bool(false),
                    "focused_pane_id": .string("p2"),
                    "area": .object(["x": .number(0), "y": .number(0), "width": .number(100), "height": .number(40)]),
                    "panes": .array([
                        .object([
                            "pane_id": .string("p1"), "focused": .bool(false),
                            "rect": .object(["x": .number(0), "y": .number(0), "width": .number(49), "height": .number(40)]),
                        ]),
                        .object([
                            "pane_id": .string("p2"), "focused": .bool(true),
                            "rect": .object(["x": .number(51), "y": .number(0), "width": .number(49), "height": .number(40)]),
                        ]),
                    ]),
                    "splits": .array([
                        .object([
                            "id": .string("split_0_root"), "direction": .string("right"), "ratio": .number(0.5),
                            "rect": .object(["x": .number(0), "y": .number(0), "width": .number(100), "height": .number(40)]),
                        ]),
                    ]),
                ]),
            ],
            agents: []
        )
        let projection = try HerdrSessionProjection(snapshot: snapshot)
        let client = HerdrActionClient(api: HerdrSocketAPI(socketPath: "/tmp/herdr-a.sock"))
        live.update(client: client, connectionID: "c1", projection: projection)

        let optimistic = try projection.applyingLocalFocus(paneID: "p1")
        live.installProjection(optimistic, connectionID: "c1")

        XCTAssertEqual(try live.projection(connectionID: "c1").focusedPane?.id, "p1")
        XCTAssertTrue(live.isConnected(connectionID: "c1"))
    }

    func testGenerationCheckedDispatchAbortsWhenReplacementWinsDuringPreflight() async throws {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "c1", name: "Test", kind: .ssh, sshHost: "test")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let preflightStarted = DispatchSemaphore(value: 0)
        let releasePreflight = DispatchSemaphore(value: 0)
        let oldAPI = BlockingDispatchMutationAPI(
            snapshot: .prefixDispatchFixture,
            preflightStarted: preflightStarted,
            releasePreflight: releasePreflight
        )
        let oldGeneration = live.connect(
            client: HerdrActionClient(api: oldAPI),
            connectionID: connection.id,
            projection: nil
        )

        let task = Task {
            await live.dispatchHerdrDefault(.splitPane(.right), connectionID: connection.id)
        }
        XCTAssertEqual(preflightStarted.wait(timeout: .now() + 1), .success)
        let newGeneration = live.connect(
            client: HerdrActionClient(api: RecordingDispatchMutationAPI(snapshot: .prefixDispatchFixture)),
            connectionID: connection.id,
            projection: nil
        )
        releasePreflight.signal()
        let result = await task.value

        XCTAssertNotEqual(oldGeneration, newGeneration)
        XCTAssertEqual(result, .rejected(.generationChanged))
        XCTAssertTrue(oldAPI.mutationMethods.isEmpty)
    }

    func testGenerationCheckedNoOpRejectsObsoletePreflightProjection() async throws {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "c1", name: "Test", kind: .ssh, sshHost: "test")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let preflightStarted = DispatchSemaphore(value: 0)
        let releasePreflight = DispatchSemaphore(value: 0)
        let oldAPI = BlockingDispatchMutationAPI(
            snapshot: .prefixDispatchFixture,
            preflightStarted: preflightStarted,
            releasePreflight: releasePreflight
        )
        live.connect(
            client: HerdrActionClient(api: oldAPI),
            connectionID: connection.id,
            projection: nil
        )

        let task = Task {
            await live.dispatchHerdrDefault(.focusTab(9), connectionID: connection.id)
        }
        XCTAssertEqual(preflightStarted.wait(timeout: .now() + 1), .success)
        let replacementProjection = try HerdrSessionProjection(snapshot: .prefixReplacementFixture)
        live.connect(
            client: HerdrActionClient(api: RecordingDispatchMutationAPI(snapshot: .prefixDispatchFixture)),
            connectionID: connection.id,
            projection: replacementProjection
        )
        releasePreflight.signal()

        let result = await task.value
        XCTAssertEqual(result, .rejected(.generationChanged))
        XCTAssertTrue(oldAPI.mutationMethods.isEmpty)
        XCTAssertEqual(try live.projection(connectionID: connection.id), replacementProjection)
    }

    func testReplacementReturnsPromptlyWhileEarlierMutationOwnsFiniteLaneAttempt() async throws {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "c1", name: "Test", kind: .ssh, sshHost: "test")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let mutationStarted = DispatchSemaphore(value: 0)
        let releaseMutation = DispatchSemaphore(value: 0)
        let oldAPI = BlockingDispatchMutationAPI(
            snapshot: .prefixDispatchFixture,
            mutationStarted: mutationStarted,
            releaseMutation: releaseMutation
        )
        live.connect(
            client: HerdrActionClient(api: oldAPI),
            connectionID: connection.id,
            projection: nil
        )
        let task = Task {
            await live.dispatchHerdrDefault(.splitPane(.right), connectionID: connection.id)
        }
        XCTAssertEqual(mutationStarted.wait(timeout: .now() + 1), .success)

        let started = ProcessInfo.processInfo.systemUptime
        live.connect(
            client: HerdrActionClient(api: RecordingDispatchMutationAPI(snapshot: .prefixDispatchFixture)),
            connectionID: connection.id,
            projection: nil
        )
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.1)
        XCTAssertTrue(live.isConnected(connectionID: connection.id))
        releaseMutation.signal()

        let result = await task.value
        XCTAssertEqual(result, .rejected(.supersededAfterAcknowledgement))
        XCTAssertEqual(oldAPI.mutationMethods, ["pane.split"])
    }

    func testReplacementAfterTransmittedUnknownMutationPreservesUncertainty() async throws {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "c1", name: "Test", kind: .ssh, sshHost: "test")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let mutationStarted = DispatchSemaphore(value: 0)
        let releaseMutation = DispatchSemaphore(value: 0)
        let oldAPI = BlockingDispatchMutationAPI(
            snapshot: .prefixDispatchFixture,
            mutationStarted: mutationStarted,
            releaseMutation: releaseMutation,
            mutationOutcome: .failure(.init(
                disposition: .mutationOutcomeUnknown,
                underlying: HerdrClientError.connectionClosed
            ))
        )
        live.connect(
            client: HerdrActionClient(api: oldAPI),
            connectionID: connection.id,
            projection: nil
        )
        let task = Task {
            await live.dispatchHerdrDefault(.splitPane(.right), connectionID: connection.id)
        }
        XCTAssertEqual(mutationStarted.wait(timeout: .now() + 1), .success)
        live.connect(
            client: HerdrActionClient(api: RecordingDispatchMutationAPI(snapshot: .prefixDispatchFixture)),
            connectionID: connection.id,
            projection: nil
        )
        releaseMutation.signal()

        let result = await task.value
        guard case .failed(let failure, let recovered) = result else {
            return XCTFail("A generation replacement cannot erase transmitted-request uncertainty")
        }
        XCTAssertEqual(failure.disposition, .mutationOutcomeUnknown)
        XCTAssertNil(recovered, "An obsolete generation must not install recovery state")
        XCTAssertEqual(oldAPI.mutationMethods, ["pane.split"])
    }

    func testUnknownMutationOutcomeRecoversSnapshotWithoutRetry() async throws {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "c1", name: "Test", kind: .ssh, sshHost: "test")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let api = RecordingDispatchMutationAPI(
            snapshot: .prefixDispatchFixture,
            mutationOutcome: .failure(.init(
                disposition: .mutationOutcomeUnknown,
                underlying: HerdrClientError.connectionClosed
            ))
        )
        live.connect(
            client: HerdrActionClient(api: api),
            connectionID: connection.id,
            projection: nil
        )

        let result = await live.dispatchHerdrDefault(.splitPane(.right), connectionID: connection.id)

        guard case .failed(let failure, let recovered) = result else {
            return XCTFail("expected uncertain failure")
        }
        XCTAssertEqual(failure.disposition, .mutationOutcomeUnknown)
        XCTAssertEqual(failure.completedRequestCount, 0)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(api.mutationMethods, ["pane.split"], "Mutation must never be retried")
        XCTAssertEqual(api.snapshotCount, 2, "Preflight plus one recovery snapshot")
    }

    func testSynchronousIntentReportsUnknownMutationAsFailureAfterRecovery() throws {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "c1", name: "Test", kind: .ssh, sshHost: "test")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        let api = RecordingDispatchMutationAPI(
            snapshot: .prefixDispatchFixture,
            mutationOutcome: .failure(.init(
                disposition: .mutationOutcomeUnknown,
                underlying: HerdrClientError.connectionClosed
            ))
        )
        live.connect(
            client: HerdrActionClient(api: api),
            connectionID: connection.id,
            projection: nil
        )

        XCTAssertThrowsError(try live.perform(
            .paneSplit(targetPaneID: "p2", direction: .right, ratio: nil, cwd: nil, focus: true),
            connectionID: connection.id
        ))
        XCTAssertEqual(api.mutationMethods, ["pane.split"])
        XCTAssertEqual(api.snapshotCount, 2, "Recovery refreshes status but cannot turn uncertainty into success")
        XCTAssertEqual(try live.projection(connectionID: connection.id).focusedPane?.id, "p2")
    }

    func testGenericBatchRecoversUnknownPartialMutationWithoutRetry() throws {
        let live = configuredLivePort()
        let api = SequencedDispatchMutationAPI(
            snapshots: [.success(.prefixDispatchFixture), .success(.prefixDispatchFixture)],
            mutations: [
                .success(.object([:])),
                .failure(.init(
                    disposition: .mutationOutcomeUnknown,
                    underlying: HerdrClientError.connectionClosed
                )),
            ]
        )
        live.connect(client: HerdrActionClient(api: api), connectionID: "c1", projection: nil)

        XCTAssertThrowsError(try live.perform([
            .workspaceFocus(id: "w1"),
            .setSplitRatio(tabID: "t2", path: [], ratio: 0.6),
        ], connectionID: "c1")) { error in
            let failure = error as? HerdrActionAttemptFailure
            XCTAssertEqual(failure?.disposition, .mutationOutcomeUnknown)
            XCTAssertEqual(failure?.completedRequestCount, 1)
        }
        XCTAssertEqual(api.mutationMethods, ["workspace.focus", "layout.set_split_ratio"])
        XCTAssertEqual(api.snapshotCount, 2, "Preflight plus recovery snapshot")
    }

    func testGenericBatchClassifiesReconciliationFailureAsUnknownAndRecovers() throws {
        let live = configuredLivePort()
        let api = SequencedDispatchMutationAPI(
            snapshots: [
                .success(.prefixDispatchFixture),
                .failure(HerdrClientError.connectionClosed),
                .success(.prefixDispatchFixture),
            ],
            mutations: [.success(.object([:]))]
        )
        live.connect(client: HerdrActionClient(api: api), connectionID: "c1", projection: nil)

        XCTAssertThrowsError(try live.perform(.workspaceFocus(id: "w1"), connectionID: "c1")) { error in
            let failure = error as? HerdrActionAttemptFailure
            XCTAssertEqual(failure?.disposition, .mutationOutcomeUnknown)
            XCTAssertEqual(failure?.completedRequestCount, 1)
        }
        XCTAssertEqual(api.mutationMethods, ["workspace.focus"])
        XCTAssertEqual(api.snapshotCount, 3, "Failed reconciliation must recover without replay")
        XCTAssertEqual(try live.projection(connectionID: "c1").focusedPane?.id, "p2")
    }

    private func configuredLivePort() -> AppIntentLivePort {
        let live = AppIntentLivePort()
        let connection = BessieConnectionDefinition(id: "c1", name: "Test", kind: .ssh, sshHost: "test")
        live.updateConnectionContext(
            connections: [connection],
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id
        )
        return live
    }
}

private final class RecordingDispatchMutationAPI: HerdrMutationAPI, @unchecked Sendable {
    private let lock = NSLock()
    let snapshotValue: HerdrSnapshot
    let mutationOutcome: Result<JSONValue, HerdrMutationRequestFailure>
    private(set) var mutationMethods: [String] = []
    private(set) var snapshotCount = 0

    init(
        snapshot: HerdrSnapshot,
        mutationOutcome: Result<JSONValue, HerdrMutationRequestFailure> = .success(.object([:]))
    ) {
        snapshotValue = snapshot
        self.mutationOutcome = mutationOutcome
    }

    func request(method: String, params: [String: JSONValue]) throws -> JSONValue {
        try stagedMutationRequest(method: method, params: params).get()
    }

    func stagedMutationRequest(
        method: String,
        params: [String: JSONValue]
    ) -> Result<JSONValue, HerdrMutationRequestFailure> {
        lock.withLock { mutationMethods.append(method) }
        return mutationOutcome
    }

    func snapshot() throws -> HerdrSnapshot {
        lock.withLock { snapshotCount += 1 }
        return snapshotValue
    }
}

private func waitForDispatchSemaphore(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + 1) == .success
}

private final class BlockingDispatchMutationAPI: HerdrMutationAPI, @unchecked Sendable {
    private let lock = NSLock()
    let snapshotValue: HerdrSnapshot
    let preflightStarted: DispatchSemaphore?
    let releasePreflight: DispatchSemaphore?
    let mutationStarted: DispatchSemaphore?
    let releaseMutation: DispatchSemaphore?
    let mutationOutcome: Result<JSONValue, HerdrMutationRequestFailure>
    private(set) var mutationMethods: [String] = []
    private var didBlockPreflight = false

    init(
        snapshot: HerdrSnapshot,
        preflightStarted: DispatchSemaphore? = nil,
        releasePreflight: DispatchSemaphore? = nil,
        mutationStarted: DispatchSemaphore? = nil,
        releaseMutation: DispatchSemaphore? = nil,
        mutationOutcome: Result<JSONValue, HerdrMutationRequestFailure> = .success(.object([:]))
    ) {
        snapshotValue = snapshot
        self.preflightStarted = preflightStarted
        self.releasePreflight = releasePreflight
        self.mutationStarted = mutationStarted
        self.releaseMutation = releaseMutation
        self.mutationOutcome = mutationOutcome
    }

    func request(method: String, params: [String: JSONValue]) throws -> JSONValue {
        try stagedMutationRequest(method: method, params: params).get()
    }

    func stagedMutationRequest(
        method: String,
        params: [String: JSONValue]
    ) -> Result<JSONValue, HerdrMutationRequestFailure> {
        lock.withLock { mutationMethods.append(method) }
        mutationStarted?.signal()
        releaseMutation?.wait()
        return mutationOutcome
    }

    func snapshot() throws -> HerdrSnapshot {
        let shouldBlock = lock.withLock {
            guard !didBlockPreflight else { return false }
            didBlockPreflight = true
            return preflightStarted != nil
        }
        if shouldBlock {
            preflightStarted?.signal()
            releasePreflight?.wait()
        }
        return snapshotValue
    }
}

private final class SequencedDispatchMutationAPI: HerdrMutationAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [Result<HerdrSnapshot, Error>]
    private var mutations: [Result<JSONValue, HerdrMutationRequestFailure>]
    private(set) var mutationMethods: [String] = []
    private(set) var snapshotCount = 0

    init(
        snapshots: [Result<HerdrSnapshot, Error>],
        mutations: [Result<JSONValue, HerdrMutationRequestFailure>]
    ) {
        self.snapshots = snapshots
        self.mutations = mutations
    }

    func request(method: String, params: [String: JSONValue]) throws -> JSONValue {
        try stagedMutationRequest(method: method, params: params).get()
    }

    func stagedMutationRequest(
        method: String,
        params: [String: JSONValue]
    ) -> Result<JSONValue, HerdrMutationRequestFailure> {
        lock.withLock {
            mutationMethods.append(method)
            return mutations.removeFirst()
        }
    }

    func snapshot() throws -> HerdrSnapshot {
        try lock.withLock {
            snapshotCount += 1
            return try snapshots.removeFirst().get()
        }
    }
}

private extension HerdrSnapshot {
    static let prefixDispatchFixture = HerdrSnapshot(
        version: "0.8.0",
        protocolVersion: 19,
        focusedWorkspaceID: "w1",
        focusedTabID: "t2",
        focusedPaneID: "p2",
        workspaces: [
            .object([
                "workspace_id": .string("w1"), "number": .number(1), "label": .string("main"),
                "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(2),
                "active_tab_id": .string("t2"), "agent_status": .string("idle"),
            ]),
        ],
        tabs: [
            .object([
                "tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1),
                "label": .string("one"), "focused": .bool(false), "pane_count": .number(1),
                "agent_status": .string("idle"),
            ]),
            .object([
                "tab_id": .string("t2"), "workspace_id": .string("w1"), "number": .number(2),
                "label": .string("two"), "focused": .bool(true), "pane_count": .number(1),
                "agent_status": .string("idle"),
            ]),
        ],
        panes: [
            .object([
                "pane_id": .string("p1"), "terminal_id": .string("term1"),
                "workspace_id": .string("w1"), "tab_id": .string("t1"),
                "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1),
            ]),
            .object([
                "pane_id": .string("p2"), "terminal_id": .string("term2"),
                "workspace_id": .string("w1"), "tab_id": .string("t2"),
                "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1),
            ]),
        ],
        layouts: [],
        agents: []
    )

    static let prefixReplacementFixture = HerdrSnapshot(
        version: "0.8.0",
        protocolVersion: 19,
        focusedWorkspaceID: nil,
        focusedTabID: nil,
        focusedPaneID: nil,
        workspaces: [],
        tabs: [],
        panes: [],
        layouts: [],
        agents: []
    )
}
