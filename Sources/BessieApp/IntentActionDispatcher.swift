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

    init() {
        let live = AppIntentLivePort()
        self.live = live
        executor = BessieIntentExecutor(live: live, projects: EmptyProjectReadPort())
    }

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

private final class AppIntentLivePort: BessieIntentLivePort, @unchecked Sendable {
    private let lock = NSLock()
    private var client: HerdrActionClient?
    private var connectionID: String?
    private var latestProjection: HerdrSessionProjection?
    private var generation = UUID()

    func update(client: HerdrActionClient?, connectionID: String, projection: HerdrSessionProjection?) {
        lock.withLock {
            generation = UUID()
            self.client = client
            self.connectionID = client == nil ? nil : connectionID
            latestProjection = projection
        }
    }

    func isConnected(connectionID: String?) -> Bool {
        lock.withLock { client != nil && (connectionID == nil || connectionID == self.connectionID) }
    }

    func projection(connectionID: String) throws -> HerdrSessionProjection {
        try lock.withLock {
            guard self.connectionID == connectionID, let projection = latestProjection else {
                throw IntentDispatchError(message: "Herdr connection '\(connectionID)' is not connected.")
            }
            return projection
        }
    }

    func perform(_ action: HerdrAction, connectionID: String) throws -> HerdrSessionProjection {
        let (client, requestGeneration) = try lock.withLock {
            guard self.connectionID == connectionID, let client = self.client else {
                throw IntentDispatchError(message: "Herdr connection '\(connectionID)' is not connected.")
            }
            return (client, generation)
        }
        let projection = try client.perform(action)
        lock.withLock {
            if generation == requestGeneration { latestProjection = projection }
        }
        return projection
    }
}

private struct EmptyProjectReadPort: BessieIntentProjectReadPort {
    func listProjects() throws -> [BessieProject] { [] }
    func project(id: UUID) throws -> BessieProject? { nil }
}
