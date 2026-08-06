import XCTest
@testable import BessieCore

final class TerminalMouseRoutingTests: XCTestCase {
    func testFullMotionRequiresCellChange() {
        let sample = Data("x".utf8)
        let first = TerminalMouseRouting.route(
            kind: .motion,
            forceLocalSelection: false,
            capture: .full,
            motionCellChanged: true,
            sgrData: sample
        )
        XCTAssertEqual(first, .sgrRaw(sample))

        let sameCell = TerminalMouseRouting.route(
            kind: .motion,
            forceLocalSelection: false,
            capture: .full,
            motionCellChanged: false,
            sgrData: sample
        )
        XCTAssertEqual(sameCell, .none)
    }

    func testFullButtonDownSendsSGR() {
        let sample = Data("\u{1b}[<0;1;1M".utf8)
        let route = TerminalMouseRouting.route(
            kind: .buttonDown,
            forceLocalSelection: false,
            capture: .full,
            sgrData: sample
        )
        XCTAssertEqual(route, .sgrRaw(sample))
    }

    func testButtonsPolicyNeverMotions() {
        let sample = Data("x".utf8)
        let route = TerminalMouseRouting.route(
            kind: .motion,
            forceLocalSelection: false,
            capture: .buttons,
            motionCellChanged: true,
            sgrData: sample
        )
        XCTAssertEqual(route, .none)
    }

    func testShiftForcesLocalSelection() {
        let sample = Data("x".utf8)
        let route = TerminalMouseRouting.route(
            kind: .buttonDown,
            forceLocalSelection: true,
            capture: .full,
            sgrData: sample
        )
        XCTAssertEqual(route, .localSelection)
    }

    func testUnavailableNeverSGR() {
        let sample = Data("x".utf8)
        XCTAssertEqual(
            TerminalMouseRouting.route(
                kind: .buttonDown,
                forceLocalSelection: false,
                capture: .unavailable,
                sgrData: sample
            ),
            .focusAndLocalSelection
        )
        XCTAssertEqual(
            TerminalMouseRouting.route(
                kind: .motion,
                forceLocalSelection: false,
                capture: .unavailable,
                motionCellChanged: true,
                sgrData: sample
            ),
            .none
        )
    }

    func testCaptureCapabilityGatesShellsAndHermes() {
        XCTAssertEqual(TerminalMouseRouting.captureCapability(agent: nil), .unavailable)
        XCTAssertEqual(TerminalMouseRouting.captureCapability(agent: "shell"), .unavailable)
        XCTAssertEqual(TerminalMouseRouting.captureCapability(agent: "hermes"), .full)
        XCTAssertEqual(TerminalMouseRouting.captureCapability(agent: "Hermes"), .full)
        XCTAssertEqual(
            TerminalMouseRouting.captureCapability(
                agent: nil,
                foregroundCWD: "/home/hermes/hermes-agent/ui-tui"
            ),
            .full
        )
        XCTAssertEqual(
            TerminalMouseRouting.captureCapability(
                agent: nil,
                foregroundCWD: "/home/hermes/code/bessie"
            ),
            .unavailable
        )
    }
}
