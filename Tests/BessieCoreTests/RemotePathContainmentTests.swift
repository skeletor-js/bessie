import XCTest
@testable import BessieCore

final class RemotePathContainmentTests: XCTestCase {
    func testAbsolutePathRejectsEscapeAndAcceptsNested() throws {
        let root = WorkspaceFileRoot(
            connectionID: "ssh",
            workspaceID: "w1",
            rootURL: URL(fileURLWithPath: "/home/me/project", isDirectory: true),
            gitTopLevel: nil,
            resolution: .herdrCwd,
            remote: SSHRemoteFileAccess(host: "box", controlPath: "/tmp/c.sock")
        )
        XCTAssertEqual(try WorkspaceFS.absolutePath(root: root, relativePath: "src/a.swift").get(), "/home/me/project/src/a.swift")
        XCTAssertThrowsError(try WorkspaceFS.absolutePath(root: root, relativePath: "../secret").get())
        XCTAssertThrowsError(try WorkspaceFS.absolutePath(root: root, relativePath: "/etc/passwd").get())
        XCTAssertEqual(try WorkspaceFS.absolutePath(root: root, relativePath: "").get(), "/home/me/project")
    }

    func testResolveRootRemoteRequiresAccess() {
        let connection = BessieConnectionDefinition(name: "Remote", kind: .ssh, sshHost: "box", session: "bessie")
        let result = WorkspaceFS.resolveRoot(connection: connection, projection: nil, remoteAccess: nil)
        guard case .failure(.remoteUnsupported) = result else {
            return XCTFail("expected remoteUnsupported")
        }
    }

    func testContainedRemoteReadIsBoundedAndRejectsSymlinkEscape() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-remote-read-\(UUID().uuidString)", isDirectory: true)
        let root = directory.appendingPathComponent("root", isDirectory: true)
        let outside = directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data(repeating: 0x5a, count: 256 * 1_024)
        try payload.write(to: root.appendingPathComponent("image.png"))
        try payload.write(to: outside.appendingPathComponent("secret.png"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.png"),
            withDestinationURL: outside.appendingPathComponent("secret.png")
        )
        let fakeSSH = directory.appendingPathComponent("ssh")
        try Data("#!/bin/sh\nexec /bin/sh -s\n".utf8).write(to: fakeSSH)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeSSH.path)
        let client = SSHRemoteFileClient(access: SSHRemoteFileAccess(
            host: "fixture",
            controlPath: "/tmp/unused",
            sshExecutablePath: fakeSSH.path
        ))

        XCTAssertEqual(
            try client.readContainedFile(
                rootPath: root.path,
                relativePath: "image.png",
                maximumByteSize: payload.count
            ),
            payload
        )
        XCTAssertThrowsError(try client.readContainedFile(
            rootPath: root.path,
            relativePath: "image.png",
            maximumByteSize: payload.count - 1
        )) {
            XCTAssertEqual($0 as? WorkspacePathError, .tooLarge)
        }
        XCTAssertThrowsError(try client.readContainedFile(
            rootPath: root.path,
            relativePath: "escape.png",
            maximumByteSize: payload.count
        )) {
            XCTAssertEqual($0 as? WorkspacePathError, .pathEscape)
        }
    }
}
