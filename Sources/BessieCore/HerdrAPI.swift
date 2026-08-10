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
    public let socketPath: String
    private let requestConnection: @Sendable () throws -> any HerdrLineConnection

    public init(
        socketPath: String,
        requestDeadlines: HerdrRequestDeadlines = .prefixDispatch
    ) {
        self.socketPath = URL(fileURLWithPath: socketPath).standardizedFileURL.path
        let path = self.socketPath
        requestConnection = {
            try UnixSocketNDJSONConnection(path: path, deadlines: requestDeadlines)
        }
    }

    init(
        socketPath: String,
        requestConnection: @escaping @Sendable () throws -> any HerdrLineConnection
    ) {
        self.socketPath = socketPath
        self.requestConnection = requestConnection
    }

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

    public func stagedMutationRequest(
        method: String,
        params: [String: JSONValue]
    ) -> Result<JSONValue, HerdrMutationRequestFailure> {
        let connection: any HerdrLineConnection
        do {
            connection = try requestConnection()
        } catch {
            return .failure(.init(disposition: .definitelyUnsent, underlying: error))
        }
        defer { connection.close() }
        let id = "bessie-\(UUID().uuidString)"
        let request: JSONValue = .object([
            "id": .string(id),
            "method": .string(method),
            "params": .object(params),
        ])
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(request)
        } catch {
            return .failure(.init(disposition: .definitelyUnsent, underlying: error))
        }
        do {
            try connection.sendLine(encoded)
        } catch let failure as HerdrLineSendFailure {
            return .failure(.init(
                disposition: failure.disposition,
                underlying: failure.underlying
            ))
        } catch {
            return .failure(.init(disposition: .mutationOutcomeUnknown, underlying: error))
        }
        do {
            return .success(try HerdrResponseDecoder.decode(
                connection.readLine(),
                expectedID: id
            ).result)
        } catch {
            return .failure(.init(disposition: .mutationOutcomeUnknown, underlying: error))
        }
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
        let connection = try requestConnection()
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

    static let subscriptionNames = [
        "workspace.created", "workspace.updated", "workspace.metadata_updated", "workspace.renamed",
        "workspace.moved", "workspace.closed", "workspace.focused", "tab.created", "tab.closed",
        "tab.focused", "tab.renamed", "tab.moved", "pane.created", "pane.closed", "pane.updated",
        "pane.focused", "pane.moved", "pane.exited", "pane.agent_detected", "layout.updated",
    ]

    static let snapshotPollInterval: TimeInterval = 1
    static let snapshotPollEventName = "bessie.snapshot_poll"
}

private final class SocketEventSubscription: HerdrEventSubscription, @unchecked Sendable {
    private let connection: any HerdrLineConnection
    private let events = HerdrEventBuffer()

    init(connection: any HerdrLineConnection) {
        self.connection = connection
        Thread.detachNewThread { [weak self] in self?.readLoop() }
    }

    func drainBufferedEvents() -> [HerdrEvent] {
        events.drain()
    }

    func nextEvent() throws -> HerdrEvent? {
        try events.nextEvent(pollInterval: HerdrSocketAPI.snapshotPollInterval)
    }

    func close() { connection.close() }

    private func readLoop() {
        do {
            while true {
                let event = try JSONDecoder().decode(HerdrEvent.self, from: connection.readLine())
                events.append(event)
            }
        } catch {
            events.finish(error: error)
        }
    }
}

final class HerdrEventBuffer: @unchecked Sendable {
    private let condition = NSCondition()
    private var buffered: [HerdrEvent] = []
    private var terminalError: Error?
    private var ended = false

    func append(_ event: HerdrEvent) {
        condition.lock()
        buffered.append(event)
        condition.broadcast()
        condition.unlock()
    }

    func drain() -> [HerdrEvent] {
        condition.lock()
        defer { condition.unlock() }
        defer { buffered.removeAll() }
        return buffered
    }

    func finish(error: Error?) {
        condition.lock()
        terminalError = error
        ended = true
        condition.broadcast()
        condition.unlock()
    }

    func nextEvent(pollInterval: TimeInterval) throws -> HerdrEvent? {
        precondition(pollInterval > 0)
        condition.lock()
        defer { condition.unlock() }
        if buffered.isEmpty, !ended {
            _ = condition.wait(until: Date(timeIntervalSinceNow: pollInterval))
        }
        if !buffered.isEmpty { return buffered.removeFirst() }
        if let terminalError { throw terminalError }
        if ended { return nil }
        return HerdrEvent(name: HerdrSocketAPI.snapshotPollEventName, data: [:])
    }
}
