import Foundation
import XCTest
@testable import BessieCore

final class RemoteOnboardingBootstrapTests: XCTestCase {
    func testCollisionRefusesBeforePathRegistrationOrAttach() throws {
        let fake = FakeRemoteBootstrap(commands: [.init(exitCode: 0, stdout: Self.sessions("bessie-new"))])
        XCTAssertThrowsError(try fake.bootstrap().bootstrap(definition: Self.connection, path: "/srv/work", sessionName: "bessie-new")) {
            XCTAssertEqual($0 as? RemoteBootstrapError, .collision("bessie-new"))
        }
        XCTAssertEqual(fake.attachCount, 0); XCTAssertEqual(fake.registered.count, 0)
    }

    func testAuthOrUnknownFailureIsNotTreatedAsAbsence() throws {
        for code in [Int32(255), 127] {
            let fake = FakeRemoteBootstrap(commands: [.init(exitCode: code, stderr: Data("denied".utf8))])
            XCTAssertThrowsError(try fake.bootstrap().bootstrap(definition: Self.connection, path: "/srv/work", sessionName: "bessie-new")) {
                guard case .commandFailed = $0 as? RemoteBootstrapError else { return XCTFail("unexpected \($0)") }
            }
            XCTAssertEqual(fake.attachCount, 0)
        }
    }

