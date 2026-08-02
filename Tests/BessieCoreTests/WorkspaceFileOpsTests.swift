import Foundation
import XCTest
@testable import BessieCore

final class WorkspaceFileOpsTests: XCTestCase {
    func testListingSortsDirectoriesFirstAndCapsResults() throws {
        try withRoot { root in
            try FileManager.default.createDirectory(at: root.rootURL.appendingPathComponent("z-dir"), withIntermediateDirectories: true)
            try Data("a".utf8).write(to: root.rootURL.appendingPathComponent("a.txt"))
            try Data("b".utf8).write(to: root.rootURL.appendingPathComponent("b.txt"))

            let items = try WorkspaceFileOps.list(root: root, limit: 2)

            XCTAssertEqual(items.map(\.relativePath), ["z-dir", "a.txt"])
            XCTAssertTrue(items[0].isDirectory)
        }
    }

    func testMarkdownSaveIsAtomicAndRejectsStaleRevision() throws {
        try withRoot { root in
            let url = root.rootURL.appendingPathComponent("README.md")
            try Data("first".utf8).write(to: url)
            let document = try WorkspaceFileOps.loadText(root: root, relativePath: "README.md")

            let saved = try WorkspaceFileOps.saveMarkdown(root: root, relativePath: "README.md", text: "second", expected: document.revision)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second")
            XCTAssertNotEqual(saved, document.revision)

            try Data("external edit".utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
            XCTAssertThrowsError(try WorkspaceFileOps.saveMarkdown(root: root, relativePath: "README.md", text: "mine", expected: saved)) {
                XCTAssertEqual($0 as? WorkspaceFileOperationError, .staleRevision)
            }
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external edit")
        }
    }

    func testMoveRejectsEscapeAndDeleteUsesInjectedTrash() throws {
        try withRoot { root in
            let source = root.rootURL.appendingPathComponent("note.md")
            try Data("note".utf8).write(to: source)
            XCTAssertThrowsError(try WorkspaceFileOps.move(root: root, from: "note.md", to: "../outside.md")) {
                XCTAssertEqual($0 as? WorkspacePathError, .pathEscape)
            }

            var trashed: URL?
            try WorkspaceFileOps.delete(root: root, relativePath: "note.md") { url in
                trashed = url
                try FileManager.default.removeItem(at: url)
            }
            XCTAssertEqual(trashed, source)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testMutationsRejectContainedSymbolicLinks() throws {
        try withRoot { root in
            let target = root.rootURL.appendingPathComponent("target.md")
            let link = root.rootURL.appendingPathComponent("link.md")
            try Data("target".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let item = try XCTUnwrap(WorkspaceFileOps.list(root: root).first { $0.name == "link.md" })
            XCTAssertTrue(item.isSymbolicLink)
            XCTAssertThrowsError(try WorkspaceFileOps.move(root: root, from: "link.md", to: "renamed.md")) {
                XCTAssertEqual($0 as? WorkspaceFileOperationError, .symbolicLinkUnsupported)
            }
            XCTAssertThrowsError(try WorkspaceFileOps.delete(root: root, relativePath: "link.md") { _ in }) {
                XCTAssertEqual($0 as? WorkspaceFileOperationError, .symbolicLinkUnsupported)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        }
    }

    private func withRoot(_ body: (WorkspaceFileRoot) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bessie-file-ops-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(WorkspaceFileRoot(connectionID: "local", workspaceID: "workspace", rootURL: url, gitTopLevel: nil, resolution: .herdrCwd))
    }
}
