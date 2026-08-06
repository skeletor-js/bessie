import Foundation
import XCTest
@testable import BessieCore

final class LiveHerdrTests: XCTestCase {
    func testPinnedIsolatedRuntimeSupportsPingSubscriptionAndSnapshotBootstrap() throws {
        guard let socketPath = ProcessInfo.processInfo.environment["BESSIE_LIVE_HERDR_SOCKET"] else {
            throw XCTSkip("Set BESSIE_LIVE_HERDR_SOCKET only for the isolated Mac live check.")
        }

        let api = HerdrSocketAPI(socketPath: socketPath)
        let identity = try api.ping()
        XCTAssertEqual(identity, HerdrServerIdentity(version: "0.8.0", protocolVersion: 19))

        let bootstrapped = try HerdrBootstrapper().bootstrap(api: api)
        defer { bootstrapped.subscription.close() }
        XCTAssertEqual(bootstrapped.snapshot.version, "0.8.0")
        XCTAssertEqual(bootstrapped.snapshot.protocolVersion, 19)

        let created = try api.request(
            method: "workspace.create",
            params: ["label": .string("bessie-m2-live"), "focus": .bool(true)]
        )
        let workspaceID = try XCTUnwrap(created.objectValue?["workspace"]?.objectValue?["workspace_id"]?.stringValue)
        defer { _ = try? api.request(method: "workspace.close", params: ["workspace_id": .string(workspaceID)]) }

        Thread.sleep(forTimeInterval: 0.25)
        XCTAssertTrue(bootstrapped.subscription.drainBufferedEvents().contains { $0.name == "workspace_created" })
        let converged = try api.snapshot()
        XCTAssertTrue(converged.workspaces.contains { $0.objectValue?["workspace_id"]?.stringValue == workspaceID })
    }

