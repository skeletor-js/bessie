import Foundation
import XCTest
@testable import BessieCore

final class HerdrProtocolContractTests: XCTestCase {
    func testCreationResultsDecodeAuthoritativeIDs() throws {
        let workspace = try HerdrWorkspaceCreationResult(result: .object([
            "type": .string("workspace_created"),
            "workspace": .object(["workspace_id": .string("w1")]),
            "tab": .object(["tab_id": .string("w1:t1")]),
            "root_pane": .object(["pane_id": .string("w1:p1")]),
        ]))
        let tab = try HerdrTabCreationResult(result: .object([
            "type": .string("tab_created"),
            "tab": .object(["tab_id": .string("w1:t2")]),
            "root_pane": .object(["pane_id": .string("w1:p2")]),
        ]))
        let pane = try HerdrPaneCreationResult(result: .object([
            "type": .string("pane_info"),
            "pane": .object(["pane_id": .string("w1:p3")]),
        ]))

        XCTAssertEqual(workspace, .init(workspaceID: "w1", tabID: "w1:t1", rootPaneID: "w1:p1"))
        XCTAssertEqual(tab, .init(tabID: "w1:t2", rootPaneID: "w1:p2"))
        XCTAssertEqual(pane, .init(paneID: "w1:p3"))
    }

    func testCreationResultsRejectWrongTypeAndMissingID() {
        XCTAssertThrowsError(try HerdrWorkspaceCreationResult(result: .object([
            "type": .string("workspace_info"),
        ])))
        XCTAssertThrowsError(try HerdrTabCreationResult(result: .object([
            "type": .string("tab_created"),
            "tab": .object(["tab_id": .string("w1:t2")]),
            "root_pane": .object([:]),
        ])))
        XCTAssertThrowsError(try HerdrPaneCreationResult(result: .object([
            "type": .string("pane_info"),
            "pane": .object(["pane_id": .string(" \t\n")]),
        ])))
    }

    func testPaneFactsDecodeOptionalAuthoritativeCWDFields() throws {
        let populated = try HerdrPaneContractFacts(value: .object([
            "pane_id": .string("w1:p1"),
            "cwd": .string("/private/tmp/project"),
            "foreground_cwd": .string("/private/tmp/project/subdirectory"),
        ]))
        let absent = try HerdrPaneContractFacts(value: .object([
            "pane_id": .string("w1:p2"),
        ]))

        XCTAssertEqual(populated.cwd, "/private/tmp/project")
        XCTAssertEqual(populated.foregroundCWD, "/private/tmp/project/subdirectory")
        XCTAssertNil(absent.cwd)
        XCTAssertNil(absent.foregroundCWD)
    }

    func testStartupCommandWaitsForNonblankOutputAndStableExactEchoBeforeEnter() throws {
        let command = "printf 'abcdefghijklmnop'"
        let api = PaneCommandAPI(reads: [
            "   ",
            "$ ",
            "$ printf 'abcdefghij\nklmnop'",
            "$ printf 'abcdefghij\nklmnop'",
        ])
        let clock = TestPollingClock()
        let submitter = HerdrStartupCommandSubmitter(
            api: api,
            policy: .test,
            now: clock.now,
            wait: clock.wait
        )

        try submitter.submit(command: command, toPaneID: "w1:p1")

        XCTAssertEqual(api.submissions, [
            .init(text: command, keys: []),
            .init(text: "", keys: ["Enter"]),
        ])
        XCTAssertEqual(api.methods, [
            "pane.read", "pane.read", "pane.send_input",
            "pane.read", "pane.read", "pane.send_input",
        ])
        XCTAssertEqual(api.requests.first?.params, [
            "pane_id": .string("w1:p1"),
            "source": .string("visible"),
            "lines": .number(20),
            "format": .string("text"),
            "strip_ansi": .bool(true),
        ])
    }

    func testReadinessTimeoutSendsNoCommand() {
        let api = PaneCommandAPI(reads: ["", " \n ", ""])
        let clock = TestPollingClock()
        let submitter = HerdrStartupCommandSubmitter(api: api, policy: .test, now: clock.now, wait: clock.wait)

        XCTAssertThrowsError(try submitter.submit(command: "echo ready", toPaneID: "w1:p1")) {
            XCTAssertEqual($0 as? HerdrStartupCommandFailure, .readinessTimedOut(paneID: "w1:p1"))
        }
        XCTAssertTrue(api.submissions.isEmpty)
    }

    func testEchoTimeoutSendsExactTextButNoEnter() {
        let command = "echo exact text"
        let api = PaneCommandAPI(reads: ["$ ", "$ unrelated", "$ still unrelated", "$ "])
        let clock = TestPollingClock()
        let submitter = HerdrStartupCommandSubmitter(api: api, policy: .test, now: clock.now, wait: clock.wait)

        XCTAssertThrowsError(try submitter.submit(command: command, toPaneID: "w1:p1")) {
            XCTAssertEqual($0 as? HerdrStartupCommandFailure, .echoTimedOut(paneID: "w1:p1"))
        }
        XCTAssertEqual(api.submissions, [.init(text: command, keys: [])])
    }

