import Foundation

public protocol TerminalInputTransport: Sendable {
    func sendRaw(_ data: Data) throws
    func sendKeys(_ keys: [String]) throws
    func sendPaste(_ text: String) throws
    func sendScroll(direction: TerminalScrollDirection, lines: Int, source: TerminalScrollSource, column: Int?, row: Int?, modifiers: Int) throws
}

public enum TerminalInputOperation: Equatable, Sendable {
    case raw(Data)
    case keys([String])
    case paste(String)
    case scroll(direction: TerminalScrollDirection, lines: Int, source: TerminalScrollSource, column: Int?, row: Int?, modifiers: Int)
}

public final class TerminalInputRouter: @unchecked Sendable {
    private let transport: any TerminalInputTransport
    private let lock = NSLock()

    public init(transport: any TerminalInputTransport) { self.transport = transport }

    public func send(_ operation: TerminalInputOperation) throws {
        try lock.withLock {
            switch operation {
            case .raw(let data): try transport.sendRaw(data)
            case .keys(let keys): try transport.sendKeys(keys)
            case .paste(let text): try transport.sendPaste(text)
            case .scroll(let direction, let lines, let source, let column, let row, let modifiers):
                try transport.sendScroll(direction: direction, lines: lines, source: source, column: column, row: row, modifiers: modifiers)
            }
        }
    }
}
