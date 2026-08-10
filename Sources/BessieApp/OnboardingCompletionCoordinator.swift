import BessieCore
import Foundation

struct OnboardingMaterializationResult: Equatable {
    let connectionID: String
    let workspaceID: String
    let tabID: String
    let paneID: String
}

@MainActor
protocol OnboardingMaterializationService {
    func materialize(
        _ attempt: PendingOnboardingAttempt,
        progress: (OnboardingCompletionStage) throws -> Void
    ) async throws -> OnboardingMaterializationResult
}

enum OnboardingMaterializationError: LocalizedError {
    case connectionUnavailable(String)
    case ambiguousTopology

    var errorDescription: String? {
        switch self {
        case .connectionUnavailable(let detail): detail
        case .ambiguousTopology:
            "Herdr did not report exactly one fresh workspace, tab, and pane. No existing topology was adopted; reconnect and resume setup."
        }
    }
}

@MainActor
final class OnboardingCompletionCoordinator: ObservableObject {
    @Published private(set) var stage: OnboardingCompletionStage = .idle
    @Published private(set) var attempt: PendingOnboardingAttempt?
    @Published private(set) var error: String?
    private let store: PendingOnboardingAttemptStore
    private let clearAttempt: () throws -> Void
    private var submitting = false
    private var service: (any OnboardingMaterializationService)?

    init(
        store: PendingOnboardingAttemptStore? = nil,
        service: (any OnboardingMaterializationService)? = nil,
        clearAttempt: (() throws -> Void)? = nil
    ) {
        let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bessie/pending-onboarding-attempt.json")
        let resolvedStore = store ?? PendingOnboardingAttemptStore(url: defaultURL)
        self.store = resolvedStore
        self.clearAttempt = clearAttempt ?? { try resolvedStore.clear() }
        self.service = service
        do { attempt = try self.store.load(); stage = attempt?.stage ?? .idle }
        catch { self.error = error.localizedDescription; stage = .failed }
    }

    var canSubmit: Bool { !submitting && stage != .completed }
    var materializationStarted: Bool { attempt?.stage.hasMaterialized == true }

    var isSubmitting: Bool { submitting }

    func configure(service: any OnboardingMaterializationService) {
        if self.service == nil { self.service = service }
    }

    func begin(connectionID: String, path: String) throws -> PendingOnboardingAttempt {
        if let attempt { return attempt }
        let created = try PendingOnboardingAttempt(connectionID: connectionID, path: path)
        try persist(created, stage: .validating)
        return created
    }

    func submit(connectionID: String, path: String, operation: @escaping (PendingOnboardingAttempt) async throws -> Void) {
        guard canSubmit else { return }
        submitting = true; error = nil
        Task {
            do { try await operation(try begin(connectionID: connectionID, path: path)) }
            catch { fail(error) }
            submitting = false
        }
    }

    func submit(connectionID: String, path: String) {
        guard let service else {
            fail(OnboardingMaterializationError.connectionUnavailable("Setup materialization is unavailable. Reconnect to Herdr and try again."))
            return
        }
        submit(connectionID: connectionID, path: path) { [weak self] attempt in
            guard let self else { return }
            try self.advance(.startingSession)
            let result = try await service.materialize(attempt) { stage in
                try self.advance(stage)
            }
            try self.advance(.waitingForFirstFrame, connectionID: result.connectionID,
                             ids: (result.workspaceID, result.tabID, result.paneID))
        }
    }

    func advance(_ next: OnboardingCompletionStage, connectionID: String? = nil,
                 ids: (workspace: String?, tab: String?, pane: String?) = (nil, nil, nil)) throws {
        guard var attempt else { return }
        attempt.connectionID = connectionID ?? attempt.connectionID
        attempt.workspaceID = ids.workspace ?? attempt.workspaceID
        attempt.tabID = ids.tab ?? attempt.tabID
        attempt.paneID = ids.pane ?? attempt.paneID
        if next == .completed {
            do {
                try clearAttempt()
            } catch {
                self.error = "Bessie couldn't finish setup cleanup. \(error.localizedDescription)"
                throw error
            }
            self.attempt = nil
            stage = .completed
            error = nil
            return
        }
        try persist(attempt, stage: next)
    }

    func cancelBeforeMaterialization() throws {
        guard !materializationStarted else { return }
        try store.clear(); attempt = nil; stage = .idle; error = nil
    }

