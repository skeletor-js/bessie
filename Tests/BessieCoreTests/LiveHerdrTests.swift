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
        XCTAssertEqual(identity, HerdrServerIdentity(version: "0.7.5", protocolVersion: 17))

        let bootstrapped = try HerdrBootstrapper().bootstrap(api: api)
        defer { bootstrapped.subscription.close() }
        XCTAssertEqual(bootstrapped.snapshot.version, "0.7.5")
        XCTAssertEqual(bootstrapped.snapshot.protocolVersion, 17)

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
}
