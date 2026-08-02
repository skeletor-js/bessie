import BessieCore
import Foundation
import XCTest
@testable import BessieApp

@MainActor
final class FollowFilesViewModelTests: XCTestCase {
    func testConfigureRestartsTheStretchWhenTheSamePaneChangesDirectory() throws {
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let model = FollowFilesViewModel()

        model.configure(
            connection: .localBessie,
            projection: try projection(cwd: first.path),
            paneID: "pane"
        )
        XCTAssertEqual(model.stretch?.root.rootURL, first.resolvingSymlinksInPath())

        model.configure(
            connection: .localBessie,
            projection: try projection(cwd: second.path),
            paneID: "pane"
        )
        XCTAssertEqual(model.stretch?.root.rootURL, second.resolvingSymlinksInPath())
        model.stop()
    }

    func testRemoteConnectionDoesNotStartAWatchStretch() throws {
        let remote = try BessieConnectionDefinition(
            id: "remote",
            name: "Remote",
            kind: .ssh,
            sshHost: "remote"
        ).validated()
        let model = FollowFilesViewModel()

        model.configure(connection: remote, projection: try projection(cwd: "/tmp"), paneID: "pane")

        XCTAssertEqual(model.availability, .remoteUnsupported)
        XCTAssertNil(model.stretch)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-follow-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func projection(cwd: String) throws -> HerdrSessionProjection {
        try HerdrSessionProjection(snapshot: HerdrSnapshot(
            version: "0.7.5",
            protocolVersion: 17,
            focusedWorkspaceID: "workspace",
            focusedTabID: "tab",
            focusedPaneID: "pane",
            workspaces: [.object([
                "workspace_id": .string("workspace"),
                "number": .number(1),
                "label": .string("Workspace"),
                "focused": .bool(true),
                "pane_count": .number(1),
                "tab_count": .number(1),
                "active_tab_id": .string("tab"),
                "agent_status": .string("working"),
            ])],
            tabs: [.object([
                "tab_id": .string("tab"),
                "workspace_id": .string("workspace"),
                "number": .number(1),
                "label": .string("Tab"),
                "focused": .bool(true),
                "pane_count": .number(1),
                "agent_status": .string("working"),
            ])],
            panes: [.object([
                "pane_id": .string("pane"),
                "terminal_id": .string("terminal"),
                "workspace_id": .string("workspace"),
                "tab_id": .string("tab"),
                "focused": .bool(true),
                "cwd": .string(cwd),
                "agent_status": .string("working"),
                "revision": .number(1),
            ])],
            layouts: [],
            agents: []
        ))
    }
}