    private func persist(_ value: PendingOnboardingAttempt, stage: OnboardingCompletionStage) throws {
        var value = value; value.stage = stage; try store.save(value)
        attempt = value; self.stage = stage
    }

    private func fail(_ failure: Error) {
        error = failure.localizedDescription; stage = .failed
        if var attempt { attempt.stage = .failed; try? store.save(attempt); self.attempt = attempt }
    }
}

@MainActor
final class ProductionOnboardingMaterializationService: OnboardingMaterializationService {
    private unowned let fleet: ConnectionFleetViewModel
    private let remoteBootstrap: RemoteOnboardingBootstrap
    private let register: @MainActor (BessieConnectionDefinition) throws -> Void

    init(fleet: ConnectionFleetViewModel, remoteBootstrap: RemoteOnboardingBootstrap,
         register: @escaping @MainActor (BessieConnectionDefinition) throws -> Void) {
        self.fleet = fleet; self.remoteBootstrap = remoteBootstrap; self.register = register
    }

    func materialize(
        _ attempt: PendingOnboardingAttempt,
        progress: (OnboardingCompletionStage) throws -> Void
    ) async throws -> OnboardingMaterializationResult {
        guard let definition = fleet.connectionDefinitions.first(where: { $0.id == attempt.connectionID }) else {
            throw OnboardingMaterializationError.connectionUnavailable("The selected connection no longer exists. Choose it again and resume setup.")
        }
        if definition.kind == .ssh {
            try progress(.connecting)
            let expected = attempt.workspaceID.flatMap { workspace in attempt.tabID.flatMap { tab in attempt.paneID.map { (workspace, tab, $0) } } }
            let result = try await Task.detached { [remoteBootstrap] in
                try remoteBootstrap.bootstrap(definition: definition, path: attempt.path,
                                              sessionName: attempt.sessionName, expectedIDs: expected)
            }.value
            try progress(.adoptingWorkspace)
            return OnboardingMaterializationResult(connectionID: result.connection.id, workspaceID: result.workspaceID,
                                                   tabID: result.tabID, paneID: result.paneID)
        }
        let localDefinition: BessieConnectionDefinition
        if definition.id == BessieConnectionDefinition.localBessie.id {
            localDefinition = try BessieConnectionDefinition(
                id: attempt.attemptID, name: "This Mac · Setup", kind: .local, session: attempt.sessionName
            ).validated()
            try register(localDefinition)
        } else {
            localDefinition = definition
        }
        try progress(.connecting)
        var localModel: ConnectionViewModel?
        for _ in 0..<80 {
            if let candidate = fleet.activate(connectionID: localDefinition.id), candidate.projection != nil {
                localModel = candidate
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let model = localModel, let before = model.projection else {
            throw OnboardingMaterializationError.connectionUnavailable(
                "The selected Herdr connection is not authoritative yet. Wait for Connect, then resume setup."
            )
        }
        try progress(.creatingWorkspace)
        let projection: HerdrSessionProjection = try await withCheckedThrowingContinuation { continuation in
            model.perform(.workspaceCreate(cwd: attempt.path, label: "Bessie setup", focus: true)) {
                continuation.resume(returning: $0)
            } failure: {
                continuation.resume(throwing: OnboardingMaterializationError.connectionUnavailable(
                    model.actionError ?? "Herdr rejected workspace creation. Check the selected directory and resume setup."
                ))
            }
        }
        let oldWorkspaces = Set(before.workspaces.map(\.id))
        let oldTabs = Set(before.tabs.map(\.id))
        let oldPanes = Set(before.panes.map(\.id))
        let workspaces = projection.workspaces.filter { !oldWorkspaces.contains($0.id) }
        let tabs = projection.tabs.filter { !oldTabs.contains($0.id) }
        let panes = projection.panes.filter { !oldPanes.contains($0.id) }
        guard workspaces.count == 1, tabs.count == 1, panes.count == 1,
              tabs[0].workspaceID == workspaces[0].id,
              panes[0].workspaceID == workspaces[0].id,
              panes[0].tabID == tabs[0].id,
              let effectiveCWD = panes[0].effectiveCWD,
              OnboardingPathValidator.localPathsAreEquivalent(effectiveCWD, attempt.path)
        else { throw OnboardingMaterializationError.ambiguousTopology }
        return OnboardingMaterializationResult(
            connectionID: localDefinition.id,
            workspaceID: workspaces[0].id,
            tabID: tabs[0].id,
            paneID: panes[0].id
        )
    }
}
