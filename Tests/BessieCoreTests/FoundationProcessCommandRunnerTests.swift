import XCTest
@testable import BessieCore

final class FoundationProcessCommandRunnerTests: XCTestCase {
    func testDrainsLargeStandardOutputAndErrorWithoutDeadlock() throws {
        let byteCount = 256 * 1_024
        let script = "import sys; sys.stdout.write('o' * \(byteCount)); sys.stderr.write('e' * \(byteCount))"

        let result = try FoundationProcessCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", script],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, byteCount)
        XCTAssertEqual(result.stderr.count, byteCount)
    }

    func testTerminatesAndReapsTimedOutProcess() {
        XCTAssertThrowsError(try FoundationProcessCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            timeout: 0.05
        )) { error in
            XCTAssertEqual(error as? FoundationProcessCommandError, .timedOut)
        }
    }
}