    func testExistingCommandTextCannotFalsePositiveAsNewEcho() {
        let command = "echo duplicate"
        let api = PaneCommandAPI(reads: [
            "$ echo duplicate",
            "$ echo duplicate",
            "$ echo duplicate",
            "$ echo duplicate",
        ])
        let clock = TestPollingClock()
        let submitter = HerdrStartupCommandSubmitter(api: api, policy: .test, now: clock.now, wait: clock.wait)

        XCTAssertThrowsError(try submitter.submit(command: command, toPaneID: "w1:p1")) {
            XCTAssertEqual($0 as? HerdrStartupCommandFailure, .echoTimedOut(paneID: "w1:p1"))
        }
        XCTAssertEqual(api.submissions, [.init(text: command, keys: [])])
    }

    func testCancellationAfterCommandTextSendsNoEnter() {
        let command = "echo cancellation"
        let api = PaneCommandAPI(reads: ["$ ", "$ echo cancellation"])
        let clock = TestPollingClock()
        let submitter = HerdrStartupCommandSubmitter(
            api: api,
            policy: .test,
            now: clock.now,
            wait: clock.wait,
            isCancelled: { !api.submissions.isEmpty }
        )

        XCTAssertThrowsError(try submitter.submit(command: command, toPaneID: "w1:p1")) {
            XCTAssertEqual($0 as? HerdrStartupCommandFailure, .cancelled(paneID: "w1:p1"))
        }
        XCTAssertEqual(api.submissions, [.init(text: command, keys: [])])
    }

    func testCommandRejectsLineBreaksBeforeReadingOrSending() {
        let api = PaneCommandAPI(reads: ["$ "])
        let clock = TestPollingClock()
        let submitter = HerdrStartupCommandSubmitter(api: api, policy: .test, now: clock.now, wait: clock.wait)

        for command in ["echo one\necho two", "echo one\recho two"] {
            XCTAssertThrowsError(try submitter.submit(command: command, toPaneID: "w1:p1")) {
                XCTAssertEqual($0 as? HerdrStartupCommandFailure, .invalidCommand)
            }
        }
        XCTAssertTrue(api.methods.isEmpty)
    }
}

private final class PaneCommandAPI: HerdrMutationAPI, @unchecked Sendable {
    struct Request {
        let method: String
        let params: [String: JSONValue]
    }

    struct Submission: Equatable {
        let text: String
        let keys: [String]
    }

    private var reads: [String]
    private(set) var methods: [String] = []
    private(set) var requests: [Request] = []
    private(set) var submissions: [Submission] = []

    init(reads: [String]) {
        self.reads = reads
    }

    func request(method: String, params: [String: JSONValue]) throws -> JSONValue {
        methods.append(method)
        requests.append(.init(method: method, params: params))
        switch method {
        case "pane.read":
            let text = reads.isEmpty ? "" : reads.removeFirst()
            return .object([
                "type": .string("pane_read"),
                "read": .object([
                    "pane_id": .string("w1:p1"),
                    "workspace_id": .string("w1"),
                    "tab_id": .string("w1:t1"),
                    "source": .string("visible"),
                    "format": .string("text"),
                    "text": .string(text),
                    "revision": .number(0),
                    "truncated": .bool(false),
                ]),
            ])
        case "pane.send_input":
            guard case .string(let text)? = params["text"],
                  case .array(let keyValues)? = params["keys"] else {
                throw HerdrClientError.unexpectedResponse("missing input fields")
            }
            let keys = try keyValues.map { value -> String in
                guard case .string(let key) = value else {
                    throw HerdrClientError.unexpectedResponse("invalid input key")
                }
                return key
            }
            submissions.append(.init(text: text, keys: keys))
            return .object(["type": .string("ok")])
        default:
            throw HerdrClientError.unexpectedResponse("unexpected method \(method)")
        }
    }

    func snapshot() throws -> HerdrSnapshot {
        throw HerdrClientError.unexpectedResponse("snapshot not used")
    }
}

private final class TestPollingClock: @unchecked Sendable {
    private var value = Date(timeIntervalSinceReferenceDate: 0)

    lazy var now: @Sendable () -> Date = { [self] in value }
    lazy var wait: @Sendable (TimeInterval) -> Void = { [self] interval in
        value = value.addingTimeInterval(interval)
    }
}

private extension HerdrStartupCommandPolicy {
    static let test = HerdrStartupCommandPolicy(
        pollInterval: 0.5,
        readinessTimeout: 1,
        echoTimeout: 1,
        stableEchoReadCount: 2
    )
}
