import XCTest
@testable import BessieCore

final class TerminalSGRMouseTests: XCTestCase {
    func testButtonPressAndReleaseAreSGREncoded() {
        let press = TerminalSGRMouse.button(.left, pressed: true, column: 12, row: 4)
        XCTAssertEqual(String(decoding: press, as: UTF8.self), "\u{1b}[<0;12;4M")
        let release = TerminalSGRMouse.button(.left, pressed: false, column: 12, row: 4)
        XCTAssertEqual(String(decoding: release, as: UTF8.self), "\u{1b}[<0;12;4m")
    }

    func testWheelAndModifiers() {
        let wheel = TerminalSGRMouse.button(.wheelUp, pressed: true, column: 1, row: 1, control: true)
        XCTAssertEqual(String(decoding: wheel, as: UTF8.self), "\u{1b}[<80;1;1M")
    }

    func testCellHitTesting() {
        let cell = TerminalSGRMouse.cell(x: 10, y: 20, width: 100, height: 40, columns: 10, rows: 4)
        XCTAssertEqual(cell?.column, 2)
        XCTAssertEqual(cell?.row, 3)
        XCTAssertNil(TerminalSGRMouse.cell(x: 0, y: 0, width: 0, height: 10, columns: 10, rows: 4))
    }

    func testHoverMotionUsesCode35() {
        let data = TerminalSGRMouse.motion(buttonHeld: nil, column: 10, row: 4)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\u{1b}[<35;10;4M")
    }

    func testDragMotionUsesCode32PlusButton() {
        let data = TerminalSGRMouse.motion(buttonHeld: .left, column: 3, row: 2)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\u{1b}[<32;3;2M")
    }
}
