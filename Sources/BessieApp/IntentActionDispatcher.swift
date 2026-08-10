import BessieCore
import Foundation

enum HerdrDefaultCapturedCloseTarget: Equatable, Sendable {
    case workspace(id: String)
    case tab(id: String, workspaceID: String)
    case pane(id: String, workspaceID: String, terminalID: String)
}

enum HerdrDefaultTopologyIntent: Equatable, Sendable {
    case beginResize
    case createWorkspace
    case createTab(workspaceID: String, label: String)
    case nextTab
    case previousTab
    case focusTab(Int)
    case renameTab(id: String, label: String)
    case closeTab(id: String)
    case splitPane(SplitDirection)
    case splitPaneTarget(id: String, direction: SplitDirection)
    case focusPane(PaneDirection)
    case focusPaneTarget(id: String)
    case swapPane(PaneDirection)
    case swapPaneTarget(id: String, direction: PaneDirection)
    case cyclePane(HerdrPrefixPaneCycleDirection)
    case closePane(id: String)
    case toggleZoom
    case toggleZoomTarget(id: String)
    case resizePane(id: String, direction: PaneDirection)
    case renamePane(id: String, label: String?)
    case renameWorkspace(id: String, label: String)
    case closeWorkspace(id: String)
    case capturedClose(target: HerdrDefaultCapturedCloseTarget, action: HerdrAction)
}

enum HerdrDefaultResolution: Equatable, Sendable {
    case actions([HerdrAction])
    case noOp
}

struct HerdrDefaultResolutionError: LocalizedError, Equatable, Sendable {
    let message: String
    var errorDescription: String? { message }
}

enum HerdrDefaultTopologyResolver {
    static func resolve(
        _ intent: HerdrDefaultTopologyIntent,
        in projection: HerdrSessionProjection
    ) throws -> HerdrDefaultResolution {
        switch intent {
        case .beginResize:
            return .noOp
        case .createWorkspace:
            return .actions([.workspaceCreate(cwd: nil, label: nil, focus: true)])
        case .createTab(let workspaceID, let label):
            try require(projection.workspaces.contains { $0.id == workspaceID }, "workspace", workspaceID)
            return .actions([.tabCreate(
                workspaceID: workspaceID,
                cwd: nil,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                focus: true
            )])
        case .nextTab:
            return tabCycle(offset: 1, projection: projection)
        case .previousTab:
            return tabCycle(offset: -1, projection: projection)
        case .focusTab(let index):
            guard let workspaceID = projection.focusedWorkspace?.id else { return .noOp }
            let tabs = projection.tabs.filter { $0.workspaceID == workspaceID }
            guard tabs.indices.contains(index - 1) else { return .noOp }
            return .actions([.tabFocus(id: tabs[index - 1].id)])
        case .renameTab(let id, let label):
            try require(projection.tabs.contains { $0.id == id }, "tab", id)
            return .actions([.tabRename(id: id, label: label)])
        case .closeTab(let id):
            try require(projection.tabs.contains { $0.id == id }, "tab", id)
            return .actions([.tabClose(id: id)])
        case .splitPane(let direction):
            guard let paneID = projection.focusedPane?.id else { return .noOp }
            return .actions([.paneSplit(
                targetPaneID: paneID,
                direction: direction,
                ratio: nil,
                cwd: nil,
                focus: true
            )])
        case .splitPaneTarget(let id, let direction):
            try require(projection.panes.contains { $0.id == id }, "pane", id)
            return .actions([.paneSplit(
                targetPaneID: id,
                direction: direction,
                ratio: nil,
                cwd: nil,
                focus: true
            )])
        case .focusPane(let direction):
            guard let paneID = projection.focusedPane?.id else { return .noOp }
            return .actions([.paneFocusDirection(sourcePaneID: paneID, direction: direction)])
        case .focusPaneTarget(let id):
            try require(projection.panes.contains { $0.id == id }, "pane", id)
            return .actions([.paneFocus(id: id)])
        case .swapPane(let direction):
            guard let paneID = projection.focusedPane?.id else { return .noOp }
            return .actions([.paneSwap(id: paneID, direction: direction)])
        case .swapPaneTarget(let id, let direction):
            try require(projection.panes.contains { $0.id == id }, "pane", id)
            return .actions([.paneSwap(id: id, direction: direction)])
        case .cyclePane(let direction):
            guard let tabID = projection.focusedTab?.id,
                  let paneID = projection.focusedPane?.id,
                  let paneIDs = projection.layouts[tabID]?.root.paneIDs,
                  !paneIDs.isEmpty,
                  let currentIndex = paneIDs.firstIndex(of: paneID)
            else { return .noOp }
            let offset = direction == .next ? 1 : -1
            let index = (currentIndex + offset + paneIDs.count) % paneIDs.count
            return .actions([.paneFocus(id: paneIDs[index])])
        case .closePane(let id):
            try require(projection.panes.contains { $0.id == id }, "pane", id)
            return .actions([.paneClose(id: id)])
        case .toggleZoom:
            guard let paneID = projection.focusedPane?.id else { return .noOp }
            return .actions([.paneZoom(id: paneID, mode: .toggle)])
        case .toggleZoomTarget(let id):
            try require(projection.panes.contains { $0.id == id }, "pane", id)
            return .actions([.paneZoom(id: id, mode: .toggle)])
        case .resizePane(let id, let direction):
            try require(projection.panes.contains { $0.id == id }, "pane", id)
            return .actions([.paneResize(id: id, direction: direction, amount: 0.05)])
        case .renamePane(let id, let label):
            try require(projection.panes.contains { $0.id == id }, "pane", id)
            return .actions([.paneRename(id: id, label: label)])
        case .renameWorkspace(let id, let label):
            try require(projection.workspaces.contains { $0.id == id }, "workspace", id)
            return .actions([.workspaceRename(id: id, label: label)])
        case .closeWorkspace(let id):
            try require(projection.workspaces.contains { $0.id == id }, "workspace", id)
            return .actions([.workspaceClose(id: id)])
        case .capturedClose(let target, let action):
            try validateCapturedClose(target: target, action: action, projection: projection)
            return .actions([action])
        }
    }

