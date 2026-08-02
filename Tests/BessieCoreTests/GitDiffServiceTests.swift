import Foundation
import XCTest
@testable import BessieCore

final class GitDiffServiceTests: XCTestCase {
    func testNoGitShowsFullFileAsAddedWithHonestBanner() throws {
        try withTemporaryDirectory { directory in
            try Data("hello\n".utf8).write(to: directory.appendingPathComponent("note.txt"))
            let preview = GitDiffService().preview(root: Self.root(directory), relativePath: "note.txt")

            XCTAssertEqual(preview.kind, .text)
            XCTAssertEqual(preview.banner, "No git baseline")
            XCTAssertTrue(preview.text?.contains("+hello") == true)
        }
    }

    func testPathEscapeFailsClosedIncludingDeletedPaths() throws {
        try withTemporaryDirectory { directory in
            let preview = GitDiffService().preview(root: Self.root(directory), relativePath: "../outside.txt")
            XCTAssertEqual(preview.kind, .unavailable)
            XCTAssertEqual(preview.banner, "Path is outside the workspace")
        }
    }

    func testGitHEADPreviewIncludesTrackedModifiedDeletedAndUntrackedFiles() throws {
        try withTemporaryDirectory { directory in
            try runGit(["init", "-q"], at: directory)
            try runGit(["config", "user.email", "tests@example.com"], at: directory)
            try runGit(["config", "user.name", "Tests"], at: directory)
            try Data("before\n".utf8).write(to: directory.appendingPathComponent("modified.txt"))
            try Data("remove me\n".utf8).write(to: directory.appendingPathComponent("deleted.txt"))
            try runGit(["add", "."], at: directory)
            try runGit(["commit", "-qm", "baseline"], at: directory)
            try Data("after\n".utf8).write(to: directory.appendingPathComponent("modified.txt"))
            try FileManager.default.removeItem(at: directory.appendingPathComponent("deleted.txt"))
            try Data("new\n".utf8).write(to: directory.appendingPathComponent("untracked.txt"))
            let root = Self.root(directory, gitTopLevel: directory)
            let service = GitDiffService()

            XCTAssertTrue(service.preview(root: root, relativePath: "modified.txt").text?.contains("+after") == true)
            XCTAssertTrue(service.preview(root: root, relativePath: "deleted.txt").text?.contains("-remove me") == true)
            XCTAssertTrue(service.preview(root: root, relativePath: "untracked.txt").text?.contains("+new") == true)
        }
    }

    func testBinaryAndOversizedFilesDegradeHonestly() throws {
        try withTemporaryDirectory { directory in
            try Data([0, 1, 2]).write(to: directory.appendingPathComponent("binary.dat"))
            try Data(repeating: 65, count: 32).write(to: directory.appendingPathComponent("large.txt"))
            let service = GitDiffService(maximumTextBytes: 16)

            XCTAssertEqual(service.preview(root: Self.root(directory), relativePath: "binary.dat").kind, .binary)
            XCTAssertEqual(service.preview(root: Self.root(directory), relativePath: "large.txt").kind, .unavailable)
        }
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private static func root(_ url: URL, gitTopLevel: URL? = nil) -> WorkspaceFileRoot {
        .init(connectionID: "local", workspaceID: "workspace", rootURL: url, gitTopLevel: gitTopLevel, resolution: .herdrCwd)
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