    func testPathValidationFailureDoesNotRegisterOrAttachAndPathTravelsOnStdin() throws {
        let fake = FakeRemoteBootstrap(commands: [.init(exitCode: 0, stdout: Self.sessions()), .init(exitCode: 20)])
        XCTAssertThrowsError(try fake.bootstrap().bootstrap(definition: Self.connection, path: "/srv/a; touch /tmp/no", sessionName: "bessie-new")) {
            XCTAssertEqual($0 as? RemoteBootstrapError, .invalidPath("/srv/a; touch /tmp/no"))
        }
        XCTAssertEqual(fake.inputs.last, Data("/srv/a; touch /tmp/no\n".utf8))
        XCTAssertFalse(fake.arguments.last!.last!.contains("touch /tmp/no"))
        XCTAssertTrue(fake.arguments.last!.contains("BatchMode=yes")); XCTAssertTrue(fake.arguments.last!.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(fake.registered.isEmpty); XCTAssertEqual(fake.attachCount, 0)
    }

    func testPathValidationScriptExecutesPortablyWithoutEvaluatingPathBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let marker = root.appendingPathComponent("injected")
        let directory = root.appendingPathComponent("workspace;$(touch injected) 'quoted'")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(try executePathValidation(input: "\(directory.path)\n", currentDirectory: root), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testEmbeddedNewlineIsRejectedByShellAndBeforeBootstrapSideEffects() throws {
        XCTAssertEqual(try executePathValidation(input: "/tmp\n/definitely-not-a-directory\n"), 20)

        let fake = FakeRemoteBootstrap(commands: [
            .init(exitCode: 0, stdout: Self.sessions()),
            .init(exitCode: 20),
        ])
        XCTAssertThrowsError(try fake.bootstrap().bootstrap(
            definition: Self.connection,
            path: "/tmp\n/definitely-not-a-directory",
            sessionName: "bessie-new"
        )) {
            XCTAssertEqual($0 as? OnboardingPersistenceError, .pathMustBeAbsolute)
        }
        XCTAssertTrue(fake.arguments.isEmpty)
        XCTAssertTrue(fake.registered.isEmpty)
        XCTAssertEqual(fake.attachCount, 0)
    }

    func testAttachUsesForcedPTYAndSelectedCWDWaitsForDetachedThenStopsBeforeContinuedProof() throws {
        let fake = FakeRemoteBootstrap(commands: [
            .init(exitCode: 0, stdout: Self.sessions()), .init(exitCode: 0),
            .init(exitCode: 0, stdout: Self.status(detached: false)),
            .init(exitCode: 0, stdout: Self.status(detached: true)),
            .init(exitCode: 0, stdout: Self.status(detached: true)),
        ], snapshot: Self.snapshot())
        let result = try fake.bootstrap().bootstrap(definition: Self.connection, path: "/srv/my work", sessionName: "bessie-new")
        XCTAssertEqual(result.workspaceID, "w1"); XCTAssertEqual(result.tabID, "t1"); XCTAssertEqual(result.paneID, "p1")
        XCTAssertEqual(fake.registered.map(\.session), ["bessie-new"])
        XCTAssertTrue(fake.attachArguments.contains("-tt"))
        XCTAssertEqual(fake.attachArguments.last, "cd -- '/srv/my work' && exec herdr session attach bessie-new")
        XCTAssertEqual(fake.events.suffix(2), ["process.stop", "snapshot"])
    }

    func testRejectsExtraOrIncorrectParentTopology() throws {
        for snapshot in [Self.snapshot(extraPane: true), Self.snapshot(tabWorkspace: "wrong")] {
            let fake = FakeRemoteBootstrap(commands: Self.successCommands, snapshot: snapshot)
            XCTAssertThrowsError(try fake.bootstrap().bootstrap(definition: Self.connection, path: "/srv/my work", sessionName: "bessie-new")) {
                XCTAssertEqual($0 as? RemoteBootstrapError, .ambiguousTopology)
            }
        }
    }

    func testResumeWithExactPendingIDsOnlyReconcilesAndDoesNotAttachAgain() throws {
        let fake = FakeRemoteBootstrap(commands: [], snapshot: Self.snapshot())
        let result = try fake.bootstrap().bootstrap(definition: Self.connection, path: "/srv/my work", sessionName: "bessie-new",
                                                    expectedIDs: ("w1", "t1", "p1"))
        XCTAssertEqual(result.paneID, "p1"); XCTAssertEqual(fake.attachCount, 0); XCTAssertTrue(fake.arguments.isEmpty)
    }

    private static let connection = BessieConnectionDefinition(id: "remote", name: "Remote", kind: .ssh, sshHost: "studio")

    private func executePathValidation(input bytes: String, currentDirectory: URL? = nil) throws -> Int32 {
        let script = try XCTUnwrap(RemoteOnboardingBootstrap.pathValidationArguments(host: "studio").last)
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = currentDirectory
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(bytes.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static let successCommands: [RemoteBootstrapCommandResult] = [
        .init(exitCode: 0, stdout: sessions()), .init(exitCode: 0), .init(exitCode: 0, stdout: status(detached: true)),
        .init(exitCode: 0, stdout: status(detached: true)),
    ]
    private static func status(detached: Bool) -> Data {
        Data(#"{"server":{"running":true,"version":"0.8.0","protocol":19,"session":"bessie-new","capabilities":{"live_handoff":true,"detached_server_daemon":\#(detached)}}}"#.utf8)
    }
    private static func sessions(_ names: String...) -> Data {
        let rows = names.map { #"{"name":"\#($0)","default":false,"running":true,"socket_path":"/tmp/x","session_dir":"/tmp/y"}"# }.joined(separator: ",")
        return Data("{\"sessions\":[\(rows)]}".utf8)
    }
    fileprivate static func snapshot(extraPane: Bool = false, tabWorkspace: String = "w1") -> HerdrSnapshot {
        var panes: [JSONValue] = [.object(["pane_id": .string("p1"), "terminal_id": .string("term1"),
            "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(true),
            "cwd": .string("/srv/my work"), "agent_status": .string("idle"), "revision": .number(1)])]
        if extraPane { panes.append(panes[0]) }
        return HerdrSnapshot(version: "0.8.0", protocolVersion: 19, focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p1",
            workspaces: [.object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("work"), "focused": .bool(true),
                "pane_count": .number(Double(panes.count)), "tab_count": .number(1), "active_tab_id": .string("t1"), "agent_status": .string("idle")])],
            tabs: [.object(["tab_id": .string("t1"), "workspace_id": .string(tabWorkspace), "number": .number(1), "label": .string("tab"),
                "focused": .bool(true), "pane_count": .number(Double(panes.count)), "agent_status": .string("idle")])],
            panes: panes, layouts: [], agents: [])
    }
}

private final class FakeRemoteBootstrap: @unchecked Sendable {
    var commands: [RemoteBootstrapCommandResult]
    var suppliedSnapshot: HerdrSnapshot
    var arguments: [[String]] = []; var inputs: [Data?] = []; var registered: [BessieConnectionDefinition] = []
    var attachArguments: [String] = []; var attachCount = 0; var events: [String] = []
    init(commands: [RemoteBootstrapCommandResult], snapshot: HerdrSnapshot = RemoteOnboardingBootstrapTests.snapshot()) {
        self.commands = commands; suppliedSnapshot = snapshot
    }
    func bootstrap() -> RemoteOnboardingBootstrap {
        RemoteOnboardingBootstrap(command: { [self] args, input in
            arguments.append(args); inputs.append(input); return commands.removeFirst()
        }, attach: { [self] args in
            attachCount += 1; attachArguments = args; return FakeBootstrapProcess { self.events.append("process.stop") }
        }, snapshot: { [self] _ in events.append("snapshot"); return suppliedSnapshot },
        register: { [self] in registered.append($0) }, pollCount: 4, sleep: {})
    }
}

private final class FakeBootstrapProcess: RemoteBootstrapProcess, @unchecked Sendable {
    var isRunning = true
    let stopped: () -> Void
    init(stopped: @escaping () -> Void) { self.stopped = stopped }
    func stop() { isRunning = false; stopped() }
}