    private static func tabCycle(
        offset: Int,
        projection: HerdrSessionProjection
    ) -> HerdrDefaultResolution {
        guard let workspaceID = projection.focusedWorkspace?.id else { return .noOp }
        let tabs = projection.tabs.filter { $0.workspaceID == workspaceID }
        guard !tabs.isEmpty else { return .noOp }
        let currentIndex = projection.focusedTab.flatMap { focused in
            tabs.firstIndex { $0.id == focused.id }
        } ?? 0
        let index = (currentIndex + offset + tabs.count) % tabs.count
        return .actions([.tabFocus(id: tabs[index].id)])
    }

    private static func require(_ condition: Bool, _ kind: String, _ id: String) throws {
        guard condition else {
            throw HerdrDefaultResolutionError(message: "The captured \(kind) '\(id)' is no longer available.")
        }
    }

    private static func validateCapturedClose(
        target: HerdrDefaultCapturedCloseTarget,
        action: HerdrAction,
        projection: HerdrSessionProjection
    ) throws {
        let validAction: Bool
        switch target {
        case .workspace(let id):
            try require(projection.workspaces.contains { $0.id == id }, "workspace", id)
            validAction = action == .workspaceClose(id: id)
        case .tab(let id, let workspaceID):
            try require(
                projection.tabs.contains { $0.id == id && $0.workspaceID == workspaceID },
                "tab",
                id
            )
            validAction = action == .tabClose(id: id) || action == .workspaceClose(id: workspaceID)
        case .pane(let id, let workspaceID, let terminalID):
            try require(
                projection.panes.contains {
                    $0.id == id
                        && $0.workspaceID == workspaceID
                        && $0.terminalID == terminalID
                },
                "pane",
                id
            )
            validAction = action == .paneClose(id: id) || action == .workspaceClose(id: workspaceID)
        }
        guard validAction else {
            throw HerdrDefaultResolutionError(message: "The captured close mutation is no longer valid.")
        }
    }
}

