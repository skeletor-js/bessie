import Foundation
import XCTest
@testable import BessieCore

final class DiagnosticsHardeningTests: XCTestCase {
    func testSupportEvidenceRejectsAllUntrustedDetailAtTheBoundary() {
        let hostile = """
        token=ghp_supersecret
        /Users/private-user/Secret/project
        private-user@prod.internal
        ssh -i ~/.ssh/id_ed25519 prod.internal
        terminal said: deploy --password swordfish
        """
        let evidence = DiagnosticSupportEvidence(
            stage: .terminalController,
            errorClass: .controllerDisconnected,
            untrustedDetail: hostile,
            facts: [.apiHealthy(false), .retryAttempt(3)]
        )
        let report = evidence.report

        XCTAssertTrue(report.contains("stage=terminalController"))
        XCTAssertTrue(report.contains("error_class=controller_disconnected"))
        XCTAssertTrue(report.contains("api_healthy=false"))
        XCTAssertTrue(report.contains("retry_attempt=3"))
        for forbidden in ["ghp_supersecret", "private-user", "Secret/project", "prod.internal", "id_ed25519", "deploy", "swordfish"] {
            XCTAssertFalse(report.contains(forbidden), "Leaked \(forbidden)")
        }
        XCTAssertFalse(report.contains(hostile))
    }

    func testRuntimeReportUsesCategoriesInsteadOfPathsSessionsOrSocketNames() {
        let report = RuntimeDiagnosticSnapshot(
            stage: .apiConnection,
            finding: .apiUnavailable,
            runtime: HerdrRuntime(
                url: URL(fileURLWithPath: "/Users/private-user/Applications/Bessie.app/Contents/Resources/Herdr/herdr"),
                source: .bundled
            ),
            observedVersion: "0.8.0",
            observedProtocol: 19,
            session: "private-session",
            apiSocketPath: "/Users/private-user/.config/herdr/private.sock"
        ).sanitizedReport

        XCTAssertTrue(report.contains("stage=apiConnection"))
        XCTAssertTrue(report.contains("finding=apiUnavailable"))
        XCTAssertTrue(report.contains("runtime_location=bundled"))
        XCTAssertTrue(report.contains("session_configured=true"))
        XCTAssertTrue(report.contains("socket_configured=true"))
        for forbidden in ["private-user", "private-session", "private.sock", "/Users/"] {
            XCTAssertFalse(report.contains(forbidden), "Leaked \(forbidden)")
        }
    }

    func testUntrustedDiagnosticTextIsAlwaysDiscardedNotPatternMatched() {
        XCTAssertEqual(
            DiagnosticSanitizer.discardUntrustedText("innocent-looking terminal output without a secret marker"),
            "[redacted untrusted detail]"
        )
        XCTAssertEqual(DiagnosticSanitizer.discardUntrustedText(""), "[no detail]")
    }
}
