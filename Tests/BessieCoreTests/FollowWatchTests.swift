import Foundation
import XCTest
@testable import BessieCore

final class FollowWatchTests: XCTestCase {
    func testTouchStateFollowsLatestUnlessPinnedAndCapsRecencyList() {
        var state = FollowTouchState(maximumCount: 3)
        state.record(.init(relativePath: "a.txt", touchedAt: Date(timeIntervalSince1970: 1), kind: .added))
        state.record(.init(relativePath: "b.txt", touchedAt: Date(timeIntervalSince1970: 2), kind: .modified))
        state.pin("a.txt")
        state.record(.init(relativePath: "c.txt", touchedAt: Date(timeIntervalSince1970: 3), kind: .added))

        XCTAssertEqual(state.selectedPath, "a.txt")
        XCTAssertEqual(state.touchedPaths.map(\.relativePath), ["c.txt", "b.txt", "a.txt"])

        state.pin(nil)
        state.record(.init(relativePath: "d.txt", touchedAt: Date(timeIntervalSince1970: 4), kind: .deleted))
        XCTAssertEqual(state.selectedPath, "d.txt")
        XCTAssertEqual(state.touchedPaths.map(\.relativePath), ["d.txt", "c.txt", "b.txt"])
    }

    func testRecordingSamePathCoalescesAndUpdatesRecency() {
        var state = FollowTouchState()
        state.record(.init(relativePath: "file.txt", touchedAt: Date(timeIntervalSince1970: 1), kind: .added))
        state.record(.init(relativePath: "file.txt", touchedAt: Date(timeIntervalSince1970: 2), kind: .modified))

        XCTAssertEqual(state.touchedPaths.count, 1)
        XCTAssertEqual(state.touchedPaths.first?.changeKind, .modified)
        XCTAssertEqual(state.touchedPaths.first?.lastTouchedAt, Date(timeIntervalSince1970: 2))
    }

    func testWatcherSuppressesInitialSnapshotAndReportsAddModifyDelete() async throws {
        try await withTemporaryDirectory { directory in
            let existing = directory.appendingPathComponent("existing.txt")
            try Data("initial".utf8).write(to: existing)
            let watcher = WorkspaceFileWatcher(root: Self.root(directory), pollingInterval: .milliseconds(100))
            let events = await watcher.start()
            let collector = Task { () -> [WorkspaceFileChange] in
                var result: [WorkspaceFileChange] = []
                for await batch in events {
                    result.append(contentsOf: batch)
                    if result.contains(where: { $0.relativePath == "added.txt" && $0.kind == .deleted }) { break }
                }
                return result
            }

            try await Task.sleep(for: .milliseconds(250))
            XCTAssertFalse(collector.isCancelled)
            let added = directory.appendingPathComponent("added.txt")
            try Data("one".utf8).write(to: added)
            try await Task.sleep(for: .milliseconds(250))
            try Data("two, changed".utf8).write(to: added)
            try await Task.sleep(for: .milliseconds(250))
            try FileManager.default.removeItem(at: added)

            let changes = try await withThrowingTaskGroup(of: [WorkspaceFileChange].self) { group in
                group.addTask { await collector.value }
                group.addTask {
                    try await Task.sleep(for: .seconds(3))
                    throw TimeoutError()
                }
                let value = try await group.next()!
                group.cancelAll()
                return value
            }
            await watcher.stop()

            XCTAssertFalse(changes.contains { $0.relativePath == "existing.txt" })
            XCTAssertTrue(changes.contains { $0.relativePath == "added.txt" && $0.kind == .added })
            XCTAssertTrue(changes.contains { $0.relativePath == "added.txt" && $0.kind == .modified })
            XCTAssertTrue(changes.contains { $0.relativePath == "added.txt" && $0.kind == .deleted })
        }
    }

    func testWatcherIgnoresSharedDirectories() async throws {
        try await withTemporaryDirectory { directory in
            let watcher = WorkspaceFileWatcher(root: Self.root(directory), pollingInterval: .milliseconds(75))
            let events = await watcher.start()
            try await Task.sleep(for: .milliseconds(150))
            let ignored = directory.appendingPathComponent("node_modules/package", isDirectory: true)
            try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
            try Data("ignored".utf8).write(to: ignored.appendingPathComponent("index.js"))

            let received = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await batch in events where !batch.isEmpty { return true }
                    return false
                }
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(350))
                    return false
                }
                let value = await group.next()!
                group.cancelAll()
                return value
            }
            await watcher.stop()
            XCTAssertFalse(received)
        }
    }

    private struct TimeoutError: Error {}

    private static func root(_ url: URL) -> WorkspaceFileRoot {
        .init(connectionID: "local", workspaceID: "workspace", rootURL: url, gitTopLevel: nil, resolution: .herdrCwd)
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }
}
