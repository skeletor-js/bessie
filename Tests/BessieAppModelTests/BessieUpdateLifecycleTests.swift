import AppKit
import Foundation
import XCTest
@testable import BessieApp

@MainActor
final class BessieUpdateLifecycleTests: XCTestCase {
    func testAppOwnsStartsAndInjectsExactlyOneCoordinatorAcrossBothScenes() throws {
        let source = try sourceFile("Sources/BessieApp/BessieApp.swift")

        XCTAssertEqual(source.components(separatedBy: "@StateObject private var updates: BessieUpdateCoordinator").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "BessieUpdateCoordinator()").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "updates.start()").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: ".environmentObject(updates)").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy: "Window(\"Bessie\", id:").count - 1, 1)
    }

    func testNativeUpdateCommandTracksCoordinatorAvailabilityAndPerformsManualCheck() {
        let adapter = LifecycleUpdaterAdapter()
        adapter.canCheckForUpdates = false
        let coordinator = BessieUpdateCoordinator(
            launchContext: .eligibleForCoordinatorTests,
            adapterFactory: { _ in adapter }
        )
        let command = BessieCheckForUpdatesCommand(coordinator: coordinator)

        XCTAssertTrue(coordinator.start())
        XCTAssertFalse(command.isEnabled)
        XCTAssertFalse(command.perform())
        XCTAssertEqual(adapter.checkCount, 0)

        adapter.sendAvailabilityChanged(true)
        XCTAssertTrue(command.isEnabled)
        XCTAssertTrue(command.perform())
        XCTAssertEqual(adapter.checkCount, 1)
        XCTAssertFalse(command.isEnabled)
        XCTAssertFalse(command.perform())
        XCTAssertEqual(adapter.checkCount, 1)
    }

    func testTerminationHooksRemainCleanupOnlyAndNeverOwnHerdrTopologyOrProcesses() throws {
        let appSource = try sourceFile("Sources/BessieApp/BessieApp.swift")
        let delegateSource = try sourceFile("Sources/BessieApp/BessieAppDelegate.swift")
        let viewShutdown = try functionBody(named: "private func shutdownForAppExit()", in: appSource)
        let appTermination = try functionBody(
            named: "func applicationShouldTerminate(_ sender: NSApplication)",
            in: delegateSource
        )

        XCTAssertTrue(viewShutdown.contains("projects.updateConnection(nil, snapshot: nil)"))
        XCTAssertTrue(viewShutdown.contains("terminalRegistry.releaseAll()"))
        XCTAssertTrue(viewShutdown.contains("fleet.stop()"))
        XCTAssertTrue(appTermination.contains("fleet?.stopIntentServer()"))
        XCTAssertTrue(appTermination.contains("fleet?.stop()"))
        XCTAssertTrue(appTermination.contains("return .terminateNow"))

        for forbidden in ["herdr stop", "workspace.close", "pane.close", "tab.close", "Process.kill", "kill(", "PTY"] {
            XCTAssertFalse(viewShutdown.localizedCaseInsensitiveContains(forbidden), forbidden)
            XCTAssertFalse(appTermination.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func functionBody(named signature: String, in source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: signature)?.lowerBound, "Missing \(signature)")
        let suffix = source[start...]
        var depth = 0
        var foundOpeningBrace = false
        for index in suffix.indices {
            switch suffix[index] {
            case "{":
                depth += 1
                foundOpeningBrace = true
            case "}" where foundOpeningBrace:
                depth -= 1
                if depth == 0 { return String(suffix[...index]) }
            default:
                break
            }
        }
        XCTFail("Unterminated \(signature)")
        return ""
    }
}

@MainActor
private final class LifecycleUpdaterAdapter: BessieUpdaterAdapter {
    weak var delegate: BessieUpdaterAdapterDelegate?
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = true
    var allowsAutomaticUpdates = true
    private(set) var checkCount = 0

    func start() throws {}
    func checkForUpdates() { checkCount += 1 }

    func sendAvailabilityChanged(_ available: Bool) {
        canCheckForUpdates = available
        delegate?.updaterAvailabilityDidChange()
    }
}
