import Foundation
import XCTest
@testable import BessieCore

final class TerminalControllerTests: XCTestCase {
    func testFrameDecoderNormalizesPinnedAndDocumentedAliases() throws {
        let pinned = try HerdrTerminalEnvelope.decode(Data(#"{"type":"terminal.frame","seq":1,"encoding":"ansi","width":80,"height":24,"full":true,"bytes":"SEk="}"#.utf8))
        let documented = try HerdrTerminalEnvelope.decode(Data(#"{"type":"terminal.frame","seq":2,"encoding":"ansi","cols":90,"rows":30,"full":false,"bytes_b64":"IQ=="}"#.utf8))

        XCTAssertEqual(pinned, .frame(.init(sequence: 1, grid: .init(columns: 80, rows: 24), full: true, bytes: Data("HI".utf8))))
        XCTAssertEqual(documented, .frame(.init(sequence: 2, grid: .init(columns: 90, rows: 30), full: false, bytes: Data("!".utf8))))
        XCTAssertEqual(try HerdrTerminalEnvelope.decode(Data(#"{"type":"terminal.closed","reason":"released"}"#.utf8)), .closed(reason: "released"))
    }

    func testFrameDecoderRejectsUnknownEncodingAndInvalidBase64() {
        XCTAssertThrowsError(try HerdrTerminalEnvelope.decode(Data(#"{"type":"terminal.frame","seq":1,"encoding":"cells","width":80,"height":24,"full":true,"bytes":"SEk="}"#.utf8)))
        XCTAssertThrowsError(try HerdrTerminalEnvelope.decode(Data(#"{"type":"terminal.frame","seq":1,"encoding":"ansi","width":80,"height":24,"full":true,"bytes":"%%%"}"#.utf8)))
    }

    func testSequencerRequiresMatchingFullThenAppliesOnlyContiguousFrames() {
        let sequencer = TerminalFrameSequencer(grid: .init(columns: 80, rows: 24))

        XCTAssertEqual(sequencer.accept(.init(sequence: 1, grid: .init(columns: 80, rows: 24), full: false, bytes: Data("delta".utf8))), .waitingForFull)
        XCTAssertEqual(sequencer.accept(.init(sequence: 2, grid: .init(columns: 70, rows: 20), full: true, bytes: Data("stale".utf8))), .waitingForFull)
        XCTAssertEqual(sequencer.accept(.init(sequence: 3, grid: .init(columns: 80, rows: 24), full: true, bytes: Data("full".utf8))), .apply(Data("full".utf8)))
        XCTAssertEqual(sequencer.accept(.init(sequence: 4, grid: .init(columns: 80, rows: 24), full: false, bytes: Data("next".utf8))), .apply(Data("next".utf8)))
        XCTAssertEqual(sequencer.accept(.init(sequence: 4, grid: .init(columns: 80, rows: 24), full: false, bytes: Data())), .ignored)
        XCTAssertEqual(sequencer.accept(.init(sequence: 6, grid: .init(columns: 80, rows: 24), full: false, bytes: Data())), .reconnect(reason: "terminal frame gap: expected 5, received 6"))
        XCTAssertFalse(sequencer.acceptsInput)
    }

    func testResizeFreezesInputUntilMatchingFullRepaint() {
        let sequencer = TerminalFrameSequencer(grid: .init(columns: 80, rows: 24))
        _ = sequencer.accept(.init(sequence: 1, grid: .init(columns: 80, rows: 24), full: true, bytes: Data()))
        XCTAssertTrue(sequencer.acceptsInput)

        sequencer.requestGrid(.init(columns: 100, rows: 40))
        XCTAssertFalse(sequencer.acceptsInput)
        XCTAssertEqual(sequencer.accept(.init(sequence: 2, grid: .init(columns: 80, rows: 24), full: false, bytes: Data())), .waitingForFull)
        XCTAssertEqual(sequencer.accept(.init(sequence: 3, grid: .init(columns: 100, rows: 40), full: true, bytes: Data("paint".utf8))), .apply(Data("paint".utf8)))
        XCTAssertTrue(sequencer.acceptsInput)
    }

    func testCommandsUseExactProtocol17NDJSONShapes() throws {
        XCTAssertEqual(TerminalControlCommand.input(Data("cow".utf8)).jsonObject, ["type": .string("terminal.input"), "text": .string("cow")])
        XCTAssertEqual(TerminalControlCommand.input(Data([0xff])).jsonObject, ["type": .string("terminal.input"), "bytes": .string("/w==")])
        XCTAssertEqual(TerminalControlCommand.resize(.init(columns: 90, rows: 30), cellWidthPixels: 8, cellHeightPixels: 16).jsonObject, ["type": .string("terminal.resize"), "cols": .number(90), "rows": .number(30), "cell_width_px": .number(8), "cell_height_px": .number(16)])
        XCTAssertEqual(TerminalControlCommand.scroll(direction: .up, lines: 3, source: .wheel, column: 4, row: 5, modifiers: 0).jsonObject, ["type": .string("terminal.scroll"), "direction": .string("up"), "lines": .number(3), "source": .string("wheel"), "column": .number(4), "row": .number(5), "modifiers": .number(0)])
        XCTAssertEqual(TerminalControlCommand.release.jsonObject, ["type": .string("terminal.release")])
    }

    func testInputRouterPreservesCompositeSubmissionOrder() throws {
        let transport = RecordingTerminalInputTransport()
        let router = TerminalInputRouter(transport: transport)

        try router.send(.raw(Data("a".utf8)))
        try router.send(.keys(["left"]))
        try router.send(.paste("β\n"))
        try router.send(.scroll(direction: .down, lines: 2, source: .pageKey, column: nil, row: nil, modifiers: 0))

        XCTAssertEqual(transport.events, ["raw:a", "keys:left", "paste:β\n", "scroll:down:2:page_key"])
    }

    func testProcessInvocationUsesOneControllerWithoutTakeover() {
        let invocation = HerdrTerminalProcessInvocation(executablePath: "/repo/.local/herdr/herdr", paneID: "w1:p2", grid: .init(columns: 80, rows: 24))
        XCTAssertEqual(invocation.arguments, ["terminal", "session", "control", "w1:p2", "--cols", "80", "--rows", "24"])
        XCTAssertFalse(invocation.arguments.contains("--takeover"))
    }

    func testProcessFailureSeparatesOwnershipConflictFromReconnectableExit() {
        XCTAssertEqual(TerminalControllerFailure.classify(stderr: "terminal x already has an attached client; retry with --takeover", status: 1), .ownershipConflict("terminal x already has an attached client; retry with --takeover"))
        XCTAssertEqual(TerminalControllerFailure.classify(stderr: "", status: 9), .processExit("terminal controller exited 9"))
    }
}

private final class RecordingTerminalInputTransport: TerminalInputTransport, @unchecked Sendable {
    private(set) var events: [String] = []
    func sendRaw(_ data: Data) throws { events.append("raw:" + String(decoding: data, as: UTF8.self)) }
    func sendKeys(_ keys: [String]) throws { events.append("keys:" + keys.joined(separator: ",")) }
    func sendPaste(_ text: String) throws { events.append("paste:" + text) }
    func sendScroll(direction: TerminalScrollDirection, lines: Int, source: TerminalScrollSource, column: Int?, row: Int?, modifiers: Int) throws {
        events.append("scroll:\(direction.rawValue):\(lines):\(source.rawValue)")
    }
}
