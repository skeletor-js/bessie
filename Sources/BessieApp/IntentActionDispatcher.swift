import BessieCore
import Foundation

enum BessiePilotIntentMapping {
    static func request(for action: HerdrAction, connectionID: String) -> BessieIntentRequest? {
        let intent: String
        let target: (String, String)
        switch action {
        case .paneFocus(let id):
            intent = "pane.focus"
            target = ("pane_id", id)
        case .workspaceFocus(let id):
            intent = "workspace.focus"
            target = ("workspace_id", id)
        case .workspaceClose(let id):
            intent = "workspace.close"
            target = ("workspace_id", id)
        default:
            return nil
        }
        return BessieIntentRequest(
            id: UUID().uuidString,
            intent: intent,
            params: ["connection_id": .string(connectionID), target.0: .string(target.1)]
        )
    }
}

final class BessieIntentActionDispatcher: @unchecked Sendable {
    private let live: AppIntentLivePort
    private let executor: BessieIntentExecutor

    init(
        live: AppIntentLivePort = AppIntentLivePort(),
        projects: any BessieIntentProjectReadPort = BessieProjectStore()
    ) {
        self.live = live
        executor = BessieIntentExecutor(live: live, projects: projects)
    }

    init(live: AppIntentLivePort, executor: BessieIntentExecutor) {
        self.live = live
        self.executor = executor
    }

    func execute(_ request: BessieIntentRequest) -> BessieIntentResult { executor.execute(request) }

    func update(client: HerdrActionClient?, connectionID: String, projection: HerdrSessionProjection?) {
        live.update(client: client, connectionID: connectionID, projection: projection)
    }

    func perform(
        _ actions: [HerdrAction],
        connectionID: String,
        confirmDestructive: Bool = false
    ) throws -> HerdrSessionProjection {
        guard !actions.isEmpty else { return try live.projection(connectionID: connectionID) }
        var projection: HerdrSessionProjection?
        for action in actions {
            if let request = BessiePilotIntentMapping.request(for: action, connectionID: connectionID) {
                var result = executor.execute(request)
                if confirmDestructive,
                   result.error?.code == .needsConfirmation,
                   let token = result.error?.confirmToken
                {
                    result = executor.execute(BessieIntentRequest(
                        id: request.id,
                        intent: request.intent,
                        params: request.params,
                        confirmToken: token
                    ))
                }
                guard result.ok else { throw IntentDispatchError(message: result.error?.message ?? "Intent execution failed.") }
                projection = try live.projection(connectionID: connectionID)
            } else {
                projection = try live.perform(action, connectionID: connectionID)
            }
        }
        return projection!
    }
}

private struct IntentDispatchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class AppIntentLivePort: BessieIntentLivePort, @unchecked Sendable {
    private struct State {
        var client: HerdrActionClient
        var projection: HerdrSessionProjection?
        var generation: UUID
    }

    private let lock = NSLock()
    private var states: [String: State] = [:]

    func update(client: HerdrActionClient?, connectionID: String, projection: HerdrSessionProjection?) {
        lock.withLock {
            if let client {
                states[connectionID] = State(client: client, projection: projection, generation: UUID())
            } else {
                states[connectionID] = nil
            }
        }
    }

    func isConnected(connectionID: String?) -> Bool {
        lock.withLock { connectionID.map { states[$0] != nil } ?? !states.isEmpty }
    }

    func projection(connectionID: String) throws -> HerdrSessionProjection {
        try lock.withLock {
            guard let projection = states[connectionID]?.projection else {
                throw IntentDispatchError(message: "Herdr connection '\(connectionID)' is not connected.")
            }
            return projection
        }
    }

    func perform(_ action: HerdrAction, connectionID: String) throws -> HerdrSessionProjection {
        let (client, requestGeneration) = try lock.withLock {
            guard let state = states[connectionID] else {
                throw IntentDispatchError(message: "Herdr connection '\(connectionID)' is not connected.")
            }
            return (state.client, state.generation)
        }
        let projection = try client.perform(action)
        lock.withLock {
            if states[connectionID]?.generation == requestGeneration {
                states[connectionID]?.projection = projection
            }
        }
        return projection
    }
}
