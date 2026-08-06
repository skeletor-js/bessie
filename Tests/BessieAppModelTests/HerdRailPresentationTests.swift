import XCTest
@testable import BessieApp
@testable import BessieCore

final class HerdRailPresentationTests: XCTestCase {
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
        XCTAssertEqual(BessieStatusGeometry.settledDiameter, 9)
        XCTAssertEqual(BessieStatusGeometry.unknownDiameter, 8)
    }

    func testCollapsedPaneDescriptionIncludesTitleAndLocation() {
        let row = HerdRailPaneRow(
            id: HerdPaneIdentity(connectionID: "remote", paneID: "p1"),
            title: "Claude review", location: "Hermes · bessie · review", group: .working,
            rawState: .working, agentKind: "claude",
            target: RoutedPaneTarget(connectionID: "remote", workspaceID: "w", tabID: "t", paneID: "p1")
        )
        XCTAssertEqual(row.accessibilityDescription, "Claude review, Working, Hermes · bessie · review")
    }
}
