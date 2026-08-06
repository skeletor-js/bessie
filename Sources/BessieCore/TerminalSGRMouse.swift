import Foundation

/// Encode xterm SGR mouse sequences for injection through Herdr `terminal.input`.
/// Coordinates are 1-based cell positions (xterm mouse protocol).
public enum TerminalSGRMouse: Sendable {
    public enum Button: Int, Sendable {
        case left = 0
        case middle = 1
        case right = 2
        case wheelUp = 64
        case wheelDown = 65
        case wheelLeft = 66
        case wheelRight = 67
    }

    public static func button(
        _ button: Button,
        pressed: Bool,
        column: Int,
        row: Int,
        control: Bool = false,
        shift: Bool = false,
        meta: Bool = false
    ) -> Data {
        let col = max(1, column)
        let r = max(1, row)
        var code = button.rawValue
        if control { code += 16 }
        if shift { code += 4 }
        if meta { code += 8 }
        let suffix = pressed ? "M" : "m"
        return Data("\u{1b}[<\(code);\(col);\(r)\(suffix)".utf8)
    }

    /// Motion / drag / hover.
    /// - buttonHeld nil → no-button motion (DECSET 1003 hover) = base 35
    /// - buttonHeld set → button-motion (DECSET 1002 drag) = 32 + button
    public static func motion(
        buttonHeld: Button?,
        column: Int,
        row: Int,
        control: Bool = false,
        shift: Bool = false,
        meta: Bool = false
    ) -> Data {
        let col = max(1, column)
        let r = max(1, row)
        // xterm SGR: motion bit +32; no-button motion uses button code 3 → 35.
        var code = 32
        if let buttonHeld {
            code += buttonHeld.rawValue
        } else {
            code += 3
        }
        if control { code += 16 }
        if shift { code += 4 }
        if meta { code += 8 }
        return Data("\u{1b}[<\(code);\(col);\(r)M".utf8)
    }

    public static func cell(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        columns: Int,
        rows: Int
    ) -> (column: Int, row: Int)? {
        guard columns > 0, rows > 0, width > 0, height > 0 else { return nil }
        let px = min(max(x, 0), width - 0.001)
        let py = min(max(y, 0), height - 0.001)
        let col = min(columns, max(1, Int(px / (width / Double(columns))) + 1))
        let row = min(rows, max(1, Int(py / (height / Double(rows))) + 1))
        return (col, row)
    }
}
