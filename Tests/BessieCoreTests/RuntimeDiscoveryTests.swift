import Foundation
import XCTest
@testable import BessieCore

final class RuntimeDiscoveryTests: XCTestCase {
    func testExplicitOverrideWinsBeforePathAndLocalCandidates() {
        let locator = HerdrRuntimeLocator(isExecutable: { _ in true })

        let result = locator.locate(
            explicitPath: "/approved/herdr",
            path: "/usr/bin:/opt/homebrew/bin",
            repositoryRoot: URL(fileURLWithPath: "/repo")
        )

        XCTAssertEqual(result, HerdrRuntime(url: URL(fileURLWithPath: "/approved/herdr"), source: .explicitOverride))
    }

    func testPathCandidatePrecedesRepositoryLocalFallback() {
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/herdr")
        let locator = HerdrRuntimeLocator(isExecutable: { $0 == executable })

        let result = locator.locate(
            explicitPath: nil,
            path: "/usr/bin:/opt/homebrew/bin",
            repositoryRoot: URL(fileURLWithPath: "/repo")
        )

        XCTAssertEqual(result, HerdrRuntime(url: executable, source: .path))
    }

    func testRepositoryLocalFallbackIsRecognized() {
        let executable = URL(fileURLWithPath: "/repo/.local/herdr/herdr")
        let locator = HerdrRuntimeLocator(isExecutable: { $0 == executable })

        let result = locator.locate(
            explicitPath: nil,
            path: "",
            repositoryRoot: URL(fileURLWithPath: "/repo")
        )

        XCTAssertEqual(result, HerdrRuntime(url: executable, source: .repositoryLocal))
    }

    func testUserLocalInstallIsFoundWithoutShellPath() {
        let executable = URL(fileURLWithPath: "/Users/tester/.local/bin/herdr")
        let locator = HerdrRuntimeLocator(isExecutable: { $0 == executable })

        let result = locator.locate(
            explicitPath: nil,
            path: "/usr/bin:/bin",
            repositoryRoot: URL(fileURLWithPath: "/Applications"),
            homeDirectory: URL(fileURLWithPath: "/Users/tester")
        )

        XCTAssertEqual(result, HerdrRuntime(url: executable, source: .path))
    }
}