    func testTypedActionsMutateAndReconcileIsolatedHerdrTopology() throws {
        guard let socketPath = ProcessInfo.processInfo.environment["BESSIE_LIVE_HERDR_SOCKET"] else {
            throw XCTSkip("Set BESSIE_LIVE_HERDR_SOCKET only for the isolated Mac live check.")
        }

        let api = HerdrSocketAPI(socketPath: socketPath)
        let client = HerdrActionClient(api: api)
        let runID = ProcessInfo.processInfo.environment["BESSIE_LIVE_RUN_ID"] ?? UUID().uuidString
        let initial = try HerdrSessionProjection(snapshot: api.snapshot())
        let originalWorkspaceIDs = Set(initial.workspaces.map(\.id))

        var projection = try client.perform(.workspaceCreate(cwd: nil, label: "bessie-m3-\(runID)", focus: true))
        let workspace = try XCTUnwrap(projection.workspaces.first { $0.label == "bessie-m3-\(runID)" })
        defer {
            for id in ((try? HerdrSessionProjection(snapshot: api.snapshot()).workspaces.map(\.id)) ?? []) where !originalWorkspaceIDs.contains(id) {
                _ = try? api.request(method: "workspace.close", params: ["workspace_id": .string(id)])
            }
        }

        projection = try client.perform(.workspaceRename(id: workspace.id, label: "bessie-m3-renamed-\(runID)"))
        XCTAssertEqual(projection.focusedWorkspace?.id, workspace.id)
        XCTAssertEqual(projection.workspaces.first { $0.id == workspace.id }?.label, "bessie-m3-renamed-\(runID)")
        projection = try client.perform(.workspaceMove(id: workspace.id, insertIndex: 0))
        XCTAssertEqual(projection.workspaces.first?.id, workspace.id)
        projection = try client.perform(.workspaceFocus(id: workspace.id))
        XCTAssertEqual(projection.focusedWorkspace?.id, workspace.id)

        var initialTab = try XCTUnwrap(projection.tabs.first { $0.workspaceID == workspace.id })
        var initialPane = try XCTUnwrap(projection.panes.first { $0.tabID == initialTab.id })
        projection = try client.perform(.tabCreate(workspaceID: workspace.id, cwd: nil, label: "m3-second", focus: false))
        var secondTab = try XCTUnwrap(projection.tabs.first { $0.workspaceID == workspace.id && $0.id != initialTab.id })
        projection = try client.perform(.tabRename(id: secondTab.id, label: "m3-renamed-tab"))
        XCTAssertEqual(projection.tabs.first { $0.id == secondTab.id }?.label, "m3-renamed-tab")
        projection = try client.perform(.tabMove(id: secondTab.id, insertIndex: 0))
        let reorderedTabs = projection.tabs.filter { $0.workspaceID == workspace.id }
        XCTAssertEqual(reorderedTabs.map(\.number), [1, 2])
        secondTab = try XCTUnwrap(reorderedTabs.first)
        initialTab = try XCTUnwrap(reorderedTabs.last)
        initialPane = try XCTUnwrap(projection.panes.first { $0.tabID == initialTab.id })
        projection = try client.perform(.tabFocus(id: initialTab.id))
        XCTAssertEqual(projection.focusedTab?.id, initialTab.id)

        projection = try client.perform(.paneSplit(targetPaneID: initialPane.id, direction: .right, ratio: 0.45, cwd: nil, focus: true))
        let splitPane = try XCTUnwrap(projection.panes.first { $0.tabID == initialTab.id && $0.id != initialPane.id })
        XCTAssertEqual(Set(projection.layouts[initialTab.id]?.root.paneIDs ?? []), Set([initialPane.id, splitPane.id]))
        projection = try client.perform(.paneRename(id: splitPane.id, label: "m3-split"))
        XCTAssertEqual(projection.panes.first { $0.id == splitPane.id }?.label, "m3-split")
        projection = try client.perform(.paneFocus(id: initialPane.id))
        XCTAssertEqual(projection.focusedPane?.id, initialPane.id)
        projection = try client.perform(.paneResize(id: initialPane.id, direction: .right, amount: 0.05))
        XCTAssertNotNil(projection.layouts[initialTab.id])
        projection = try client.perform(.setSplitRatio(tabID: initialTab.id, path: [], ratio: 0.6))
        guard case .split(let root) = try XCTUnwrap(projection.layouts[initialTab.id]?.root) else {
            return XCTFail("expected live split root")
        }
        XCTAssertEqual(root.ratio, 0.6, accuracy: 0.001)
        projection = try client.perform(.paneSwapExplicit(sourceID: initialPane.id, targetID: splitPane.id))
        XCTAssertEqual(Set(projection.layouts[initialTab.id]?.root.paneIDs ?? []), Set([initialPane.id, splitPane.id]))
        projection = try client.perform(.paneZoom(id: initialPane.id, mode: .on))
        XCTAssertEqual(projection.layouts[initialTab.id]?.zoomed, true)
        projection = try client.perform(.paneZoom(id: initialPane.id, mode: .off))
        XCTAssertEqual(projection.layouts[initialTab.id]?.zoomed, false)

        let secondTabTarget = try XCTUnwrap(projection.panes.first { $0.tabID == secondTab.id })
        projection = try client.perform(.paneMove(id: splitPane.id, destination: .tab(tabID: secondTab.id, targetPaneID: secondTabTarget.id, split: .down, ratio: 0.5), focus: true))
        XCTAssertEqual(projection.focusedTab?.id, secondTab.id)
        XCTAssertEqual(projection.tabs.first { $0.id == secondTab.id }?.paneCount, 2)
        projection = try client.perform(.paneClose(id: splitPane.id))
        XCTAssertFalse(projection.panes.contains { $0.id == splitPane.id })
        projection = try client.perform(.tabClose(id: secondTab.id))
        XCTAssertFalse(projection.tabs.contains { $0.id == secondTab.id })
        projection = try client.perform(.workspaceClose(id: workspace.id))
        XCTAssertFalse(projection.workspaces.contains { $0.id == workspace.id })
    }

    func testFinalPaneAndFinalTabUseHerdrAuthoritativeWorkspaceCascade() throws {
        guard let socketPath = ProcessInfo.processInfo.environment["BESSIE_LIVE_HERDR_SOCKET"] else {
            throw XCTSkip("Set BESSIE_LIVE_HERDR_SOCKET only for the isolated Mac live check.")
        }

        let api = HerdrSocketAPI(socketPath: socketPath)
        let client = HerdrActionClient(api: api)
        let runID = ProcessInfo.processInfo.environment["BESSIE_LIVE_RUN_ID"] ?? UUID().uuidString

        let paneWorkspace = try HerdrWorkspaceCreationResult(result: api.request(
            method: "workspace.create",
            params: ["label": .string("bessie-final-pane-\(runID)"), "focus": .bool(true)]
        ))
        var projection = try client.perform(.paneClose(id: paneWorkspace.rootPaneID))
        XCTAssertFalse(projection.panes.contains { $0.id == paneWorkspace.rootPaneID })
        XCTAssertFalse(projection.workspaces.contains { $0.id == paneWorkspace.workspaceID })

        let tabWorkspace = try HerdrWorkspaceCreationResult(result: api.request(
            method: "workspace.create",
            params: ["label": .string("bessie-final-tab-\(runID)"), "focus": .bool(true)]
        ))
        projection = try client.perform(.tabClose(id: tabWorkspace.tabID))
        XCTAssertFalse(projection.tabs.contains { $0.id == tabWorkspace.tabID })
        XCTAssertFalse(projection.workspaces.contains { $0.id == tabWorkspace.workspaceID })
    }

