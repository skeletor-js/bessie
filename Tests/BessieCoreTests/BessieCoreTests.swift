import XCTest
@testable import BessieCore

final class BessieCoreTests: XCTestCase {
    func testCompatibilityBaselineMatchesApprovedHerdrContract() {
        XCTAssertEqual(BessieCompatibility.herdrVersion, "0.8.0")
        XCTAssertEqual(BessieCompatibility.protocolVersion, 19)
        XCTAssertEqual(
            BessieCompatibility.herdrSourceRevision,
            "346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
        )
    }

    func testCompatibilityReportsProtocolBeforeVersionMismatch() {
        let identity = HerdrServerIdentity(version: "0.7.4", protocolVersion: 16)
        XCTAssertEqual(
            HerdrCompatibility.incompatibility(for: identity),
            "Herdr uses protocol 16. Bessie requires protocol 19."
        )
    }
}
