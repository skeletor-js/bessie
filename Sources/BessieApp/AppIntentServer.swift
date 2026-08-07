import BessieCore
import Foundation

final class AppIntentServer: @unchecked Sendable {
    let live: AppIntentLivePort
    let dispatcher: BessieIntentActionDispatcher
    private let presentation: AppPanePresentationIntentPort
    private let server: BessieIntentSocketServer

    init(
        path: String = BessieIntentSocketPath.resolved(),
        projects: any BessieIntentProjectReadPort = BessieProjectStore()
    ) {
        let live = AppIntentLivePort()
        let presentation = AppPanePresentationIntentPort()
        let executor = BessieIntentExecutor(live: live, projects: projects, presentation: presentation)
        self.live = live
        self.presentation = presentation
        dispatcher = BessieIntentActionDispatcher(live: live, executor: executor)
        server = BessieIntentSocketServer(path: path) { request in executor.execute(request) }
    }

    func start() throws { try server.start() }
    func stop() { server.stop() }

    func configurePresentationHandler(
        _ handler: @escaping @MainActor @Sendable (BessieIntentRequest) -> BessieIntentResult
    ) {
        presentation.configure(handler)
    }

    func updateConnectionContext(
        connections: [BessieConnectionDefinition],
        selectedConnectionID: String,
        defaultProjectConnectionID: String
    ) {
        live.updateConnectionContext(
            connections: connections,
            selectedConnectionID: selectedConnectionID,
            defaultProjectConnectionID: defaultProjectConnectionID
        )
    }
}

private final class AppPanePresentationIntentPort: BessieIntentPresentationPort, @unchecked Sendable {
    private struct Cached {
        let binding: Data
        let result: BessieIntentResult
    }

    private let condition = NSCondition()
    private var handler: (@MainActor @Sendable (BessieIntentRequest) -> BessieIntentResult)?
    private var completed: [String: Cached] = [:]
    private var completionOrder: [String] = []
    private var inFlight: [String: Data] = [:]

    func configure(_ handler: @escaping @MainActor @Sendable (BessieIntentRequest) -> BessieIntentResult) {
        condition.withLock { self.handler = handler }
    }

    func executePresentation(_ request: BessieIntentRequest) -> BessieIntentResult {
        let binding: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            binding = try encoder.encode(JSONValue.object([
                "intent": .string(request.intent.rawValue),
                "params": .object(request.params),
            ]))
        } catch {
            return .failure(id: request.id, code: .invalidParams, message: "Could not bind presentation request.")
        }

        condition.lock()
        if let cached = completed[request.id] {
            condition.unlock()
            guard cached.binding == binding else {
                return .failure(id: request.id, code: .conflict, message: "Request ID was already used with different parameters.")
            }
            return cached.result
        }
        while let active = inFlight[request.id] {
            guard active == binding else {
                condition.unlock()
                return .failure(id: request.id, code: .conflict, message: "Request ID is in flight with different parameters.")
            }
            if !condition.wait(until: Date().addingTimeInterval(2)) {
                condition.unlock()
                return .failure(id: request.id, code: .unsupported, message: "Timed out waiting for the matching presentation request.")
            }
            if let cached = completed[request.id] {
                condition.unlock()
                return cached.result
            }
        }
        guard let handler else {
            condition.unlock()
            return .failure(id: request.id, code: .unsupported, message: "Pane presentation state is unavailable.")
        }
        inFlight[request.id] = binding
        condition.unlock()

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedIntentResult()
        DispatchQueue.main.async {
            let result = handler(request)
            resultBox.value = result
            self.complete(requestID: request.id, binding: binding, result: result)
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 2) == .success, let delivered = resultBox.value {
            return delivered
        }
        return .failure(id: request.id, code: .unsupported, message: "Timed out applying pane presentation intent; retry the same request ID.")
    }

    private func complete(requestID: String, binding: Data, result: BessieIntentResult) {
        condition.withLock {
            guard inFlight[requestID] == binding else { return }
            inFlight[requestID] = nil
            completed[requestID] = Cached(binding: binding, result: result)
            completionOrder.append(requestID)
            if completionOrder.count > 256 {
                completed[completionOrder.removeFirst()] = nil
            }
            condition.broadcast()
        }
    }
}

private final class LockedIntentResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BessieIntentResult?
    var value: BessieIntentResult? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
