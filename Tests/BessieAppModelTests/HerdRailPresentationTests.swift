import XCTest
@testable import BessieApp
@testable import BessieCore

final class HerdRailPresentationTests: XCTestCase {
    func testRestartPresentationExistsOnlyForVerifiedReadyStateWithRetainedHandler() throws {
        let version = BessieUpdateVersion(shortVersion: "1.2.0", buildVersion: "120")

        XCTAssertNil(HerdRailUpdatePresentation(
            phase: .idle,
            canRestartToUpdate: false
        ))
        XCTAssertNil(HerdRailUpdatePresentation(
            phase: .readyToRestart(version),
            canRestartToUpdate: false
        ))
        XCTAssertNil(HerdRailUpdatePresentation(
            phase: .installing(version),
            canRestartToUpdate: true
        ))

        let presentation = try XCTUnwrap(HerdRailUpdatePresentation(
            phase: .readyToRestart(version),
            canRestartToUpdate: true
        ))
        XCTAssertEqual(presentation.title, "Restart to Update")
        XCTAssertEqual(presentation.version, "1.2.0")
        XCTAssertEqual(presentation.expandedAccessibilityLabel, "Restart to Update")
        XCTAssertEqual(presentation.collapsedAccessibilityLabel, "Restart to Update Bessie 1.2.0")
        XCTAssertEqual(presentation.help, "Restart to Update Bessie 1.2.0")
        XCTAssertEqual(presentation.symbolName, "arrow.clockwise")
    }

    func testRestartActionAppearsImmediatelyAboveSettingsDivider() throws {
        let version = BessieUpdateVersion(shortVersion: "1.2.0", buildVersion: "120")
        let ready = try XCTUnwrap(HerdRailUpdatePresentation(
            phase: .readyToRestart(version),
            canRestartToUpdate: true
        ))

        XCTAssertEqual(HerdRailFooterPresentation.items(update: nil), [
            .settingsDivider,
            .settings,
        ])
        XCTAssertEqual(HerdRailFooterPresentation.items(update: ready), [
            .restartToUpdate,
            .settingsDivider,
            .settings,
        ])
    }

    func testRestartActivationInvokesClosureAtMostOnceUntilPresentationChanges() {
        var activation = HerdRailUpdateActivation()
        var invocations = 0

        XCTAssertTrue(activation.invoke { invocations += 1 })
        XCTAssertFalse(activation.invoke { invocations += 1 })
        XCTAssertEqual(invocations, 1)
        XCTAssertTrue(activation.isConsumed)

        activation.reset()
        XCTAssertFalse(activation.isConsumed)
        XCTAssertTrue(activation.invoke { invocations += 1 })
        XCTAssertEqual(invocations, 2)
    }

    func testBindingRailWidthsAndAppearanceChoicesAreExact() {
        XCTAssertEqual(BessieDesign.railWidth, 244)
        XCTAssertEqual(BessieDesign.collapsedRailWidth, 52)
        XCTAssertEqual(BessieAppearance.allCases, [
            .system, .dark, .light, .catppuccinLatte, .catppuccinFrappe,
            .catppuccinMacchiato, .catppuccinMocha,
        ])
    }

    func testStatusGlyphUsesBindingGeometry() {
        XCTAssertEqual(BessieStatusGeometry.needsYouDiameter, 8)
        XCTAssertEqual(BessieStatusGeometry.workingDiameter, 10)
        XCTAssertEqual(BessieStatusGeometry.doneDiameter, 10)
        XCTAssertEqual(BessieStatusGeometry.idleWidth, 10)
        XCTAssertEqual(BessieStatusGeometry.unknownDiameter, 8)
    }

    func testCollapsedPaneDescriptionIncludesTitleAndLocation() {
        let row = HerdRailPaneRow(
            id: HerdPaneIdentity(connectionID: "remote", paneID: "p1"),
            terminalID: "terminal-p1",
            title: "Review pane", secondaryIdentity: "claude-review", location: "Hermes · bessie · review", group: .working,
            rawState: .working, agentKind: "claude",
            target: RoutedPaneTarget(connectionID: "remote", workspaceID: "w", tabID: "t", paneID: "p1")
        )
        XCTAssertEqual(row.accessibilityDescription, "Review pane, claude-review, Working, Hermes · bessie · review")
    }
}
