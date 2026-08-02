import Foundation
import XCTest
@testable import BessieCore

final class WorkspaceFSTests: XCTestCase {
    func testResolveRootUsesConsensusCWDAndFindsGitTopLevel() throws {
        try withTemporaryDirectory { directory in
            let repository = directory.appendingPathComponent("repository", isDirectory: true)
            let nested = repository.appendingPathComponent("Sources/Feature", isDirectory: true)
            try FileManager.default.createDirectory(at: repository.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let projection = try Self.projection(cwds: [nested.path, nested.path])

            let root = try WorkspaceFS.resolveRoot(
                connection: .localBessie,
                projection: projection,
                workspaceID: "workspace"
            ).get()

            XCTAssertEqual(root.connectionID, BessieConnectionDefinition.localBessie.id)
            XCTAssertEqual(root.workspaceID, "workspace")
            XCTAssertEqual(root.rootURL, nested.resolvingSymlinksInPath())
            XCTAssertEqual(root.gitTopLevel, repository.resolvingSymlinksInPath())
            XCTAssertEqual(root.resolution, .herdrCwd)
        }
    }

    func testResolveRootFallsBackToSelectedPaneCWDWhenWorkspaceCWDsDiffer() throws {
        try withTemporaryDirectory { directory in
            let first = directory.appendingPathComponent("first", isDirectory: true)
            let second = directory.appendingPathComponent("second", isDirectory: true)
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            let projection = try Self.projection(cwds: [first.path, second.path])

            let root = try WorkspaceFS.resolveRoot(
                connection: .localBessie,
                projection: projection,
                paneID: "pane-2",
                workspaceID: "workspace"
            ).get()

            XCTAssertEqual(root.rootURL, second.resolvingSymlinksInPath())
            XCTAssertEqual(root.resolution, .selectedPaneCwd)
        }
    }

    func testResolveRootRejectsStaleOrContradictoryPaneSelection() throws {
        try withTemporaryDirectory { directory in
            let projection = try Self.projection(cwds: [directory.path])

            XCTAssertEqual(
                WorkspaceFS.resolveRoot(
                    connection: .localBessie,
                    projection: projection,
                    paneID: "missing-pane"
                ),
                .failure(.missingRoot)
            )
            XCTAssertEqual(
                WorkspaceFS.resolveRoot(
                    connection: .localBessie,
                    projection: projection,
                    paneID: "pane-1",
                    workspaceID: "different-workspace"
                ),
                .failure(.missingRoot)
            )
        }
    }

    func testResolveRootRejectsRemoteAndMissingOrInvalidCWDs() throws {
        let remote = BessieConnectionDefinition(name: "Remote", kind: .ssh, sshHost: "hermes")
        XCTAssertEqual(
            WorkspaceFS.resolveRoot(connection: remote, projection: nil),
            .failure(.remoteUnsupported)
        )

        let relative = try Self.projection(cwds: ["relative/path"])
        XCTAssertEqual(
            WorkspaceFS.resolveRoot(connection: .localBessie, projection: relative, workspaceID: "workspace"),
            .failure(.missingRoot)
        )
        let filesHome = try WorkspaceFS.resolveRoot(connection: .localBessie, projection: nil).get()
        XCTAssertEqual(filesHome.rootURL, FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath())
        XCTAssertEqual(filesHome.workspaceID, "files-home")
    }

    func testResolveRootRejectsFilesAndMissingDirectories() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("file.txt")
            try Data("text".utf8).write(to: file)

            XCTAssertEqual(
                WorkspaceFS.resolveRoot(
                    connection: .localBessie,
                    projection: try Self.projection(cwds: [file.path]),
                    workspaceID: "workspace"
                ),
                .failure(.notDirectory)
            )
            XCTAssertEqual(
                WorkspaceFS.resolveRoot(
                    connection: .localBessie,
                    projection: try Self.projection(cwds: [directory.appendingPathComponent("missing").path]),
                    workspaceID: "workspace"
                ),
                .failure(.notDirectory)
            )
        }
    }

    func testResolveFileAllowsDescendantsAndRejectsTraversalAndSiblingPrefix() throws {
        try withTemporaryDirectory { directory in
            let rootURL = directory.appendingPathComponent("root", isDirectory: true)
            let sibling = directory.appendingPathComponent("root-sibling", isDirectory: true)
            try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("nested"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            let file = rootURL.appendingPathComponent("nested/file.txt")
            let siblingFile = sibling.appendingPathComponent("outside.txt")
            try Data("inside".utf8).write(to: file)
            try Data("outside".utf8).write(to: siblingFile)
            let root = Self.root(rootURL)

            XCTAssertEqual(try WorkspaceFS.resolveFile(root: root, relativePath: "nested/file.txt").get(), file)
            XCTAssertEqual(
                WorkspaceFS.resolveFile(root: root, relativePath: "../root-sibling/outside.txt"),
                .failure(.pathEscape)
            )
            XCTAssertEqual(
                WorkspaceFS.resolveFile(root: root, relativePath: siblingFile.path),
                .failure(.pathEscape)
            )
            XCTAssertEqual(
                WorkspaceFS.resolveFile(root: root, relativePath: "nested/missing.txt"),
                .failure(.notFound)
            )
        }
    }

    func testResolveFileRejectsSymlinkEscapeButAllowsContainedSymlink() throws {
        try withTemporaryDirectory { directory in
            let rootURL = directory.appendingPathComponent("root", isDirectory: true)
            let outside = directory.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let insideFile = rootURL.appendingPathComponent("inside.txt")
            let outsideFile = outside.appendingPathComponent("outside.txt")
            try Data("inside".utf8).write(to: insideFile)
            try Data("outside".utf8).write(to: outsideFile)
            try FileManager.default.createSymbolicLink(
                at: rootURL.appendingPathComponent("inside-link.txt"),
                withDestinationURL: insideFile
            )
            try FileManager.default.createSymbolicLink(
                at: rootURL.appendingPathComponent("escape.txt"),
                withDestinationURL: outsideFile
            )
            let root = Self.root(rootURL)

            XCTAssertEqual(
                try WorkspaceFS.resolveFile(root: root, relativePath: "inside-link.txt").get(),
                insideFile.resolvingSymlinksInPath()
            )
            XCTAssertEqual(
                WorkspaceFS.resolveFile(root: root, relativePath: "escape.txt"),
                .failure(.pathEscape)
            )
        }
    }

    func testResolveContainedPathAllowsMissingLeafButRejectsMissingLeafBelowEscapingSymlink() throws {
        try withTemporaryDirectory { directory in
            let rootURL = directory.appendingPathComponent("root", isDirectory: true)
            let outside = directory.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("nested"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: rootURL.appendingPathComponent("escape"),
                withDestinationURL: outside
            )
            let root = Self.root(rootURL)

            XCTAssertEqual(
                try WorkspaceFS.resolveContainedPath(root: root, relativePath: "nested/new-file.md").get(),
                rootURL.appendingPathComponent("nested/new-file.md")
            )
            XCTAssertEqual(
                WorkspaceFS.resolveContainedPath(root: root, relativePath: "escape/new-file.md"),
                .failure(.pathEscape)
            )
        }
    }

    func testResolveContainedPathRejectsNestedSymlinkTargetWithMissingSuffix() throws {
        try withTemporaryDirectory { directory in
            let rootURL = directory.appendingPathComponent("root", isDirectory: true)
            let outside = directory.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: rootURL.appendingPathComponent("bridge"),
                withDestinationURL: outside
            )
            try FileManager.default.createSymbolicLink(
                atPath: rootURL.appendingPathComponent("redirect").path,
                withDestinationPath: "bridge/missing"
            )

            XCTAssertEqual(
                WorkspaceFS.resolveContainedPath(
                    root: Self.root(rootURL),
                    relativePath: "redirect/new-file.md"
                ),
                .failure(.pathEscape)
            )
        }
    }

    func testResolveContainedPathTreatsTildeSymlinkTargetAsRelativePOSIXPath() throws {
        try withTemporaryDirectory { directory in
            let rootURL = directory.appendingPathComponent("root", isDirectory: true)
            let tildeDirectory = rootURL.appendingPathComponent("~", isDirectory: true)
            try FileManager.default.createDirectory(at: tildeDirectory, withIntermediateDirectories: true)
            let file = tildeDirectory.appendingPathComponent("inside.txt")
            try Data("inside".utf8).write(to: file)
            try FileManager.default.createSymbolicLink(
                atPath: rootURL.appendingPathComponent("link.txt").path,
                withDestinationPath: "~/inside.txt"
            )

            XCTAssertEqual(
                try WorkspaceFS.resolveFile(root: Self.root(rootURL), relativePath: "link.txt").get(),
                file
            )
        }
    }

    func testResolveContainedPathRejectsRootReplacedByOutsideSymlink() throws {
        try withTemporaryDirectory { directory in
            let rootURL = directory.appendingPathComponent("root", isDirectory: true)
            let movedRoot = directory.appendingPathComponent("moved-root", isDirectory: true)
            let outside = directory.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try Data("outside".utf8).write(to: outside.appendingPathComponent("file.txt"))
            let root = Self.root(rootURL)
            try FileManager.default.moveItem(at: rootURL, to: movedRoot)
            try FileManager.default.createSymbolicLink(at: rootURL, withDestinationURL: outside)

            XCTAssertEqual(
                WorkspaceFS.resolveContainedPath(root: root, relativePath: "file.txt"),
                .failure(.pathEscape)
            )
        }
    }

    func testSharedIgnoreRulesMatchDirectoryComponentsOnly() {
        for path in [
            ".git/config",
            "nested/node_modules/package/index.js",
            ".build/debug/Bessie",
            "project/DerivedData/Build/output",
        ] {
            XCTAssertTrue(WorkspaceFS.isIgnoredRelativePath(path), path)
        }

        for path in [
            "git/config",
            "node_modules.txt",
            "build/output",
            "DerivedDataReport.md",
            "Sources/.github/workflows/check.yml",
        ] {
            XCTAssertFalse(WorkspaceFS.isIgnoredRelativePath(path), path)
        }
    }

    func testFileMetadataClassifiesKindsAndDetectsBinaryContent() throws {
        try withTemporaryDirectory { directory in
            let markdown = directory.appendingPathComponent("README.md")
            let image = directory.appendingPathComponent("preview.png")
            let video = directory.appendingPathComponent("clip.mp4")
            let text = directory.appendingPathComponent("notes.unknown")
            let binary = directory.appendingPathComponent("payload.unknown")
            let binaryMarkdown = directory.appendingPathComponent("binary.md")
            try Data("# Bessie".utf8).write(to: markdown)
            try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
            try Data([0, 0, 0, 0x18]).write(to: video)
            try Data("plain UTF-8 text".utf8).write(to: text)
            try Data([0x41, 0, 0x42]).write(to: binary)
            try Data([0x41, 0, 0x42]).write(to: binaryMarkdown)
            let root = Self.root(directory)

            let markdownMeta = try WorkspaceFS.fileMeta(root: root, relativePath: "README.md").get()
            XCTAssertEqual(markdownMeta.kind, .markdown)
            XCTAssertEqual(markdownMeta.byteSize, 8)
            XCTAssertEqual(markdownMeta.contentType, "text/markdown")
            XCTAssertEqual(try WorkspaceFS.fileMeta(root: root, relativePath: "preview.png").get().kind, .image)
            XCTAssertEqual(try WorkspaceFS.fileMeta(root: root, relativePath: "clip.mp4").get().kind, .video)
            XCTAssertEqual(try WorkspaceFS.fileMeta(root: root, relativePath: "notes.unknown").get().kind, .text)
            XCTAssertEqual(try WorkspaceFS.fileMeta(root: root, relativePath: "payload.unknown").get().kind, .binary)
            XCTAssertEqual(try WorkspaceFS.fileMeta(root: root, relativePath: "binary.md").get().kind, .binary)
            XCTAssertEqual(try WorkspaceFS.fileMeta(root: root, relativePath: "").get().kind, .directory)
        }
    }

    func testFileMetadataAppliesOptionalSizeLimit() throws {
        try withTemporaryDirectory { directory in
            try Data("too large".utf8).write(to: directory.appendingPathComponent("file.txt"))

            XCTAssertEqual(
                WorkspaceFS.fileMeta(root: Self.root(directory), relativePath: "file.txt", maximumByteSize: 3),
                .failure(.tooLarge)
            )
        }
    }

    private static func root(_ url: URL) -> WorkspaceFileRoot {
        WorkspaceFileRoot(
            connectionID: BessieConnectionDefinition.localBessie.id,
            workspaceID: "workspace",
            rootURL: url.resolvingSymlinksInPath(),
            gitTopLevel: nil,
            resolution: .herdrCwd
        )
    }

    private static func projection(cwds: [String?]) throws -> HerdrSessionProjection {
        let workspaceID = "workspace"
        let tabID = "tab"
        return try HerdrSessionProjection(snapshot: HerdrSnapshot(
            version: "0.7.5",
            protocolVersion: 17,
            focusedWorkspaceID: workspaceID,
            focusedTabID: tabID,
            focusedPaneID: "pane-1",
            workspaces: [.object([
                "workspace_id": .string(workspaceID),
                "number": .number(1),
                "label": .string("Workspace"),
                "focused": .bool(true),
                "pane_count": .number(Double(cwds.count)),
                "tab_count": .number(1),
                "active_tab_id": .string(tabID),
                "agent_status": .string("idle"),
            ])],
            tabs: [.object([
                "tab_id": .string(tabID),
                "workspace_id": .string(workspaceID),
                "number": .number(1),
                "label": .string("Tab"),
                "focused": .bool(true),
                "pane_count": .number(Double(cwds.count)),
                "agent_status": .string("idle"),
            ])],
            panes: cwds.enumerated().map { index, cwd in
                var pane: [String: JSONValue] = [
                    "pane_id": .string("pane-\(index + 1)"),
                    "terminal_id": .string("terminal-\(index + 1)"),
                    "workspace_id": .string(workspaceID),
                    "tab_id": .string(tabID),
                    "focused": .bool(index == 0),
                    "agent_status": .string("idle"),
                    "revision": .number(Double(index + 1)),
                ]
                if let cwd { pane["cwd"] = .string(cwd) }
                return .object(pane)
            },
            layouts: [],
            agents: []
        ))
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-workspace-fs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
