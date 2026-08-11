import Foundation
import XCTest
@testable import BessieCore

final class RuntimeSetupTests: XCTestCase {
    func testFreshAndCorruptSelectionUseBundled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HerdrRuntimeSelectionStore(url: root.appendingPathComponent("selection.json"))
        XCTAssertEqual(store.load(), .bundled)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), .bundled)
    }

    func testVersionedSelectionsRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HerdrRuntimeSelectionStore(url: root.appendingPathComponent("selection.json"))
        for selection in [HerdrRuntimeSelection.bundled, .system, .custom(URL(fileURLWithPath: "/opt/herdr"))] {
            try store.save(selection); XCTAssertEqual(store.load(), selection)
        }
    }

    func testSelectedCustomMissingDoesNotFallBack() {
        let missing = URL(fileURLWithPath: "/definitely-missing-bessie-herdr")
        XCTAssertThrowsError(try HerdrRuntimeLocator(isExecutable: { _ in false }).resolve(
            explicitPath: nil, selection: .custom(missing), bundledURL: URL(fileURLWithPath: "/bundled/herdr"), path: "/bin"
        )) { XCTAssertEqual($0 as? RuntimeResolutionFailure, .customMissing(missing.path)) }
    }

    func testBundledSystemAndCustomResolveOnlyTheirSelectedSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundle/herdr")
        let system = root.appendingPathComponent("system/herdr")
        let custom = root.appendingPathComponent("custom/herdr")
        for url in [bundled, system, custom] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        let locator = HerdrRuntimeLocator(isExecutable: { [$0 == bundled, $0 == system, $0 == custom].contains(true) })

        XCTAssertEqual(try locator.resolve(explicitPath: nil, selection: .bundled, bundledURL: bundled, path: root.appendingPathComponent("system").path).source, .bundled)
        XCTAssertEqual(try locator.resolve(explicitPath: nil, selection: .system, bundledURL: bundled, path: root.appendingPathComponent("system").path).url, system)
        XCTAssertEqual(try locator.resolve(explicitPath: nil, selection: .custom(custom), bundledURL: bundled, path: root.appendingPathComponent("system").path).source, .custom)
    }

    func testExplicitOverrideStillWins() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        let runtime = try HerdrRuntimeLocator(isExecutable: { $0 == url }).resolve(
            explicitPath: url.path, selection: .bundled, bundledURL: nil, path: "")
        XCTAssertEqual(runtime.source, .explicitOverride)
    }

    func testDiagnosticReportIsAllowlistedAndContainsNoArbitraryOutput() {
        let report = RuntimeDiagnosticSnapshot(stage: .apiConnection, finding: .apiUnavailable,
            runtime: HerdrRuntime(url: URL(fileURLWithPath: "/Applications/Bessie.app/Contents/Resources/Herdr/herdr"), source: .bundled),
            observedVersion: "0.8.0", observedProtocol: 19, apiSocketPath: "/tmp/bessie.sock").sanitizedReport
        XCTAssertTrue(report.contains("source=bundled")); XCTAssertFalse(report.contains("PATH="))
        XCTAssertFalse(report.contains("terminal output")); XCTAssertFalse(report.contains("TOKEN"))
    }

    func testOnboardingMovesForwardAndBackWithoutCompletingEarly() {
        var state = OnboardingState()
        state.advance(runtimeReady: true, sessionReady: false, workspaceReady: false, terminalControllerReady: false)
        XCTAssertEqual(state.step, .connect)
        state.advance(runtimeReady: true, sessionReady: true, workspaceReady: false, terminalControllerReady: false)
        XCTAssertEqual(state.step, .howItWorks)
        state.goBack()
        XCTAssertEqual(state.step, .connect)
        XCTAssertFalse(state.completed)
    }

    func testOnboardingBackEligibilityIncludesNotifications() {
        XCTAssertFalse(OnboardingState(step: .connect).canNavigateBack)
        XCTAssertTrue(OnboardingState(step: .howItWorks).canNavigateBack)
        XCTAssertTrue(OnboardingState(step: .readTheRail).canNavigateBack)
        XCTAssertTrue(OnboardingState(step: .notifications).canNavigateBack)
    }

    func testOnboardingCompletesOnlyFromReadyWithReadyTerminalController() {
        var state = OnboardingState(step: .notifications)
        state.advance(runtimeReady: true, sessionReady: true, workspaceReady: true, terminalControllerReady: false)
        XCTAssertFalse(state.completed)
        state.advance(runtimeReady: true, sessionReady: true, workspaceReady: true, terminalControllerReady: true)
        XCTAssertTrue(state.completed)
        state.runAgain(); XCTAssertEqual(state, OnboardingState())
    }

    func testPendingAttemptPersistsExactIDsAndRejectsFutureSchema() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PendingOnboardingAttemptStore(url: root.appendingPathComponent("attempt.json"))
        let attempt = try PendingOnboardingAttempt(attemptID: "attempt-1", connectionID: "remote", sessionName: "bessie-1", path: "/tmp/../tmp/work", stage: .connecting, workspaceID: "w", tabID: "t", paneID: "p")
        try store.save(attempt)
        XCTAssertEqual(try store.load(), attempt)
        try Data(#"{"schemaVersion":999}"#.utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? OnboardingPersistenceError, .unsupportedSchema(999)) }
    }

    func testGeneratedPendingAttemptUsesBoundedOnboardingSessionName() throws {
        let attempt = try PendingOnboardingAttempt(connectionID: "remote", path: "/srv/project")

        XCTAssertTrue(attempt.sessionName.hasPrefix("bessie-ob-"))
        XCTAssertEqual(attempt.sessionName.utf8.count, 34)
        XCTAssertTrue(BessieConnectionDefinition.isSafeSession(attempt.sessionName))
    }

    func testAbsolutePathAndRemoteAttachCommandAreSafeAndUseSelectedCWD() throws {
        XCTAssertThrowsError(try OnboardingPathValidator.absolute("relative"))
        XCTAssertThrowsError(try OnboardingPathValidator.absolute("/tmp\n/not-the-selected-path"))
        XCTAssertThrowsError(try OnboardingPathValidator.absolute("/tmp\r/not-the-selected-path"))
        let connection = BessieConnectionDefinition(name: "Remote", kind: .ssh, sshHost: "studio", session: "old")
        let args = try RemoteHerdrBridgePlan.remoteAttachArguments(for: connection, session: "bessie-new", directory: "/srv/my work")
        XCTAssertTrue(args.contains("-tt")); XCTAssertEqual(args.last, "cd -- '/srv/my work' && exec herdr session attach bessie-new")
        XCTAssertFalse(args.joined(separator: " ").contains("nohup"))
    }

    func testLocalOnboardingPathComparisonResolvesSymlinksOnBothSides() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let canonical = root.appendingPathComponent("canonical", isDirectory: true)
        let selected = root.appendingPathComponent("selected", isDirectory: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: canonical)

        XCTAssertTrue(OnboardingPathValidator.localPathsAreEquivalent(selected.path, canonical.path))
        XCTAssertTrue(OnboardingPathValidator.localPathsAreEquivalent(canonical.path + "/", selected.path))
        XCTAssertFalse(OnboardingPathValidator.localPathsAreEquivalent(selected.path, root.path))
    }

    func testEveryFindingHasStableTypedIdentity() {
        XCTAssertEqual(Set(SetupFinding.allCases.map(\.rawValue)).count, 9)
        XCTAssertTrue(SetupFinding.allCases.allSatisfy { !$0.safeActions.isEmpty })
        XCTAssertTrue(SetupFinding.allCases.flatMap(\.safeActions).allSatisfy { SetupAction.allCases.contains($0) })
    }

    func testTroubleActionsExactlyMatchEveryFindingContract() {
        let expected: [(SetupFinding, [SetupAction])] = [
            (.bundledIntegrity, [.copyReport, .revealRuntime]),
            (.externalMissing, [.openSettings, .copyReport]),
            (.externalNotExecutable, [.openSettings, .copyReport]),
            (.incompatible, [.openSettings, .copyReport]),
            (.serverStartup, [.retry, .copyReport]),
            (.apiUnavailable, [.retry, .copyReport]),
            (.terminalControlUnavailable, [.retry, .copyReport]),
            (.permissionOrFilesystem, [.revealRuntime, .copyReport]),
            (.previouslyHealthyLoss, [.retry, .copyReport]),
        ]
        XCTAssertEqual(expected.map(\.0), SetupFinding.allCases)
        for (finding, actions) in expected {
            let diagnostic = RuntimeDiagnosticSnapshot(stage: .runtimeValidation, finding: finding)
            XCTAssertEqual(diagnostic.availableActions, actions, "Wrong Trouble actions for \(finding.rawValue)")
        }
        XCTAssertEqual(RuntimeDiagnosticSnapshot(stage: .runtimeResolution).availableActions, [])
    }

    func testRuntimeRevealTargetsBundledAppOrNearestExternalLocation() {
        let bundled = RuntimeDiagnosticSnapshot(
            stage: .runtimeValidation,
            finding: .bundledIntegrity,
            runtime: HerdrRuntime(
                url: URL(fileURLWithPath: "/Applications/Bessie.app/Contents/Resources/Herdr/herdr"),
                source: .bundled
            )
        )
        XCTAssertEqual(bundled.runtimeRevealURL(fileExists: { _ in false })?.path, "/Applications/Bessie.app")

        let external = RuntimeDiagnosticSnapshot(
            stage: .runtimeValidation,
            finding: .permissionOrFilesystem,
            runtime: HerdrRuntime(url: URL(fileURLWithPath: "/opt/herdr/bin/herdr"), source: .custom)
        )
        XCTAssertEqual(external.runtimeRevealURL(fileExists: { $0 == "/opt/herdr" })?.path, "/opt/herdr")
    }

    func testTerminalControllerFactsDistinguishHealthyAndUnavailableControl() {
        XCTAssertTrue(TerminalControllerFacts(ready: 1).healthy)
        XCTAssertNil(TerminalControllerFacts(ready: 1).finding)
        XCTAssertEqual(TerminalControllerFacts(ready: 1, failed: 1).finding, .terminalControlUnavailable)
        XCTAssertEqual(TerminalControllerFacts(ownershipConflicts: 1).finding, .terminalControlUnavailable)
    }

    func testBundledValidationRequiresExactPathHashSignatureAndIdentity() throws {
        let url = URL(fileURLWithPath: "/Applications/Bessie.app/Contents/Resources/Herdr/herdr")
        let runtime = HerdrRuntime(url: url, source: .bundled)
        let lock = BundledRuntimeLock(canonicalURL: url, sha256: "abc", versionOutput: "herdr 0.8.0", protocolVersion: 19)
        let validator = HerdrRuntimeValidator(
            inspect: { _ in RuntimeFileFacts(exists: true, regularFile: true, executable: true, arm64: true, sha256: "abc", signatureValid: true) },
            identity: { _ in HerdrServerIdentity(version: "0.8.0", protocolVersion: 19) })
        XCTAssertEqual(try validator.validate(runtime, bundledLock: lock).protocolVersion, 19)
        XCTAssertThrowsError(try validator.validate(HerdrRuntime(url: URL(fileURLWithPath: "/tmp/herdr"), source: .bundled), bundledLock: lock)) {
            XCTAssertEqual($0 as? RuntimeValidationFailure, .bundledIntegrity)
        }
    }

    func testBundledRuntimeLockUsesPackagedSignedHashAndFailsClosedWithoutIt() throws {
        let url = URL(fileURLWithPath: "/Applications/Bessie.app/Contents/Resources/Herdr/herdr")
        let packaged = Data(#"""
        {
            "sha256": "unsigned-upstream-hash",
            "bundled_sha256": "signed-packaged-hash",
            "expected_version_output": "herdr 0.8.0",
            "protocol": 19
        }
        """#.utf8)

        let lock = try XCTUnwrap(BundledRuntimeLock(data: packaged, canonicalURL: url))
        XCTAssertEqual(lock.sha256, "signed-packaged-hash")

        let sourceOnly = Data(#"""
        {
            "sha256": "unsigned-upstream-hash",
            "expected_version_output": "herdr 0.8.0",
            "protocol": 19
        }
        """#.utf8)
        XCTAssertNil(BundledRuntimeLock(data: sourceOnly, canonicalURL: url))
    }

    func testExternalValidationFailuresNeverBecomeBundledIntegrity() {
        let url = URL(fileURLWithPath: "/opt/herdr")
        let validator = HerdrRuntimeValidator(
            inspect: { _ in RuntimeFileFacts(exists: true, regularFile: true, executable: false, arm64: true, sha256: nil, signatureValid: false) },
            identity: { _ in HerdrServerIdentity(version: "0.8.0", protocolVersion: 19) })
        XCTAssertThrowsError(try validator.validate(HerdrRuntime(url: url, source: .custom), bundledLock: nil)) {
            XCTAssertEqual($0 as? RuntimeValidationFailure, .externalNotExecutable(url.path))
        }
    }

    func testExecutableWithoutHerdrIdentityIsIncompatible() {
        let url = URL(fileURLWithPath: "/opt/not-herdr")
        let validator = HerdrRuntimeValidator(
            inspect: { _ in RuntimeFileFacts(exists: true, regularFile: true, executable: true, arm64: true, sha256: nil, signatureValid: true) },
            identity: { _ in throw CocoaError(.fileReadCorruptFile) })
        XCTAssertThrowsError(try validator.validate(HerdrRuntime(url: url, source: .custom), bundledLock: nil)) {
            XCTAssertEqual($0 as? RuntimeValidationFailure, .incompatible(version: nil, protocolVersion: nil))
        }
    }

    func testCorruptBundledAndIncompatibleExternalRemainDistinct() {
        let bundledURL = URL(fileURLWithPath: "/bundle/herdr")
        let lock = BundledRuntimeLock(canonicalURL: bundledURL, sha256: "expected", versionOutput: "herdr 0.8.0", protocolVersion: 19)
        let corrupt = HerdrRuntimeValidator(
            inspect: { _ in RuntimeFileFacts(exists: true, regularFile: true, executable: true, arm64: true, sha256: "wrong", signatureValid: true) },
            identity: { _ in HerdrServerIdentity(version: "0.8.0", protocolVersion: 19) })
        XCTAssertThrowsError(try corrupt.validate(HerdrRuntime(url: bundledURL, source: .bundled), bundledLock: lock)) {
            XCTAssertEqual($0 as? RuntimeValidationFailure, .bundledIntegrity)
        }

        let incompatible = HerdrRuntimeValidator(
            inspect: { _ in RuntimeFileFacts(exists: true, regularFile: true, executable: true, arm64: true, sha256: nil, signatureValid: false) },
            identity: { _ in HerdrServerIdentity(version: "0.8.0", protocolVersion: 18) })
        XCTAssertThrowsError(try incompatible.validate(HerdrRuntime(url: URL(fileURLWithPath: "/external/herdr"), source: .custom), bundledLock: nil)) {
            XCTAssertEqual($0 as? RuntimeValidationFailure, .incompatible(version: "0.8.0", protocolVersion: 18))
        }
    }
}
