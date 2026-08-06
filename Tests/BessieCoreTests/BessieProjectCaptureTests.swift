import Foundation
import XCTest
@testable import BessieCore

final class BessieProjectCaptureTests: XCTestCase {
    func testCaptureRejectsMissingProjectionAndMissingFocusedWorkspace() throws {
        XCTAssertThrowsError(try BessieProjectCapture.capture(from: nil)) { error in
            XCTAssertEqual(error as? BessieProjectCaptureError, .missingProjection)
        }

        let projection = try HerdrSessionProjection(snapshot: .emptyCaptureFixture)
        XCTAssertThrowsError(try BessieProjectCapture.capture(from: projection)) { error in
            XCTAssertEqual(error as? BessieProjectCaptureError, .missingFocusedWorkspace)
        }
    }

    func testCaptureMapsNestedMultiTabTopologyWithFreshIDsAndBlankCommands() throws {
        let projection = try HerdrSessionProjection(snapshot: .captureFixture)
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let project = try BessieProjectCapture.capture(from: projection, now: capturedAt)

        XCTAssertEqual(project.name, "duplicate")
        XCTAssertEqual(project.workingDirectory, "/tmp/bessie-capture")
        XCTAssertEqual(project.createdAt, capturedAt)
        XCTAssertEqual(project.updatedAt, capturedAt)
        XCTAssertEqual(project.tabs.map(\.name), ["duplicate", "duplicate"])
        XCTAssertEqual(project.tabs.map(\.panes.count), [3, 1])
        XCTAssertEqual(project.tabs[0].panes.map(\.label), ["duplicate", "duplicate", "duplicate"])
        XCTAssertTrue(project.tabs.flatMap(\.panes).allSatisfy { $0.command == nil })

        let firstTab = project.tabs[0]
        XCTAssertEqual(firstTab.panes[0].placement, .root)
        XCTAssertEqual(
            firstTab.panes[1].placement,
            .split(fromPaneID: firstTab.panes[0].id, direction: .right, ratio: 1.0 / 3.0)
        )
        XCTAssertEqual(
            firstTab.panes[2].placement,
            .split(fromPaneID: firstTab.panes[0].id, direction: .down, ratio: 0.75)
        )

        XCTAssertEqual(Set(project.tabs.map(\.id)).count, 2)
        XCTAssertEqual(Set(project.tabs.flatMap(\.panes).map(\.id)).count, 4)
        let encoded = String(decoding: try BessieProjectCodec.encode(project), as: UTF8.self)
        for runtimeID in ["live-workspace", "live-tab-one", "live-tab-two", "live-pane-one", "live-pane-two", "live-pane-three", "live-pane-four"] {
            XCTAssertFalse(encoded.contains(runtimeID))
        }
    }

    func testCaptureLeavesWorkingDirectoryBlankWhenPaneCWDIsMissingOrAmbiguous() throws {
        let missing = try HerdrSessionProjection(snapshot: .captureFixture(cwds: [nil, "/tmp/bessie-capture", "/tmp/bessie-capture", "/tmp/bessie-capture"]))
        let ambiguous = try HerdrSessionProjection(snapshot: .captureFixture(cwds: ["/tmp/one", "/tmp/two", "/tmp/one", "/tmp/one"]))

        XCTAssertEqual(try BessieProjectCapture.capture(from: missing).workingDirectory, "")
        XCTAssertEqual(try BessieProjectCapture.capture(from: ambiguous).workingDirectory, "")
    }

    func testCaptureRejectsWorkspaceWithMissingLayout() throws {
        let projection = try HerdrSessionProjection(snapshot: .captureFixture(includeSecondLayout: false))

        XCTAssertThrowsError(try BessieProjectCapture.capture(from: projection)) { error in
            XCTAssertEqual(error as? BessieProjectCaptureError, .missingLayout(tabID: "live-tab-two"))
        }
    }

    func testCaptureRejectsSnapshotMissingAnAdvertisedTabAndPanes() throws {
        let projection = try HerdrSessionProjection(snapshot: .captureFixtureOmittingAdvertisedSecondTab)

        XCTAssertThrowsError(try BessieProjectCapture.capture(from: projection)) { error in
            XCTAssertEqual(error as? BessieProjectCaptureError, .missingTabs)
        }
    }

    func testCaptureRejectsDuplicatePaneFactsInsteadOfCrashing() throws {
        let projection = try HerdrSessionProjection(snapshot: .captureFixtureWithDuplicatePane)

        XCTAssertThrowsError(try BessieProjectCapture.capture(from: projection)) { error in
            XCTAssertEqual(error as? BessieProjectCaptureError, .missingPane(paneID: "live-pane-one"))
        }
    }

