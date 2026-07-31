import XCTest
@testable import BessieCore

final class BessieCoreTests: XCTestCase {
    func testCompatibilityBaselineMatchesApprovedHerdrContract() {
        XCTAssertEqual(BessieCompatibility.herdrVersion, "0.7.5")
        XCTAssertEqual(BessieCompatibility.protocolVersion, 17)
        XCTAssertEqual(
            BessieCompatibility.herdrSourceRevision,
            "b4112743cff42452b5d18558bf2d55bbbfff8c69"
        )
    }

    func testCompatibilityReportsProtocolBeforeVersionMismatch() {
        let identity = HerdrServerIdentity(version: "0.7.4", protocolVersion: 16)
        XCTAssertEqual(
            HerdrCompatibility.incompatibility(for: identity),
            "Herdr uses protocol 16. Bessie requires protocol 17."
        )
    }
}