extension HerdrDefaultTopologyIntent {
    init?(action: HerdrAction) {
        switch action {
        case .workspaceCreate(let cwd, let label, let focus) where cwd == nil && label == nil && focus:
            self = .createWorkspace
        case .workspaceRename(let id, let label):
            self = .renameWorkspace(id: id, label: label)
        case .workspaceClose(let id):
            self = .closeWorkspace(id: id)
        case .tabCreate(let workspaceID, let cwd, let label, let focus) where cwd == nil && focus:
            self = .createTab(workspaceID: workspaceID, label: label ?? "")
        case .tabRename(let id, let label):
            self = .renameTab(id: id, label: label)
        case .tabClose(let id):
            self = .closeTab(id: id)
        case .paneSplit(let id, let direction, _, let cwd, let focus) where cwd == nil && focus:
            self = .splitPaneTarget(id: id, direction: direction)
        case .paneFocus(let id):
            self = .focusPaneTarget(id: id)
        case .paneFocusDirection(_, let direction):
            self = .focusPane(direction)
        case .paneResize(let id, let direction, _):
            self = .resizePane(id: id, direction: direction)
        case .paneSwap(let id, let direction):
            self = .swapPaneTarget(id: id, direction: direction)
        case .paneZoom(let id, .toggle):
            self = .toggleZoomTarget(id: id)
        case .paneRename(let id, let label):
            self = .renamePane(id: id, label: label)
        case .paneClose(let id):
            self = .closePane(id: id)
        default:
            return nil
        }
    }
}

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

enum HerdrDefaultDispatchRejection: Equatable, Sendable {
    case disconnected
    case generationChanged
    case supersededAfterAcknowledgement
    case preflightFailed(String)
    case invalidTarget(String)
}

struct HerdrDefaultDispatchFailure: Equatable, Sendable {
    let disposition: HerdrMutationDisposition
    let completedRequestCount: Int
    let message: String
}

enum HerdrDefaultDispatchResult: Equatable, Sendable {
    case applied(HerdrSessionProjection)
    case noOp(HerdrSessionProjection?)
    case rejected(HerdrDefaultDispatchRejection)
    case failed(HerdrDefaultDispatchFailure, recovered: HerdrSessionProjection?)
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

    @discardableResult
    func connect(
        client: HerdrActionClient,
        connectionID: String,
        projection: HerdrSessionProjection?
    ) -> UUID {
        live.connect(client: client, connectionID: connectionID, projection: projection)
    }

    func refreshProjection(
        _ projection: HerdrSessionProjection,
        connectionID: String,
        generation: UUID
    ) {
        live.refreshProjection(projection, connectionID: connectionID, generation: generation)
    }

    func disconnect(connectionID: String, generation: UUID? = nil) {
        live.disconnect(connectionID: connectionID, generation: generation)
    }

    func dispatchHerdrDefault(
        _ intent: HerdrDefaultTopologyIntent,
        connectionID: String
    ) async -> HerdrDefaultDispatchResult {
        await live.dispatchHerdrDefault(intent, connectionID: connectionID)
    }

