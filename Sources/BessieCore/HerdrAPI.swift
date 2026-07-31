import Foundation

public protocol HerdrAPI: Sendable {
    func ping() throws -> HerdrServerIdentity
    func subscribe() throws -> any HerdrEventSubscription
    func snapshot() throws -> HerdrSnapshot
}

public protocol HerdrEventSubscription: AnyObject, Sendable {
    func drainBufferedEvents() -> [HerdrEvent]
    func nextEvent() throws -> HerdrEvent?
    func close()
}

public final class HerdrSocketAPI: HerdrAPI, @unchecked Sendable {
    private let socketPath: String

    public init(socketPath: String) { self.socketPath = socketPath }

    public func ping() throws -> HerdrServerIdentity {
        try perform(method: "ping").identity()
    }

    public func snapshot() throws -> HerdrSnapshot {
        try perform(method: "session.snapshot").snapshot()
    }

    @discardableResult
    public func request(method: String, params: [String: JSONValue] = [:]) throws -> JSONValue {
        try perform(method: method, params: params).result
    }

    public func subscribe() throws -> any HerdrEventSubscription {
        let connection = try UnixSocketNDJSONConnection(path: socketPath)
        let id = "bessie-subscribe-\(UUID().uuidString)"
        let subscriptions = Self.subscriptionNames.map { JSONValue.object(["type": .string($0)]) }
        let request: JSONValue = .object([
            "id": .string(id),
            "method": .string("events.subscribe"),
            "params": .object(["subscriptions": .array(subscriptions)]),
        ])
        try connection.sendLine(JSONEncoder().encode(request))
        let acknowledgement = try HerdrResponseDecoder.decode(connection.readLine(), expectedID: id)
        guard case .object(let result) = acknowledgement.result,
              result["type"] == .string("subscription_started") else {
            connection.close()
            throw HerdrClientError.unexpectedResponse("events.subscribe was not acknowledged")
        }
        return SocketEventSubscription(connection: connection)
    }

    private func perform(method: String, params: [String: JSONValue] = [:]) throws -> HerdrResponse {
        let connection = try UnixSocketNDJSONConnection(path: socketPath)
        defer { connection.close() }
        let id = "bessie-\(UUID().uuidString)"
        let request: JSONValue = .object([
            "id": .string(id),
            "method": .string(method),
            "params": .object(params),
        ])
        try connection.sendLine(JSONEncoder().encode(request))
        return try HerdrResponseDecoder.decode(connection.readLine(), expectedID: id)
    }

    private static let subscriptionNames = [
        "workspace.created", "workspace.updated", "workspace.metadata_updated", "workspace.renamed",
        "workspace.moved", "workspace.closed", "workspace.focused", "tab.created", "tab.closed",
        "tab.focused", "tab.renamed", "tab.moved", "pane.created", "pane.closed", "pane.updated",
        "pane.focused", "pane.moved", "pane.exited", "pane.agent_detected", "layout.updated",
    ]
}

private final class SocketEventSubscription: HerdrEventSubscription, @unchecked Sendable {
    private let connection: any HerdrLineConnection
    private let condition = NSCondition()
    private var buffered: [HerdrEvent] = []
    private var terminalError: Error?
    private var ended = false

    init(connection: any HerdrLineConnection) {
        self.connection = connection
        Thread.detachNewThread { [weak self] in self?.readLoop() }
    }

    func drainBufferedEvents() -> [HerdrEvent] {
        condition.lock()
        defer { condition.unlock() }
        defer { buffered.removeAll() }
        return buffered
    }

    func nextEvent() throws -> HerdrEvent? {
        condition.lock()
        defer { condition.unlock() }
        while buffered.isEmpty && !ended { condition.wait() }
        if !buffered.isEmpty { return buffered.removeFirst() }
        if let terminalError { throw terminalError }
        return nil
    }

    func close() { connection.close() }

    private func readLoop() {
        do {
            while true {
                let event = try JSONDecoder().decode(HerdrEvent.self, from: connection.readLine())
                condition.lock()
                buffered.append(event)
                condition.broadcast()
                condition.unlock()
            }
        } catch {
            condition.lock()
            terminalError = error
            ended = true
            condition.broadcast()
            condition.unlock()
        }
    }
}
