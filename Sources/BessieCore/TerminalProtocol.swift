import Foundation

public struct TerminalGrid: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

public struct HerdrTerminalFrame: Equatable, Sendable {
    public let sequence: UInt64
    public let grid: TerminalGrid
    public let full: Bool
    public let bytes: Data

    public init(sequence: UInt64, grid: TerminalGrid, full: Bool, bytes: Data) {
        self.sequence = sequence
        self.grid = grid
        self.full = full
        self.bytes = bytes
    }
}

public enum HerdrTerminalEnvelope: Equatable, Sendable {
    case frame(HerdrTerminalFrame)
    case closed(reason: String)

    public static func decode(_ data: Data) throws -> HerdrTerminalEnvelope {
        let value = try JSONDecoder().decode(WireEnvelope.self, from: data)
        switch value.type {
        case "terminal.frame":
            guard value.encoding == "ansi" else {
                throw HerdrClientError.unexpectedResponse("terminal frame encoding must be ansi")
            }
            guard let sequence = value.sequence,
                  let columns = value.columns ?? value.width,
                  let rows = value.rows ?? value.height,
                  columns > 0, rows > 0,
                  let encoded = value.bytesBase64 ?? value.bytes,
                  let decoded = Data(base64Encoded: encoded)
            else {
                throw HerdrClientError.unexpectedResponse("terminal frame is missing valid sequence, dimensions, or base64 bytes")
            }
            return .frame(HerdrTerminalFrame(
                sequence: sequence,
                grid: TerminalGrid(columns: columns, rows: rows),
                full: value.full ?? false,
                bytes: decoded
            ))
        case "terminal.closed":
            return .closed(reason: value.reason ?? "Herdr closed the terminal controller.")
        default:
            throw HerdrClientError.unexpectedResponse("unknown terminal envelope \(value.type)")
        }
    }
}

private struct WireEnvelope: Decodable {
    let type: String
    let sequence: UInt64?
    let encoding: String?
    let width: Int?
    let height: Int?
    let columns: Int?
    let rows: Int?
    let full: Bool?
    let bytes: String?
    let bytesBase64: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case type, encoding, width, height, cols, rows, full, bytes, reason
        case sequence = "seq"
        case bytesBase64 = "bytes_b64"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        sequence = try container.decodeIfPresent(UInt64.self, forKey: .sequence)
        encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        columns = try container.decodeIfPresent(Int.self, forKey: .cols)
        rows = try container.decodeIfPresent(Int.self, forKey: .rows)
        full = try container.decodeIfPresent(Bool.self, forKey: .full)
        bytes = try container.decodeIfPresent(String.self, forKey: .bytes)
        bytesBase64 = try container.decodeIfPresent(String.self, forKey: .bytesBase64)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

public enum TerminalFrameDisposition: Equatable, Sendable {
    case apply(Data)
    case ignored
    case waitingForFull
    case reconnect(reason: String)
}

public final class TerminalFrameSequencer: @unchecked Sendable {
    private let lock = NSLock()
    private var requestedGrid: TerminalGrid
    private var lastSequence: UInt64?
    private var waitingForFull = true
    private var failed = false

    public init(grid: TerminalGrid) { requestedGrid = grid }

    public var acceptsInput: Bool {
        lock.withLock { !waitingForFull && !failed }
    }

    public func requestGrid(_ grid: TerminalGrid) {
        lock.withLock {
            requestedGrid = grid
            waitingForFull = true
        }
    }

    public func reset(grid: TerminalGrid) {
        lock.withLock {
            requestedGrid = grid
            lastSequence = nil
            waitingForFull = true
            failed = false
        }
    }

    public func accept(_ frame: HerdrTerminalFrame) -> TerminalFrameDisposition {
        lock.withLock {
            guard !failed else { return .waitingForFull }
            if let lastSequence {
                if frame.sequence <= lastSequence { return .ignored }
                let expected = lastSequence + 1
                guard frame.sequence == expected else {
                    failed = true
                    waitingForFull = true
                    return .reconnect(reason: "terminal frame gap: expected \(expected), received \(frame.sequence)")
                }
            }
            lastSequence = frame.sequence
            guard frame.grid == requestedGrid else {
                waitingForFull = true
                return .waitingForFull
            }
            guard !waitingForFull || frame.full else { return .waitingForFull }
            if frame.full { waitingForFull = false }
            return .apply(frame.bytes)
        }
    }
}

public enum TerminalScrollDirection: String, Equatable, Sendable { case up, down }
public enum TerminalScrollSource: String, Equatable, Sendable { case wheel, pageKey = "page_key" }

public enum TerminalControlCommand: Equatable, Sendable {
    case input(Data)
    case resize(TerminalGrid, cellWidthPixels: Int, cellHeightPixels: Int)
    case scroll(direction: TerminalScrollDirection, lines: Int, source: TerminalScrollSource, column: Int?, row: Int?, modifiers: Int)
    case release

    public var jsonObject: [String: JSONValue] {
        switch self {
        case .input(let data):
            if let text = String(data: data, encoding: .utf8) {
                return ["type": .string("terminal.input"), "text": .string(text)]
            }
            return ["type": .string("terminal.input"), "bytes": .string(data.base64EncodedString())]
        case .resize(let grid, let cellWidth, let cellHeight):
            return [
                "type": .string("terminal.resize"), "cols": .number(Double(grid.columns)), "rows": .number(Double(grid.rows)),
                "cell_width_px": .number(Double(cellWidth)), "cell_height_px": .number(Double(cellHeight)),
            ]
        case .scroll(let direction, let lines, let source, let column, let row, let modifiers):
            var object: [String: JSONValue] = [
                "type": .string("terminal.scroll"), "direction": .string(direction.rawValue), "lines": .number(Double(lines)),
                "source": .string(source.rawValue), "modifiers": .number(Double(modifiers)),
            ]
            if let column { object["column"] = .number(Double(column)) }
            if let row { object["row"] = .number(Double(row)) }
            return object
        case .release:
            return ["type": .string("terminal.release")]
        }
    }

    public func lineData() throws -> Data {
        var data = try JSONEncoder().encode(JSONValue.object(jsonObject))
        data.append(0x0a)
        return data
    }
}

public struct HerdrTerminalProcessInvocation: Equatable, Sendable {
    public let executablePath: String
    public let paneID: String
    public let grid: TerminalGrid

    public init(executablePath: String, paneID: String, grid: TerminalGrid) {
        self.executablePath = executablePath
        self.paneID = paneID
        self.grid = grid
    }

    public var arguments: [String] {
        ["terminal", "session", "control", paneID, "--cols", String(grid.columns), "--rows", String(grid.rows)]
    }
}
