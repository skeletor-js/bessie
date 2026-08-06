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

public struct TerminalFocusRequest: Equatable, Sendable {
    public let paneID: String
    public let generation: UInt64

    fileprivate init(paneID: String, generation: UInt64) {
        self.paneID = paneID
        self.generation = generation
    }
}

public struct TerminalFocusStateMachine: Equatable, Sendable {
    public private(set) var authoritativePaneID: String?
    public private(set) var responderPaneID: String?
    public private(set) var pendingRequest: TerminalFocusRequest?
    private var generation: UInt64 = 0

    public init(authoritativePaneID: String? = nil, responderPaneID: String? = nil) {
        self.authoritativePaneID = authoritativePaneID
        self.responderPaneID = responderPaneID
    }

    public var outlinedPaneID: String? {
        guard pendingRequest == nil, authoritativePaneID == responderPaneID else { return nil }
        return authoritativePaneID
    }

    @discardableResult
    public mutating func beginRequest(paneID: String) -> TerminalFocusRequest {
        generation &+= 1
        let request = TerminalFocusRequest(paneID: paneID, generation: generation)
        pendingRequest = request
        return request
    }

    public mutating func responderChanged(paneID: String, isFirstResponder: Bool) {
        if isFirstResponder {
            responderPaneID = paneID
        } else if responderPaneID == paneID {
            responderPaneID = nil
        }
    }

    @discardableResult
    public mutating func complete(
        _ request: TerminalFocusRequest,
        authoritativePaneID: String?
    ) -> Bool {
        guard pendingRequest == request else { return false }
        pendingRequest = nil
        self.authoritativePaneID = authoritativePaneID
        return authoritativePaneID == request.paneID
    }

    @discardableResult
    public mutating func fail(_ request: TerminalFocusRequest) -> Bool {
        guard pendingRequest == request else { return false }
        pendingRequest = nil
        return true
    }

    public mutating func reconcile(authoritativePaneID: String?) {
        self.authoritativePaneID = authoritativePaneID
        if pendingRequest?.paneID == authoritativePaneID {
            pendingRequest = nil
        }
    }
}

public final class TerminalInputRouter: @unchecked Sendable {
    private let transport: any TerminalInputTransport
    private let performanceRecorder: BessiePerformanceRecorder?
    private let queue = DispatchQueue(label: "bessie.terminal.input.\(UUID().uuidString)")

    public init(
        transport: any TerminalInputTransport,
        performanceRecorder: BessiePerformanceRecorder? = nil
    ) {
        self.transport = transport
        self.performanceRecorder = performanceRecorder
    }

    @discardableResult
    public func send(
        _ operation: TerminalInputOperation,
        correlateToRenderedFrame: Bool = false
    ) throws -> UInt64? {
        let sequence = recordReceived(correlateToRenderedFrame: correlateToRenderedFrame)
        try queue.sync { try route(operation, sequence: sequence) }
        return sequence
    }

    public func enqueue(_ operation: TerminalInputOperation) {
        let sequence = recordReceived(correlateToRenderedFrame: false)
        queue.async { [self] in
            do {
                try route(operation, sequence: sequence)
            } catch {
                // Mouse/keyboard must not fail silently — observe/not-ready was a
                // common "Hermes mouse dead" failure mode.
                #if DEBUG
                fputs("Bessie terminal input dropped: \(error)\n", stderr)
                #endif
            }
        }
    }

    private func recordReceived(correlateToRenderedFrame: Bool) -> UInt64? {
        let sequence = performanceRecorder?.nextSequence()
        performanceRecorder?.mark(.terminalInputReceived, sequence: sequence)
        if !correlateToRenderedFrame {
            performanceRecorder?.markUnavailable(
                from: .terminalInputReceived,
                to: .terminalFrameRendered,
                sequence: sequence
            )
        }
        return sequence
    }

    private func route(_ operation: TerminalInputOperation, sequence: UInt64?) throws {
        performanceRecorder?.mark(.terminalInputEnqueued, sequence: sequence)
        switch operation {
        case .raw(let data): try transport.sendRaw(data)
        case .keys(let keys): try transport.sendKeys(keys)
        case .paste(let text): try transport.sendPaste(text)
        case .scroll(let direction, let lines, let source, let column, let row, let modifiers):
            try transport.sendScroll(direction: direction, lines: lines, source: source, column: column, row: row, modifiers: modifiers)
        }
        performanceRecorder?.mark(.terminalWriteCompleted, sequence: sequence)
    }
}