    func testProjectsMilestoneZeroContractAgainstIsolatedHerdr() throws {
        guard let socketPath = ProcessInfo.processInfo.environment["BESSIE_LIVE_HERDR_SOCKET"] else {
            throw XCTSkip("Set BESSIE_LIVE_HERDR_SOCKET only for the isolated Mac live check.")
        }

        let api = HerdrSocketAPI(socketPath: socketPath)
        let runID = ProcessInfo.processInfo.environment["BESSIE_LIVE_RUN_ID"] ?? UUID().uuidString
        let outputMarker = "BESSIE_M0_EXECUTED_\(runID)"
        let padding = String(repeating: "x", count: 96)
        let command = "printf 'BESSIE_M0_EXECUTED_%s' '\(runID)'; : '\(padding)'"
        let created = try HerdrWorkspaceCreationResult(result: api.request(
            method: "workspace.create",
            params: [
                "cwd": .string(FileManager.default.currentDirectoryPath),
                "label": .string("duplicate-label"),
                "focus": .bool(true),
            ]
        ))
        defer {
            _ = try? api.request(
                method: "workspace.close",
                params: ["workspace_id": .string(created.workspaceID)]
            )
        }

        let workspaceSnapshot = try api.snapshot()
        XCTAssertTrue(workspaceSnapshot.workspaces.contains { $0.string(at: "workspace_id") == created.workspaceID })
        XCTAssertTrue(workspaceSnapshot.tabs.contains { $0.string(at: "tab_id") == created.tabID })
        let paneValue = try XCTUnwrap(workspaceSnapshot.panes.first { $0.string(at: "pane_id") == created.rootPaneID })
        let paneFacts = try HerdrPaneContractFacts(value: paneValue)
        XCTAssertFalse(try XCTUnwrap(paneFacts.cwd).isEmpty)

        let createdTab = try HerdrTabCreationResult(result: api.request(
            method: "tab.create",
            params: [
                "workspace_id": .string(created.workspaceID),
                "cwd": .string(FileManager.default.currentDirectoryPath),
                "label": .string("duplicate-label"),
                "focus": .bool(false),
            ]
        ))
        let tabSnapshot = try api.snapshot()
        XCTAssertTrue(tabSnapshot.tabs.contains { $0.string(at: "tab_id") == created.tabID })
        XCTAssertTrue(tabSnapshot.panes.contains { $0.string(at: "pane_id") == created.rootPaneID })
        XCTAssertTrue(tabSnapshot.tabs.contains { $0.string(at: "tab_id") == createdTab.tabID })
        XCTAssertTrue(tabSnapshot.panes.contains { $0.string(at: "pane_id") == createdTab.rootPaneID })

        let splitPane = try HerdrPaneCreationResult(result: api.request(
            method: "pane.split",
            params: [
                "target_pane_id": .string(createdTab.rootPaneID),
                "direction": .string("right"),
                "ratio": .number(0.5),
                "cwd": .string(FileManager.default.currentDirectoryPath),
                "focus": .bool(false),
            ]
        ))
        for paneID in [createdTab.rootPaneID, splitPane.paneID] {
            _ = try api.request(
                method: "pane.rename",
                params: ["pane_id": .string(paneID), "label": .string("duplicate-label")]
            )
        }
        let splitSnapshot = try api.snapshot()
        XCTAssertTrue(splitSnapshot.tabs.contains { $0.string(at: "tab_id") == created.tabID })
        XCTAssertTrue(splitSnapshot.panes.contains { $0.string(at: "pane_id") == created.rootPaneID })
        XCTAssertTrue(splitSnapshot.tabs.contains { $0.string(at: "tab_id") == createdTab.tabID })
        XCTAssertTrue(splitSnapshot.panes.contains { $0.string(at: "pane_id") == createdTab.rootPaneID })
        XCTAssertTrue(splitSnapshot.panes.contains { $0.string(at: "pane_id") == splitPane.paneID })

        try HerdrStartupCommandSubmitter(api: api).submit(command: command, toPaneID: created.rootPaneID)

        let deadline = Date(timeIntervalSinceNow: 5)
        var observed = ""
        repeat {
            observed = try api.request(
                method: "pane.read",
                params: [
                    "pane_id": .string(created.rootPaneID),
                    "source": .string("visible"),
                    "lines": .number(20),
                    "format": .string("text"),
                    "strip_ansi": .bool(true),
                ]
            ).string(at: "read", "text") ?? ""
            if observed.contains(outputMarker) { break }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        XCTAssertTrue(observed.contains(outputMarker), "startup command output was not observed")
    }

    func testNativeProjectMaterializerAgainstIsolatedHerdr() throws {
        guard let socketPath = ProcessInfo.processInfo.environment["BESSIE_LIVE_HERDR_SOCKET"] else {
            throw XCTSkip("Set BESSIE_LIVE_HERDR_SOCKET only for the isolated Mac live check.")
        }

        let api = HerdrSocketAPI(socketPath: socketPath)
        let runID = ProcessInfo.processInfo.environment["BESSIE_LIVE_RUN_ID"] ?? UUID().uuidString
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-materializer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let firstRootID = UUID()
        let splitID = UUID()
        let secondRootID = UUID()
        let outputMarker = "BESSIE_M2_EXECUTED_\(runID)"
        let command = "printf 'BESSIE_M2_EXECUTED_%s' '\(runID)'; : '\(String(repeating: "x", count: 96))'"
        let project = BessieProject(
            name: "duplicate-label",
            workingDirectory: workingDirectory.path,
            tabs: [
                .init(name: "duplicate-label", panes: [
                    .init(id: firstRootID, label: "duplicate-label", command: command, placement: .root),
                    .init(
                        id: splitID,
                        label: "duplicate-label",
                        placement: .split(fromPaneID: firstRootID, direction: .down, ratio: 0.37)
                    ),
                ]),
                .init(name: "duplicate-label", panes: [
                    .init(id: secondRootID, label: "duplicate-label", placement: .root),
                ]),
            ]
        )
        let generation = UUID()
        let connection = BessieProjectMaterializationConnection(
            definition: .init(id: "isolated-live", name: "Isolated live", kind: .local, session: "isolated"),
            socketPath: socketPath,
            generation: generation,
            identity: try api.ping()
        )
        let initialWorkspaceIDs = Set(try api.snapshot().workspaces.compactMap { $0.string(at: "workspace_id") })
        defer {
            if let finalSnapshot = try? api.snapshot() {
                let createdWorkspaceIDs = Set(finalSnapshot.workspaces.compactMap { $0.string(at: "workspace_id") })
                    .subtracting(initialWorkspaceIDs)
                for workspaceID in createdWorkspaceIDs {
                    _ = try? api.request(
                        method: "workspace.close",
                        params: ["workspace_id": .string(workspaceID)]
                    )
                }
            }
        }
        let result = try BessieProjectMaterializer(
            api: api,
            connectionStatus: { expected in
                expected.generation == generation ? .current : .changed
            }
        ).materialize(project, on: connection)

        XCTAssertEqual(Set(result.tabIDsByRecipeID.keys), Set(project.tabs.map(\.id)))
        XCTAssertEqual(Set(result.paneIDsByRecipeID.keys), Set([firstRootID, splitID, secondRootID]))
        XCTAssertEqual(Set(result.tabIDsByRecipeID.values).count, 2)
        XCTAssertEqual(Set(result.paneIDsByRecipeID.values).count, 3)
        XCTAssertTrue(result.commands.allSatisfy(\.enterSubmitted))

        let freshSnapshot = try api.snapshot()
        XCTAssertTrue(freshSnapshot.workspaces.contains { $0.string(at: "workspace_id") == result.workspaceID })
        for runtimeTabID in result.tabIDsByRecipeID.values {
            XCTAssertTrue(freshSnapshot.tabs.contains {
                $0.string(at: "tab_id") == runtimeTabID && $0.string(at: "workspace_id") == result.workspaceID
            })
        }
        for runtimePaneID in result.paneIDsByRecipeID.values {
            XCTAssertTrue(freshSnapshot.panes.contains {
                $0.string(at: "pane_id") == runtimePaneID && $0.string(at: "workspace_id") == result.workspaceID
            })
        }

        let firstRuntimePaneID = try XCTUnwrap(result.paneIDsByRecipeID[firstRootID])
        let deadline = Date(timeIntervalSinceNow: 5)
        var observed = ""
        repeat {
            observed = try api.request(
                method: "pane.read",
                params: [
                    "pane_id": .string(firstRuntimePaneID),
                    "source": .string("visible"),
                    "lines": .number(20),
                    "format": .string("text"),
                    "strip_ansi": .bool(true),
                ]
            ).string(at: "read", "text") ?? ""
            if observed.contains(outputMarker) { break }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        XCTAssertTrue(observed.contains(outputMarker), "materialized startup command output was not observed")
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    func string(at path: String...) -> String? {
        var current = self
        for key in path {
            guard let next = current.objectValue?[key] else { return nil }
            current = next
        }
        return current.stringValue
    }
}
