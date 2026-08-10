import Foundation
import XCTest
@testable import BessieCore
#if os(macOS)
import Darwin
#endif

final class TransportTests: XCTestCase {
    func testFramerPreservesPartialLinesAndReturnsEveryCompleteRecord() throws {
        var framer = NDJSONFramer()

        XCTAssertEqual(try framer.append(Data("{\"id\":\"1\"".utf8)), [])
        XCTAssertEqual(
            try framer.append(Data("}\n{\"id\":\"2\"}\npartial".utf8)),
            ["{\"id\":\"1\"}", "{\"id\":\"2\"}"]
        )
        XCTAssertEqual(framer.remainder, Data("partial".utf8))
    }

    func testResponseDecoderRejectsMismatchedCorrelationID() throws {
        let payload = Data(#"{"id":"other","result":{"type":"pong","version":"0.8.0","protocol":19}}"#.utf8)

        XCTAssertThrowsError(try HerdrResponseDecoder.decode(payload, expectedID: "expected")) { error in
            XCTAssertEqual(error as? HerdrClientError, .mismatchedResponseID(expected: "expected", actual: "other"))
        }
    }

    func testResponseDecoderSurfacesTypedServerError() throws {
        let payload = Data(#"{"id":"req-1","error":{"code":"server_unavailable","message":"not running"}}"#.utf8)

        XCTAssertThrowsError(try HerdrResponseDecoder.decode(payload, expectedID: "req-1")) { error in
            XCTAssertEqual(error as? HerdrClientError, .server(code: "server_unavailable", message: "not running"))
        }
    }

    func testInvalidRequestWithoutCorrelationIDStillSurfacesServerError() throws {
        let payload = Data(#"{"id":"","error":{"code":"invalid_request","message":"missing pane_id"}}"#.utf8)

        XCTAssertThrowsError(try HerdrResponseDecoder.decode(payload, expectedID: "req-1")) { error in
            XCTAssertEqual(error as? HerdrClientError, .server(code: "invalid_request", message: "missing pane_id"))
        }
    }

    func testSnapshotDecoderPreservesAuthoritativeIdentifiersAndCollections() throws {
        let payload = Data(#"{"id":"snapshot-1","result":{"type":"session_snapshot","snapshot":{"version":"0.8.0","protocol":19,"focused_workspace_id":"w1","focused_tab_id":"t1","focused_pane_id":"p1","workspaces":[{"workspace_id":"w1"}],"tabs":[],"panes":[],"layouts":[],"agents":[]}}}"#.utf8)

        let response = try HerdrResponseDecoder.decode(payload, expectedID: "snapshot-1")
        let snapshot = try response.snapshot()

        XCTAssertEqual(snapshot.focusedWorkspaceID, "w1")
        XCTAssertEqual(snapshot.workspaces.count, 1)
        XCTAssertEqual(snapshot.protocolVersion, 19)
    }

    func testStagedSocketMutationTreatsUnclassifiedSendFailureAsUnknown() {
        let connection = ScriptedLineConnection(sendError: HerdrClientError.connectionClosed)
        let api = HerdrSocketAPI(socketPath: "/tmp/test", requestConnection: { connection })

        let result = api.stagedMutationRequest(method: "pane.close", params: ["pane_id": .string("p1")])

        guard case .failure(let failure) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(failure.disposition, .mutationOutcomeUnknown)
        XCTAssertFalse(connection.didRead)
    }

    func testStagedSocketMutationKeepsProvenPreTransmissionFailureDefinitelyUnsent() {
        let connection = ScriptedLineConnection(sendError: HerdrLineSendFailure(
            disposition: .definitelyUnsent,
            underlying: HerdrClientError.connectionClosed
        ))
        let api = HerdrSocketAPI(socketPath: "/tmp/test", requestConnection: { connection })

        let result = api.stagedMutationRequest(method: "pane.close", params: ["pane_id": .string("p1")])

        guard case .failure(let failure) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(failure.disposition, .definitelyUnsent)
        XCTAssertFalse(connection.didRead)
    }

    func testStagedSocketMutationClassifiesEveryPostSendFailureAsUnknown() {
        for readResult in [
            Result<Data, Error>.failure(HerdrClientError.connectionClosed),
            .success(Data("not-json".utf8)),
            .success(Data(#"{"id":"wrong","result":{}}"#.utf8)),
            .success(Data(#"{"id":"","error":{"code":"failed","message":"failed"}}"#.utf8)),
        ] {
            let connection = ScriptedLineConnection(readResult: readResult)
            let api = HerdrSocketAPI(socketPath: "/tmp/test", requestConnection: { connection })

            let result = api.stagedMutationRequest(
                method: "pane.close",
                params: ["pane_id": .string("p1")]
            )

            guard case .failure(let failure) = result else { return XCTFail("expected failure") }
            XCTAssertEqual(failure.disposition, .mutationOutcomeUnknown)
            XCTAssertTrue(connection.didSendCompleteLine)
        }
    }

#if os(macOS)
    func testOneShotMutationTimesOutAfterTransmissionWithoutRetrying() throws {
        var descriptors = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        defer {
            if descriptors[0] >= 0 { Darwin.close(descriptors[0]) }
            if descriptors[1] >= 0 { Darwin.close(descriptors[1]) }
        }
        let connection = try UnixSocketNDJSONConnection(
            connectedDescriptor: descriptors[0],
            path: "socketpair",
            deadlines: .init(send: 0.1, read: 0.05)
        )
        descriptors[0] = -1
        let api = HerdrSocketAPI(socketPath: "/tmp/test", requestConnection: { connection })

        let started = ProcessInfo.processInfo.systemUptime
        let result = api.stagedMutationRequest(method: "pane.close", params: ["pane_id": .string("p1")])
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        guard case .failure(let failure) = result else { return XCTFail("expected timeout") }
        XCTAssertEqual(failure.disposition, .mutationOutcomeUnknown)
        XCTAssertLessThan(elapsed, 0.5)
        var byte: UInt8 = 0
        XCTAssertEqual(Darwin.read(descriptors[1], &byte, 1), 1, "The request reached the peer before timeout")
    }
#endif
}

private final class ScriptedLineConnection: HerdrLineConnection, @unchecked Sendable {
    let sendError: Error?
    let readResult: Result<Data, Error>
    private(set) var didSendCompleteLine = false
    private(set) var didRead = false

    init(
        sendError: Error? = nil,
        readResult: Result<Data, Error> = .failure(HerdrClientError.connectionClosed)
    ) {
        self.sendError = sendError
        self.readResult = readResult
    }

    func sendLine(_ data: Data) throws {
        if let sendError { throw sendError }
        didSendCompleteLine = true
    }

    func readLine() throws -> Data {
        didRead = true
        return try readResult.get()
    }

    func close() {}
}
