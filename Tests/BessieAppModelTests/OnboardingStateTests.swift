import Foundation
import XCTest

final class OnboardingStateTests: XCTestCase {
    func testOnboardingStepContinuityIsKeyedAndAccessibilityAware() throws {
        let source = try appSource("OnboardingView.swift")

        XCTAssertTrue(source.contains("OnboardingStepRegion"))
        XCTAssertTrue(source.contains(".id(state.step)"))
        XCTAssertTrue(source.contains("initialOffset: 12"))
        XCTAssertTrue(source.contains("withAnimation(BessieDesign.motionExplanatoryEaseOut)"))
        XCTAssertTrue(source.contains("pathFocused = step == .connect"))
        XCTAssertTrue(source.contains("notification: .announcementRequested"))
        XCTAssertTrue(source.contains("settings.connections.first(where: { $0.kind == .local })"))
        XCTAssertTrue(source.contains("Button(path.isEmpty ? \"Choose Folder…\" : \"Change…\")"))
        XCTAssertTrue(source.contains("panel.prompt = \"Choose\""))
        XCTAssertTrue(source.contains("panel.canCreateDirectories = true"))
        XCTAssertTrue(source.contains("Use the Herdr runtime on this Mac"))
        XCTAssertTrue(source.contains(".padding(.horizontal, 18)"))
        XCTAssertTrue(source.contains(".padding(.vertical, 14)"))
        XCTAssertEqual(source.components(separatedBy: ".frame(height: 76)").count - 1, 2)
        XCTAssertTrue(source.contains("Add Remote Herd"))
        XCTAssertFalse(source.contains("the local herd is already running"))
        XCTAssertFalse(source.contains(".move(edge:"))
    }

    func testTopLeftBrandTreatmentsUseOnlyTheCowMark() throws {
        let onboarding = try appSource("OnboardingView.swift")
        let rail = try appSource("HerdRail.swift")
        let designSystem = try appSource("BessieDesignSystem.swift")

        XCTAssertFalse(onboarding.contains("Text(\"Bessie\")"))
        XCTAssertFalse(rail.contains("Text(\"Bessie\")"))
        XCTAssertTrue(designSystem.contains("struct BessieBrandMark: View"))
        XCTAssertFalse(designSystem.contains("Text(\"Bessie\")"))
        XCTAssertTrue(designSystem.contains(".accessibilityLabel(\"Bessie\")"))
    }

    private func appSource(_ name: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/BessieApp/\(name)"),
            encoding: .utf8
        )
    }
}
