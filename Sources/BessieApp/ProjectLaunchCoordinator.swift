import BessieCore
import Foundation

protocol ProjectLaunchServicing: Sendable {
    func updateConnection(_ connection: BessieProjectMaterializationConnection?)
    func materialize(
        _ project: BessieProject,
        on connection: BessieProjectMaterializationConnection,
        onProgress: @escaping @Sendable (BessieProjectMaterializationProgressFact) -> Void
    ) throws -> BessieProjectMaterializationResult
}

final class LiveProjectLaunchService: ProjectLaunchServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var currentConnection: BessieProjectMaterializationConnection?

    func updateConnection(_ connection: BessieProjectMaterializationConnection?) {
        lock.withLock { currentConnection = connection }
    }

    func materialize(
        _ project: BessieProject,
        on connection: BessieProjectMaterializationConnection,
        onProgress: @escaping @Sendable (BessieProjectMaterializationProgressFact) -> Void
    ) throws -> BessieProjectMaterializationResult {
        let api = HerdrSocketAPI(socketPath: connection.socketPath)
        return try BessieProjectMaterializer(
            api: api,
            connectionStatus: { [weak self] expected in
                guard let current = self?.lock.withLock({ self?.currentConnection }) else { return .disconnected }
                return current == expected ? .current : .changed
            },
            isCancelled: {
                withUnsafeCurrentTask { $0?.isCancelled ?? false }
            }
        ).materialize(project, on: connection, onProgress: onProgress)
    }
}

struct ProjectLaunchReview: Identifiable, Equatable {
    let project: BessieProject
    let connectionName: String
    var id: UUID { project.id }
}

struct ProjectOpeningState: Equatable {
    let projectID: UUID
    let projectName: String
}

struct ProjectLaunchFailurePresentation: Identifiable, Equatable {
    let project: BessieProject
    let failure: BessieProjectMaterializationFailure
    let canRetry: Bool
    var id: UUID { project.id }
}

struct BessieProjectRunningInstance: Equatable {
    let projectID: UUID
    let connectionID: String
    let socketPath: String
    let generation: UUID
    let workspaceID: String
    let tabIDsByRecipeID: [UUID: String]
    let paneIDsByRecipeID: [UUID: String]
}

struct ProjectWorkspaceHandoff: Equatable {
    let connection: BessieProjectMaterializationConnection
    let workspaceID: String
    let tabID: String?
    let paneID: String?
    let snapshot: HerdrSnapshot
}

final class ProjectLaunchProgressSink: @unchecked Sendable {
    private let receive: @MainActor (BessieProjectMaterializationProgressFact) -> Void

    init(receive: @escaping @MainActor (BessieProjectMaterializationProgressFact) -> Void) {
        self.receive = receive
    }

    func send(_ fact: BessieProjectMaterializationProgressFact) {
        Task { @MainActor in receive(fact) }
    }
}

extension ProjectLaunchServicing {
    func updateConnection(_: BessieProjectMaterializationConnection?) {}
}