    func testCaptureAnchorsNestedSecondBranchToItsFreshRecipePane() throws {
        let projection = try HerdrSessionProjection(snapshot: .secondBranchCaptureFixture)
        let project = try BessieProjectCapture.capture(from: projection)
        let panes = try XCTUnwrap(project.tabs.first?.panes)

        XCTAssertEqual(panes.map(\.label), ["left", "upper-right", "lower-right"])
        XCTAssertEqual(panes[0].placement, .root)
        XCTAssertEqual(panes[1].placement, .split(fromPaneID: panes[0].id, direction: .right, ratio: 0.5))
        XCTAssertEqual(panes[2].placement, .split(fromPaneID: panes[1].id, direction: .down, ratio: 0.5))
    }

    func testProjectionUsesHerdrRoundedCellBoundaryForOddDimensions() throws {
        let projection = try HerdrSessionProjection(snapshot: .oddCellCaptureFixture)
        let project = try BessieProjectCapture.capture(from: projection)

        XCTAssertEqual(project.tabs[0].panes.map(\.label), ["rounded-first", "second"])
    }
}

private extension HerdrSnapshot {
    static let emptyCaptureFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: nil, focusedTabID: nil, focusedPaneID: nil,
        workspaces: [], tabs: [], panes: [], layouts: [], agents: []
    )

    static let captureFixture = captureFixture()

    static var captureFixtureOmittingAdvertisedSecondTab: HerdrSnapshot {
        let complete = captureFixture
        return HerdrSnapshot(
            version: complete.version, protocolVersion: complete.protocolVersion,
            focusedWorkspaceID: complete.focusedWorkspaceID, focusedTabID: "live-tab-one", focusedPaneID: "live-pane-one",
            workspaces: complete.workspaces,
            tabs: Array(complete.tabs.prefix(1)),
            panes: Array(complete.panes.prefix(3)),
            layouts: Array(complete.layouts.prefix(1)),
            agents: []
        )
    }

    static var captureFixtureWithDuplicatePane: HerdrSnapshot {
        let complete = captureFixture
        return HerdrSnapshot(
            version: complete.version, protocolVersion: complete.protocolVersion,
            focusedWorkspaceID: complete.focusedWorkspaceID, focusedTabID: complete.focusedTabID, focusedPaneID: complete.focusedPaneID,
            workspaces: complete.workspaces,
            tabs: complete.tabs,
            panes: complete.panes + [complete.panes[0]],
            layouts: complete.layouts,
            agents: complete.agents
        )
    }

    static let secondBranchCaptureFixture = simpleCaptureFixture(
        paneFacts: [
            ("left", "left", rect(x: 0, y: 0, width: 49, height: 40)),
            ("upper", "upper-right", rect(x: 51, y: 0, width: 49, height: 19)),
            ("lower", "lower-right", rect(x: 51, y: 21, width: 49, height: 19)),
        ],
        splits: [
            .object(["id": .string("split_root"), "direction": .string("right"), "ratio": .number(0.5), "rect": rect(x: 0, y: 0, width: 100, height: 40)]),
            .object(["id": .string("split_1"), "direction": .string("down"), "ratio": .number(0.5), "rect": rect(x: 50, y: 0, width: 50, height: 40)]),
        ]
    )

    static let oddCellCaptureFixture = simpleCaptureFixture(
        paneFacts: [
            ("rounded", "rounded-first", rect(x: 2, y: 0, width: 1, height: 10)),
            ("second", "second", rect(x: 3, y: 0, width: 2, height: 10)),
        ],
        splits: [
            .object(["id": .string("split_root"), "direction": .string("right"), "ratio": .number(0.5), "rect": rect(x: 0, y: 0, width: 5, height: 10)]),
        ]
    )

    static func captureFixture(
        cwds: [String?] = Array(repeating: "/tmp/bessie-capture", count: 4),
        includeSecondLayout: Bool = true
    ) -> HerdrSnapshot {
        let workspace = "live-workspace"
        let tabOne = "live-tab-one", tabTwo = "live-tab-two"
        let paneIDs = ["live-pane-one", "live-pane-two", "live-pane-three", "live-pane-four"]
        var layouts: [JSONValue] = [nestedLayout(workspace: workspace, tab: tabOne, panes: paneIDs)]
        if includeSecondLayout {
            layouts.append(.object([
                "workspace_id": .string(workspace), "tab_id": .string(tabTwo), "zoomed": .bool(false),
                "focused_pane_id": .string(paneIDs[3]),
                "panes": .array([.object([
                    "pane_id": .string(paneIDs[3]), "focused": .bool(false),
                    "rect": rect(x: 0, y: 0, width: 120, height: 40),
                ])]),
                "splits": .array([]),
            ]))
        }
        return HerdrSnapshot(
            version: "0.8.0", protocolVersion: 19,
            focusedWorkspaceID: workspace, focusedTabID: tabOne, focusedPaneID: paneIDs[1],
            workspaces: [.object([
                "workspace_id": .string(workspace), "number": .number(1), "label": .string("duplicate"),
                "focused": .bool(true), "pane_count": .number(4), "tab_count": .number(2),
                "active_tab_id": .string(tabOne), "agent_status": .string("idle"),
            ])],
            tabs: [
                tab(id: tabOne, workspace: workspace, number: 1, panes: 3),
                tab(id: tabTwo, workspace: workspace, number: 2, panes: 1),
            ],
            panes: paneIDs.enumerated().map { index, id in
                var value: [String: JSONValue] = [
                    "pane_id": .string(id), "terminal_id": .string("terminal-\(index)"),
                    "workspace_id": .string(workspace), "tab_id": .string(index == 3 ? tabTwo : tabOne),
                    "focused": .bool(index == 1), "label": .string("duplicate"),
                    "agent_status": .string("idle"), "revision": .number(Double(index + 1)),
                ]
                if let cwd = cwds[index] { value["cwd"] = .string(cwd) }
                return .object(value)
            },
            layouts: layouts,
            agents: []
        )
    }

    static func tab(id: String, workspace: String, number: Double, panes: Double) -> JSONValue {
        .object([
            "tab_id": .string(id), "workspace_id": .string(workspace), "number": .number(number),
            "label": .string("duplicate"), "focused": .bool(number == 1), "pane_count": .number(panes),
            "agent_status": .string("idle"),
        ])
    }

    static func simpleCaptureFixture(
        paneFacts: [(id: String, label: String, rect: JSONValue)],
        splits: [JSONValue]
    ) -> HerdrSnapshot {
        let workspace = "workspace", tabID = "tab"
        return HerdrSnapshot(
            version: "0.8.0", protocolVersion: 19,
            focusedWorkspaceID: workspace, focusedTabID: tabID, focusedPaneID: paneFacts[0].id,
            workspaces: [.object([
                "workspace_id": .string(workspace), "number": .number(1), "label": .string("Captured"),
                "focused": .bool(true), "pane_count": .number(Double(paneFacts.count)), "tab_count": .number(1),
                "active_tab_id": .string(tabID), "agent_status": .string("idle"),
            ])],
            tabs: [tab(id: tabID, workspace: workspace, number: 1, panes: Double(paneFacts.count))],
            panes: paneFacts.enumerated().map { index, fact in .object([
                "pane_id": .string(fact.id), "terminal_id": .string("terminal-\(index)"),
                "workspace_id": .string(workspace), "tab_id": .string(tabID), "focused": .bool(index == 0),
                "label": .string(fact.label), "agent_status": .string("idle"), "revision": .number(Double(index + 1)),
                "cwd": .string("/tmp/bessie-capture"),
            ]) },
            layouts: [.object([
                "workspace_id": .string(workspace), "tab_id": .string(tabID), "zoomed": .bool(false),
                "focused_pane_id": .string(paneFacts[0].id),
                "panes": .array(paneFacts.enumerated().map { index, fact in .object([
                    "pane_id": .string(fact.id), "focused": .bool(index == 0), "rect": fact.rect,
                ]) }),
                "splits": .array(splits),
            ])],
            agents: []
        )
    }

    static func nestedLayout(workspace: String, tab: String, panes: [String]) -> JSONValue {
        .object([
            "workspace_id": .string(workspace), "tab_id": .string(tab), "zoomed": .bool(false),
            "focused_pane_id": .string(panes[1]),
            "panes": .array([
                .object(["pane_id": .string(panes[0]), "focused": .bool(false), "rect": rect(x: 0, y: 0, width: 39, height: 29)]),
                .object(["pane_id": .string(panes[1]), "focused": .bool(true), "rect": rect(x: 0, y: 31, width: 39, height: 9)]),
                .object(["pane_id": .string(panes[2]), "focused": .bool(false), "rect": rect(x: 41, y: 0, width: 79, height: 40)]),
            ]),
            "splits": .array([
                .object(["id": .string("split_root"), "direction": .string("right"), "ratio": .number(1.0 / 3.0), "rect": rect(x: 0, y: 0, width: 120, height: 40)]),
                .object(["id": .string("split_0"), "direction": .string("down"), "ratio": .number(0.75), "rect": rect(x: 0, y: 0, width: 40, height: 40)]),
            ]),
        ])
    }

    static func rect(x: Double, y: Double, width: Double, height: Double) -> JSONValue {
        .object(["x": .number(x), "y": .number(y), "width": .number(width), "height": .number(height)])
    }
}
