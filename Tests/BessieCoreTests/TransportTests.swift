import Foundation
import XCTest
@testable import BessieCore

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
        let payload = Data(#"{"id":"other","result":{"type":"pong","version":"0.7.5","protocol":17}}"#.utf8)

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
        let payload = Data(#"{"id":"snapshot-1","result":{"type":"session_snapshot","snapshot":{"version":"0.7.5","protocol":17,"focused_workspace_id":"w1","focused_tab_id":"t1","focused_pane_id":"p1","workspaces":[{"workspace_id":"w1"}],"tabs":[],"panes":[],"layouts":[],"agents":[]}}}"#.utf8)

        let response = try HerdrResponseDecoder.decode(payload, expectedID: "snapshot-1")
        let snapshot = try response.snapshot()

        XCTAssertEqual(snapshot.focusedWorkspaceID, "w1")
        XCTAssertEqual(snapshot.workspaces.count, 1)
        XCTAssertEqual(snapshot.protocolVersion, 17)
    }
}