    func perform(
        _ actions: [HerdrAction],
        connectionID: String,
        confirmDestructive: Bool = false
    ) throws -> HerdrSessionProjection {
        guard !actions.isEmpty else { return try live.projection(connectionID: connectionID) }

        // Pure navigation/mutation batches share one Herdr snapshot. workspace.close still
        // needs the confirmation intent path, so it stays sequential.
        if actions.allSatisfy({ !Self.requiresConfirmationIntentPath($0) }) {
            return try live.perform(actions, connectionID: connectionID)
        }

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

    private static func requiresConfirmationIntentPath(_ action: HerdrAction) -> Bool {
        if case .workspaceClose = action { return true }
        return false
    }

    func installProjection(_ projection: HerdrSessionProjection, connectionID: String) {
        live.installProjection(projection, connectionID: connectionID)
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
    private let mutationLane = DispatchQueue(label: "work.superbud.Bessie.herdr-mutation-lane")
    private let ioQueue = DispatchQueue(
        label: "work.superbud.Bessie.herdr-mutation-io",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var states: [String: State] = [:]
    private var laneGenerations: [String: UUID] = [:]
    private var configuredConnections: [BessieConnectionDefinition] = []
    private var selectedConnectionID: String?
    private var defaultProjectConnectionID: String?

    func update(client: HerdrActionClient?, connectionID: String, projection: HerdrSessionProjection?) {
        if let client {
            connect(client: client, connectionID: connectionID, projection: projection)
        } else {
            disconnect(connectionID: connectionID)
        }
    }

    @discardableResult
    func connect(
        client: HerdrActionClient,
        connectionID: String,
        projection: HerdrSessionProjection?
    ) -> UUID {
        let generation = UUID()
        lock.withLock {
            states[connectionID] = State(
                client: client,
                projection: projection,
                generation: generation
            )
            mutationLane.async { [weak self] in
                self?.laneGenerations[connectionID] = generation
            }
        }
        return generation
    }

    func refreshProjection(
        _ projection: HerdrSessionProjection,
        connectionID: String,
        generation: UUID
    ) {
        lock.withLock {
            guard states[connectionID]?.generation == generation else { return }
            states[connectionID]?.projection = projection
        }
    }

    func disconnect(connectionID: String, generation: UUID? = nil) {
        lock.withLock {
            if let generation, states[connectionID]?.generation != generation { return }
            states[connectionID] = nil
            mutationLane.async { [weak self] in
                self?.laneGenerations[connectionID] = nil
            }
        }
    }

    func isConnected(connectionID: String?) -> Bool {
        lock.withLock { connectionID.map { states[$0] != nil } ?? !states.isEmpty }
    }

    func updateConnectionContext(
        connections: [BessieConnectionDefinition],
        selectedConnectionID: String,
        defaultProjectConnectionID: String
    ) {
        lock.withLock {
            configuredConnections = connections
            self.selectedConnectionID = selectedConnectionID
            self.defaultProjectConnectionID = defaultProjectConnectionID
            let enabledIDs = Set(connections.lazy.filter(\.enabled).map(\.id))
            let removedIDs = states.keys.filter { !enabledIDs.contains($0) }
            states = states.filter { enabledIDs.contains($0.key) }
            for id in removedIDs {
                mutationLane.async { [weak self] in self?.laneGenerations[id] = nil }
            }
        }
    }

    func connectionContexts(connectionID: String?) -> [BessieIntentConnectionContext] {
        lock.withLock {
            configuredConnections.compactMap { connection in
                guard connectionID == nil || connection.id == connectionID else { return nil }
                return BessieIntentConnectionContext(
                    id: connection.id,
                    label: connection.name,
                    kind: connection.kind,
                    sshHost: connection.sshHost,
                    enabled: connection.enabled,
                    selected: connection.id == selectedConnectionID,
                    defaultProjectTarget: connection.id == defaultProjectConnectionID,
                    connected: states[connection.id] != nil
                )
            }
        }
    }

    func projection(connectionID: String) throws -> HerdrSessionProjection {
        try lock.withLock {
            guard configuredConnections.contains(where: { $0.id == connectionID && $0.enabled }),
                  let projection = states[connectionID]?.projection else {
                throw IntentDispatchError(message: "Herdr connection '\(connectionID)' is not connected.")
            }
            return projection
        }
    }

    public func perform(_ action: HerdrAction, connectionID: String) throws -> HerdrSessionProjection {
        if let intent = HerdrDefaultTopologyIntent(action: action) {
            return try projection(from: dispatchHerdrDefaultSynchronously(
                intent,
                connectionID: connectionID
            ))
        }
        return try perform([action], connectionID: connectionID)
    }

    func perform(_ actions: [HerdrAction], connectionID: String) throws -> HerdrSessionProjection {
        guard !actions.isEmpty else { return try projection(connectionID: connectionID) }
        if actions.count == 1, let action = actions.first,
           let intent = HerdrDefaultTopologyIntent(action: action) {
            return try projection(from: dispatchHerdrDefaultSynchronously(
                intent,
                connectionID: connectionID
            ))
        }
        let (client, requestGeneration) = try lock.withLock {
            guard configuredConnections.contains(where: { $0.id == connectionID && $0.enabled }),
                  let state = states[connectionID] else {
                throw IntentDispatchError(message: "Herdr connection '\(connectionID)' is not connected.")
            }
            return (state.client, state.generation)
        }
        _ = try client.snapshot()
        let attemptBox = HerdrActionAttemptBox()
        let attemptFinished = DispatchSemaphore(value: 0)
        lock.lock()
        guard states[connectionID]?.generation == requestGeneration else {
            lock.unlock()
            throw IntentDispatchError(message: "The Herdr connection changed before dispatch.")
        }
        mutationLane.async { [weak self] in
            let attempt: Result<HerdrActionReceipt, HerdrActionAttemptFailure>
            if self?.laneGenerations[connectionID] == requestGeneration {
                attempt = client.performRequests(actions)
            } else {
                attempt = .failure(.init(
                    disposition: .definitelyUnsent,
                    completedRequestCount: 0,
                    underlying: IntentDispatchError(message: "The Herdr connection changed before dispatch.")
                ))
            }
            attemptBox.store(attempt)
            attemptFinished.signal()
        }
        lock.unlock()
        attemptFinished.wait()
        let attempt = attemptBox.value!
        let receipt: HerdrActionReceipt
        switch attempt {
        case .success(let value):
            receipt = value
        case .failure(let failure):
            if failure.disposition == .mutationOutcomeUnknown {
                _ = recover(client: client, connectionID: connectionID, generation: requestGeneration)
            }
            throw failure
        }
        guard lock.withLock({ states[connectionID]?.generation == requestGeneration }) else {
            throw IntentDispatchError(
                message: "Herdr acknowledged the command, but the connection changed before reconciliation."
            )
        }
        let reconciled: HerdrSessionProjection
        do {
            reconciled = try client.snapshot()
        } catch {
            let failure = HerdrActionAttemptFailure(
                disposition: .mutationOutcomeUnknown,
                completedRequestCount: receipt.completedRequestCount,
                underlying: error
            )
            _ = recover(client: client, connectionID: connectionID, generation: requestGeneration)
            throw failure
        }
        guard install(reconciled, connectionID: connectionID, generation: requestGeneration) else {
            throw IntentDispatchError(
                message: "Herdr acknowledged the command, but the connection changed before reconciliation."
            )
        }
        return reconciled
    }

    func dispatchHerdrDefault(
        _ intent: HerdrDefaultTopologyIntent,
        connectionID: String
    ) async -> HerdrDefaultDispatchResult {
        await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .rejected(.disconnected))
                    return
                }
                self.prepareHerdrDefaultDispatch(
                    intent,
                    connectionID: connectionID,
                    completion: { continuation.resume(returning: $0) }
                )
            }
        }
    }

    private func dispatchHerdrDefaultSynchronously(
        _ intent: HerdrDefaultTopologyIntent,
        connectionID: String
    ) -> HerdrDefaultDispatchResult {
        let result = HerdrDefaultDispatchResultBox()
        let finished = DispatchSemaphore(value: 0)
        ioQueue.async { [weak self] in
            guard let self else {
                result.store(.rejected(.disconnected))
                finished.signal()
                return
            }
            self.prepareHerdrDefaultDispatch(intent, connectionID: connectionID) {
                result.store($0)
                finished.signal()
            }
        }
        finished.wait()
        return result.value!
    }

    private func projection(from result: HerdrDefaultDispatchResult) throws -> HerdrSessionProjection {
        switch result {
        case .applied(let projection):
            return projection
        case .noOp(let projection):
            guard let projection else {
                throw IntentDispatchError(message: "Herdr returned no current session projection.")
            }
            return projection
        case .rejected(let rejection):
            throw IntentDispatchError(message: String(describing: rejection))
        case .failed(let failure, _):
            throw IntentDispatchError(message: failure.message)
        }
    }

    private func prepareHerdrDefaultDispatch(
        _ intent: HerdrDefaultTopologyIntent,
        connectionID: String,
        completion: @escaping @Sendable (HerdrDefaultDispatchResult) -> Void
    ) {
        guard let lease = lock.withLock({ states[connectionID].map { ($0.client, $0.generation) } }) else {
            completion(.rejected(.disconnected))
            return
        }
        let client = lease.0
        let generation = lease.1
        let preflight: HerdrSessionProjection
        do {
            preflight = try client.snapshot()
        } catch {
            completion(.rejected(.preflightFailed(error.localizedDescription)))
            return
        }
        let resolution: HerdrDefaultResolution
        do {
            resolution = try HerdrDefaultTopologyResolver.resolve(intent, in: preflight)
        } catch {
            completion(.rejected(.invalidTarget(error.localizedDescription)))
            return
        }
        if resolution == .noOp {
            if install(preflight, connectionID: connectionID, generation: generation) {
                completion(.noOp(preflight))
            } else {
                completion(.rejected(.generationChanged))
            }
            return
        }
        guard case .actions(let actions) = resolution else { return }

        lock.lock()
        guard states[connectionID]?.generation == generation else {
            lock.unlock()
            completion(.rejected(.generationChanged))
            return
        }
        mutationLane.async { [weak self] in
            guard let self else {
                completion(.rejected(.disconnected))
                return
            }
            guard self.laneGenerations[connectionID] == generation else {
                completion(.rejected(.generationChanged))
                return
            }
            let attempt = client.performRequests(actions)
            self.ioQueue.async {
                self.finishHerdrDefaultDispatch(
                    attempt,
                    client: client,
                    connectionID: connectionID,
                    generation: generation,
                    completion: completion
                )
            }
        }
        lock.unlock()
    }

    private func finishHerdrDefaultDispatch(
        _ attempt: Result<HerdrActionReceipt, HerdrActionAttemptFailure>,
        client: HerdrActionClient,
        connectionID: String,
        generation: UUID,
        completion: @escaping @Sendable (HerdrDefaultDispatchResult) -> Void
    ) {
        switch attempt {
        case .success(let receipt):
            guard lock.withLock({ states[connectionID]?.generation == generation }) else {
                completion(.rejected(.supersededAfterAcknowledgement))
                return
            }
            do {
                let projection = try client.snapshot()
                guard install(projection, connectionID: connectionID, generation: generation) else {
                    completion(.rejected(.supersededAfterAcknowledgement))
                    return
                }
                completion(.applied(projection))
            } catch {
                let failure = HerdrDefaultDispatchFailure(
                    disposition: .mutationOutcomeUnknown,
                    completedRequestCount: receipt.completedRequestCount,
                    message: error.localizedDescription
                )
                completion(.failed(
                    failure,
                    recovered: recover(client: client, connectionID: connectionID, generation: generation)
                ))
            }
        case .failure(let attemptFailure):
            let failure = HerdrDefaultDispatchFailure(
                disposition: attemptFailure.disposition,
                completedRequestCount: attemptFailure.completedRequestCount,
                message: attemptFailure.localizedDescription
            )
            let recovered = attemptFailure.disposition == .mutationOutcomeUnknown
                ? recover(client: client, connectionID: connectionID, generation: generation)
                : nil
            completion(.failed(failure, recovered: recovered))
        }
    }

    private func recover(
        client: HerdrActionClient,
        connectionID: String,
        generation: UUID
    ) -> HerdrSessionProjection? {
        guard lock.withLock({ states[connectionID]?.generation == generation }),
              let projection = try? client.snapshot(),
              install(projection, connectionID: connectionID, generation: generation)
        else { return nil }
        return projection
    }

    @discardableResult
    private func install(
        _ projection: HerdrSessionProjection,
        connectionID: String,
        generation: UUID
    ) -> Bool {
        lock.withLock {
            guard states[connectionID]?.generation == generation else { return false }
            states[connectionID]?.projection = projection
            return true
        }
    }

    /// Install a Bessie-side optimistic projection without invalidating in-flight generations.
    func installProjection(_ projection: HerdrSessionProjection, connectionID: String) {
        lock.withLock {
            states[connectionID]?.projection = projection
        }
    }
}

private final class HerdrActionAttemptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<HerdrActionReceipt, HerdrActionAttemptFailure>?

    var value: Result<HerdrActionReceipt, HerdrActionAttemptFailure>? {
        lock.withLock { stored }
    }

    func store(_ value: Result<HerdrActionReceipt, HerdrActionAttemptFailure>) {
        lock.withLock { stored = value }
    }
}

private final class HerdrDefaultDispatchResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: HerdrDefaultDispatchResult?

    var value: HerdrDefaultDispatchResult? { lock.withLock { stored } }

    func store(_ value: HerdrDefaultDispatchResult) {
        lock.withLock { stored = value }
    }
}
