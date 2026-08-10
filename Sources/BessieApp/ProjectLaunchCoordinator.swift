import BessieCore
import Foundation

protocol ProjectLaunchServicing: Sendable {
    func updateConnections(_ connections: [String: BessieProjectMaterializationConnection])
    func materialize(
        _ project: BessieProject,
        on connection: BessieProjectMaterializationConnection,
        remoteFileAccess: SSHRemoteFileAccess?,
        onProgress: @escaping @Sendable (BessieProjectMaterializationProgressFact) -> Void
    ) throws -> BessieProjectMaterializationResult
}

struct ProjectLaunchTarget: Sendable {
    let connection: BessieProjectMaterializationConnection
    var snapshot: HerdrSnapshot
    let remoteFileAccess: SSHRemoteFileAccess?
}

enum ProjectLaunchTargetReadinessError: Error, Equatable, LocalizedError, Sendable {
    case notConfigured(connectionID: String)
    case startupFailed(connectionName: String, detail: String)
    case unavailable(connectionName: String, detail: String)
    case incompatible(connectionName: String, detail: String)
    case timedOut(connectionName: String, seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let connectionID):
            "The Project's target herd (\(connectionID)) is not configured in Bessie. Restore that connection or retarget the Project, then launch again."
        case .startupFailed(let connectionName, let detail):
            "Bessie could not start \(connectionName). \(detail) Correct the runtime startup problem, then launch again."
        case .unavailable(let connectionName, let detail):
            "\(connectionName) is unavailable. \(detail) Check its runtime or connection, then launch again."
        case .incompatible(let connectionName, let detail):
            "\(connectionName) is incompatible with this Bessie build. \(detail)"
        case .timedOut(let connectionName, let seconds):
            "\(connectionName) did not become ready within \(Self.durationLabel(seconds)). The connection attempt is still running; check its status, then launch again."
        }
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let rounded = seconds.rounded()
        if abs(seconds - rounded) < 0.001 {
            return "\(Int(rounded)) second\(rounded == 1 ? "" : "s")"
        }
        return "\(seconds.formatted(.number.precision(.fractionLength(1)))) seconds"
    }
}

final class LiveProjectLaunchService: ProjectLaunchServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var currentConnections: [String: BessieProjectMaterializationConnection] = [:]

    func updateConnections(_ connections: [String: BessieProjectMaterializationConnection]) {
        lock.withLock { currentConnections = connections }
    }

    func materialize(
        _ project: BessieProject,
        on connection: BessieProjectMaterializationConnection,
        remoteFileAccess: SSHRemoteFileAccess?,
        onProgress: @escaping @Sendable (BessieProjectMaterializationProgressFact) -> Void
    ) throws -> BessieProjectMaterializationResult {
        let api = HerdrSocketAPI(socketPath: connection.socketPath)
        let remoteFolderResolver: (@Sendable (BessieProjectFolder) throws -> String)?
        if let access = remoteFileAccess {
            remoteFolderResolver = { folder in
                let client = SSHRemoteFileClient(access: access)
                let canonicalPath = try client.canonicalPath(folder.path)
                let stat = try client.stat(canonicalPath)
                guard stat.exists else { throw WorkspacePathError.notFound }
                guard stat.isDirectory else { throw WorkspacePathError.notDirectory }
                return canonicalPath
            }
        } else {
            remoteFolderResolver = nil
        }
        return try BessieProjectMaterializer(
            api: api,
            connectionStatus: { [weak self] expected in
                guard let current = self?.lock.withLock({ self?.currentConnections[expected.definition.id] }) else {
                    return .disconnected
                }
                return current == expected ? .current : .changed
            },
            remoteFolderResolver: remoteFolderResolver,
            isCancelled: {
                withUnsafeCurrentTask { $0?.isCancelled ?? false }
            }
        ).materialize(project, on: connection, onProgress: onProgress)
    }
}

struct ProjectOpeningState: Equatable {
    let projectID: UUID
    let projectName: String
}

struct ProjectLaunchFailurePresentation: Identifiable, Equatable {
    let project: BessieProject
    let failure: BessieProjectMaterializationFailure
    let canRetry: Bool
    let connectionLabel: String
    var id: UUID { project.id }

    var actionableMessage: String {
        switch failure.ownerError {
        case .validation:
            return "Fix the Project's folder, tab, pane, or command settings, then launch it again."
        case .targetConnectionMismatch(let expectedConnectionID, _):
            return "This Project targets \(expectedConnectionID), not \(connectionLabel). Connect its target herd and launch it again."
        case .remoteFolderUnavailable(_, let path, let reason):
            return "The target folder \(path) is unavailable on \(connectionLabel). \(reason) Correct that target-host path, then launch again."
        case .remoteConnection:
            return "Reconnect \(connectionLabel) through Bessie's remote Herdr connection, then launch again."
        case .incompatibleConnection(let reason):
            return "\(connectionLabel) is not compatible with this Bessie build. \(reason)"
        case .invalidEndpoint:
            return "Bessie's Herdr connection to \(connectionLabel) changed. Reconnect that herd, then launch again."
        case .cancelled:
            return "The launch was canceled. No additional Herdr objects will be created."
        case .connectionLost:
            return "\(connectionLabel) disconnected during launch. Reconnect it, then inspect any partial workspace before retrying."
        case .connectionChanged:
            return "\(connectionLabel)'s Herdr session changed during launch. Reconnect it and inspect any partial workspace before retrying."
        case .invalidCommand:
            return "A startup command is empty. Edit that command before launching the Project again."
        case .duplicateRuntimeTabID, .duplicateRuntimePaneID:
            return "Herdr returned duplicate topology identifiers on \(connectionLabel). Refresh that herd before retrying."
        case .herdr(let error):
            return "\(error.localizedDescription) Check the Project's folder paths on \(connectionLabel), then retry."
        case .startup(let error):
            switch error {
            case .invalidCommand:
                return "A startup command is invalid. Edit it before launching the Project again."
            case .readinessTimedOut:
                return "A pane on \(connectionLabel) did not become ready for its startup command. Open the partial workspace and inspect the pane before retrying."
            case .echoTimedOut:
                return "A pane on \(connectionLabel) did not echo its startup command. Open the partial workspace and inspect the pane before retrying."
            case .cancelled:
                return "Startup command submission was canceled. Inspect any partial workspace before retrying."
            }
        case .verification:
            return "Herdr created Project topology on \(connectionLabel), but Bessie could not verify it. Open the partial workspace and inspect it before retrying."
        case .unexpected(let detail):
            return "Bessie could not launch the Project on \(connectionLabel). \(detail)"
        }
    }
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
    func updateConnections(_: [String: BessieProjectMaterializationConnection]) {}
}
