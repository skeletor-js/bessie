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
}
