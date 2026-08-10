import Foundation
import XCTest

final class WorkspaceHierarchyControlTests: XCTestCase {
    func testHierarchyDisclosureLocalizesMotionToOptionOpacity() throws {
        let source = try appSource("WorkspaceTitlebarChrome.swift")

        XCTAssertTrue(source.contains("WorkspaceHierarchyOptionRegion(isPresented: openSection == .herd)"))
        XCTAssertTrue(source.contains("WorkspaceHierarchyOptionRegion(isPresented: openSection == .workspace)"))
        XCTAssertTrue(source.contains("WorkspaceHierarchyOptionRegion(isPresented: openSection == .tab)"))
        XCTAssertTrue(source.contains("withAnimation(BessieDesign.motionStrongEaseOut)"))
        XCTAssertFalse(source.contains(".animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: openSection)"))
        XCTAssertFalse(source.contains(".move(edge: .top)"))
    }

    func testHierarchyOptionSelectionAndCompactExpansionRemainImmediate() throws {
        let source = try appSource("WorkspaceTitlebarChrome.swift")

        XCTAssertTrue(source.contains("openSection = nil\n            action()"))
        XCTAssertTrue(source.contains("openSection = section\n            expandRail()"))
        XCTAssertFalse(source.contains("withAnimation { openSection"))
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
