import Foundation

public protocol BessieProjectMaterializationAPI: HerdrMutationAPI {
    var socketPath: String { get }
    func ping() throws -> HerdrServerIdentity
}

extension HerdrSocketAPI: BessieProjectMaterializationAPI {}

public struct BessieProjectMaterializationConnection: Equatable, Sendable {
    public let definition: BessieConnectionDefinition
    public let socketPath: String
    public let generation: UUID
    public let identity: HerdrServerIdentity

    public init(
        definition: BessieConnectionDefinition,
        socketPath: String,
        generation: UUID,
        identity: HerdrServerIdentity
    ) {
        self.definition = definition
        let trimmedSocketPath = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.socketPath = trimmedSocketPath.isEmpty
            ? ""
            : URL(fileURLWithPath: trimmedSocketPath).standardizedFileURL.path
        self.generation = generation
        self.identity = identity
    }
}

public enum BessieProjectMaterializationConnectionStatus: Equatable, Sendable {
    case current
    case disconnected
    case changed
}

public struct BessieProjectMaterializationPlan: Equatable, Sendable {
    public let project: BessieProject
    public let connection: BessieProjectMaterializationConnection

    public init(project: BessieProject, connection: BessieProjectMaterializationConnection) {
        self.project = project
        self.connection = connection
    }
}

public enum BessieProjectMaterializationStage: String, Equatable, Sendable {
    case validatingProject
    case validatingConnection
    case creatingWorkspace
    case verifyingCreation
    case renamingInitialTab
    case creatingTab
    case splittingPane
    case labelingPane
    case verifyingTopology
    case waitingForCommandReadiness
    case submittingCommandText
    case waitingForCommandEcho
    case submittingCommandEnter
    case verifyingComplete
}

public enum BessieProjectMaterializationAttempt: Equatable, Sendable {
    case project(UUID)
    case tab(UUID)
    case pane(UUID)
    case command(paneID: UUID)
}

public struct BessieProjectMaterializationProgressFact: Equatable, Sendable {
    public let stage: BessieProjectMaterializationStage
    public let attempt: BessieProjectMaterializationAttempt
    public let workspaceID: String?
    public let tabIDsByRecipeID: [UUID: String]
    public let paneIDsByRecipeID: [UUID: String]

    public init(
        stage: BessieProjectMaterializationStage,
        attempt: BessieProjectMaterializationAttempt,
        workspaceID: String?,
        tabIDsByRecipeID: [UUID: String],
        paneIDsByRecipeID: [UUID: String]
    ) {
        self.stage = stage
        self.attempt = attempt
        self.workspaceID = workspaceID
        self.tabIDsByRecipeID = tabIDsByRecipeID
        self.paneIDsByRecipeID = paneIDsByRecipeID
    }
}

public struct BessieProjectCommandMaterialization: Equatable, Sendable {
    public let recipePaneID: UUID
    public let runtimePaneID: String
    public let command: String
    public var attempted: Bool
    public var readinessConfirmed: Bool
    public var textSubmitted: Bool
    public var echoConfirmed: Bool
    public var enterSubmitted: Bool

    public init(recipePaneID: UUID, runtimePaneID: String, command: String) {
        self.recipePaneID = recipePaneID
        self.runtimePaneID = runtimePaneID
        self.command = command
        attempted = true
        readinessConfirmed = false
        textSubmitted = false
        echoConfirmed = false
        enterSubmitted = false
    }
}

public enum BessieProjectVerificationIssue: Error, Equatable, Sendable {
    case missingWorkspace(String)
    case workspaceLabelMismatch(runtimeWorkspaceID: String, expected: String, actual: String?)
    case missingTab(recipeTabID: UUID, runtimeTabID: String)
    case tabWrongWorkspace(recipeTabID: UUID, runtimeTabID: String, expectedWorkspaceID: String, actualWorkspaceID: String?)
    case tabLabelMismatch(recipeTabID: UUID, runtimeTabID: String, expected: String, actual: String?)
    case missingPane(recipePaneID: UUID, runtimePaneID: String)
    case paneWrongWorkspace(recipePaneID: UUID, runtimePaneID: String, expectedWorkspaceID: String, actualWorkspaceID: String?)
    case paneWrongTab(recipePaneID: UUID, runtimePaneID: String, expectedTabID: String, actualTabID: String?)
    case paneMissingFromLayout(recipePaneID: UUID, runtimePaneID: String, runtimeTabID: String)
    case tabLayoutUnavailable(recipeTabID: UUID, runtimeTabID: String)
    case tabTopologyMismatch(recipeTabID: UUID, runtimeTabID: String)
    case paneCWDUnavailable(recipePaneID: UUID, runtimePaneID: String)
    case paneCWDMismatch(recipePaneID: UUID, runtimePaneID: String, expected: String, actual: String)
    case paneLabelMismatch(recipePaneID: UUID, runtimePaneID: String, expected: String?, actual: String?)
}

public enum BessieProjectVerifiedRuntimeFact: Equatable, Sendable {
    case workspace(recipeProjectID: UUID, runtimeWorkspaceID: String)
    case tab(recipeTabID: UUID, runtimeTabID: String, runtimeWorkspaceID: String)
    case pane(recipePaneID: UUID, runtimePaneID: String, runtimeTabID: String, cwd: String)
    case commandEchoConfirmed(recipePaneID: UUID, runtimePaneID: String)
    case commandEnterSubmitted(recipePaneID: UUID, runtimePaneID: String)
}

public struct BessieProjectMaterializationResult: Equatable, Sendable {
    public let plan: BessieProjectMaterializationPlan
    public let workspaceID: String
    public let tabIDsByRecipeID: [UUID: String]
    public let paneIDsByRecipeID: [UUID: String]
    public let commands: [BessieProjectCommandMaterialization]
    public let verificationFacts: [BessieProjectVerifiedRuntimeFact]
    public let finalSnapshot: HerdrSnapshot

    public init(
        plan: BessieProjectMaterializationPlan,
        workspaceID: String,
        tabIDsByRecipeID: [UUID: String],
        paneIDsByRecipeID: [UUID: String],
        commands: [BessieProjectCommandMaterialization],
        verificationFacts: [BessieProjectVerifiedRuntimeFact],
        finalSnapshot: HerdrSnapshot
    ) {
        self.plan = plan
        self.workspaceID = workspaceID
        self.tabIDsByRecipeID = tabIDsByRecipeID
        self.paneIDsByRecipeID = paneIDsByRecipeID
        self.commands = commands
        self.verificationFacts = verificationFacts
        self.finalSnapshot = finalSnapshot
    }
}

public struct BessieProjectMaterializationPartialResult: Equatable, Sendable {
    public let projectID: UUID
    public let connectionID: String
    public let socketPath: String
    public let generation: UUID
    public let workspaceID: String?
    public let tabIDsByRecipeID: [UUID: String]
    public let paneIDsByRecipeID: [UUID: String]
    public let commands: [BessieProjectCommandMaterialization]
    public let mutationOutcome: BessieProjectMutationOutcome
    public let freshSnapshot: HerdrSnapshot?
    public let lastVerifiedSnapshot: HerdrSnapshot?

    public var isPartial: Bool { workspaceID != nil || mutationOutcome == .outcomeUnknown }

    public init(
        projectID: UUID,
        connectionID: String,
        socketPath: String,
        generation: UUID,
        workspaceID: String?,
        tabIDsByRecipeID: [UUID: String],
        paneIDsByRecipeID: [UUID: String],
        commands: [BessieProjectCommandMaterialization],
        mutationOutcome: BessieProjectMutationOutcome,
        freshSnapshot: HerdrSnapshot?,
        lastVerifiedSnapshot: HerdrSnapshot?
    ) {
        self.projectID = projectID
        self.connectionID = connectionID
        self.socketPath = socketPath
        self.generation = generation
        self.workspaceID = workspaceID
        self.tabIDsByRecipeID = tabIDsByRecipeID
        self.paneIDsByRecipeID = paneIDsByRecipeID
        self.commands = commands
        self.mutationOutcome = mutationOutcome
        self.freshSnapshot = freshSnapshot
        self.lastVerifiedSnapshot = lastVerifiedSnapshot
    }
}

public enum BessieProjectMutationOutcome: Equatable, Sendable {
    case notAttempted
    case acknowledged
    case outcomeUnknown
}

public enum BessieProjectMaterializationOwnerError: Error, Equatable, Sendable {
    case validation([BessieProjectValidationIssue])
    case remoteConnection
    case incompatibleConnection(String)
    case invalidEndpoint
    case cancelled
    case connectionLost
    case connectionChanged
    case invalidCommand(recipePaneID: UUID)
    case duplicateRuntimeTabID(String)
    case duplicateRuntimePaneID(String)
    case herdr(HerdrClientError)
    case startup(HerdrStartupCommandFailure)
    case verification([BessieProjectVerificationIssue])
    case unexpected(String)
}

public struct BessieProjectMaterializationFailure: Error, Equatable, Sendable {
    public let stage: BessieProjectMaterializationStage
    public let attempt: BessieProjectMaterializationAttempt
    public let ownerError: BessieProjectMaterializationOwnerError
    public let partialResult: BessieProjectMaterializationPartialResult

    public init(
        stage: BessieProjectMaterializationStage,
        attempt: BessieProjectMaterializationAttempt,
        ownerError: BessieProjectMaterializationOwnerError,
        partialResult: BessieProjectMaterializationPartialResult
    ) {
        self.stage = stage
        self.attempt = attempt
        self.ownerError = ownerError
        self.partialResult = partialResult
    }
}

public struct BessieProjectMaterializer: Sendable {
    private let api: any BessieProjectMaterializationAPI
    private let commandPolicy: HerdrStartupCommandPolicy
    private let now: @Sendable () -> Date
    private let wait: @Sendable (TimeInterval) -> Void
    private let isCancelled: @Sendable () -> Bool
    private let connectionStatus: @Sendable (BessieProjectMaterializationConnection) -> BessieProjectMaterializationConnectionStatus

    public init(
        api: any BessieProjectMaterializationAPI,
        connectionStatus: @escaping @Sendable (BessieProjectMaterializationConnection) -> BessieProjectMaterializationConnectionStatus,
        commandPolicy: HerdrStartupCommandPolicy = .init(),
        now: @escaping @Sendable () -> Date = Date.init,
        wait: @escaping @Sendable (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) {
        self.api = api
        self.commandPolicy = commandPolicy
        self.now = now
        self.wait = wait
        self.isCancelled = isCancelled
        self.connectionStatus = connectionStatus
    }

    public func materialize(
        _ project: BessieProject,
        on connection: BessieProjectMaterializationConnection,
        onProgress: (BessieProjectMaterializationProgressFact) -> Void = { _ in }
    ) throws -> BessieProjectMaterializationResult {
        var stage = BessieProjectMaterializationStage.validatingProject
        var attempt = BessieProjectMaterializationAttempt.project(project.id)
        var workspaceID: String?
        var tabIDs: [UUID: String] = [:]
        var paneIDs: [UUID: String] = [:]
        var commands: [BessieProjectCommandMaterialization] = []
        var lastVerifiedSnapshot: HerdrSnapshot?
        var mutationOutcome = BessieProjectMutationOutcome.notAttempted
        var normalizedProject = project

        func progress() {
            onProgress(.init(
                stage: stage,
                attempt: attempt,
                workspaceID: workspaceID,
                tabIDsByRecipeID: tabIDs,
                paneIDsByRecipeID: paneIDs
            ))
        }

        func checkBoundary() throws {
            if isCancelled() { throw BessieProjectMaterializationOwnerError.cancelled }
            try checkConnection()
        }

        func checkConnection() throws {
            switch connectionStatus(connection) {
            case .current: return
            case .disconnected:
                throw BessieProjectMaterializationOwnerError.connectionLost
            case .changed:
                throw BessieProjectMaterializationOwnerError.connectionChanged
            }
        }

        func authoritativeSnapshot() throws -> HerdrSnapshot {
            try checkConnection()
            let snapshot = try api.snapshot()
            try checkConnection()
            return snapshot
        }

        func mutationRequest(_ method: String, _ params: [String: JSONValue]) throws -> JSONValue {
            try checkBoundary()
            mutationOutcome = .outcomeUnknown
            return try api.request(method: method, params: params)
        }

        func verifyCreation() throws {
            stage = .verifyingCreation
            progress()
            let snapshot = try authoritativeSnapshot()
            let issues = Self.verificationIssues(
                project: normalizedProject,
                workspaceID: workspaceID,
                tabIDs: tabIDs,
                paneIDs: paneIDs,
                snapshot: snapshot,
                verifyMetadata: false
            )
            guard issues.isEmpty else { throw BessieProjectMaterializationOwnerError.verification(issues) }
            lastVerifiedSnapshot = snapshot
        }

        func applyLabel(_ pane: BessieProjectPane, runtimePaneID: String) throws {
            stage = .labelingPane
            attempt = .pane(pane.id)
            mutationOutcome = .notAttempted
            progress()
            let renamedPane = try HerdrPaneCreationResult(result: mutationRequest("pane.rename", [
                "pane_id": .string(runtimePaneID),
                "label": pane.label.map(JSONValue.string) ?? .null,
            ]))
            guard renamedPane.paneID == runtimePaneID else {
                throw BessieProjectMaterializationOwnerError.unexpected("pane.rename returned a different pane ID.")
            }
            mutationOutcome = .acknowledged
        }

        do {
            do {
                normalizedProject = try project.normalized()
            } catch let error as BessieProjectValidationError {
                throw BessieProjectMaterializationOwnerError.validation(error.issues)
            }
            if let invalidPane = normalizedProject.tabs.lazy.flatMap(\.panes).first(where: {
                guard let command = $0.command else { return false }
                return command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                attempt = .command(paneID: invalidPane.id)
                throw BessieProjectMaterializationOwnerError.invalidCommand(recipePaneID: invalidPane.id)
            }

            stage = .validatingConnection
            progress()
            guard connection.definition.kind == .local else {
                throw BessieProjectMaterializationOwnerError.remoteConnection
            }
            guard !connection.socketPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BessieProjectMaterializationOwnerError.invalidEndpoint
            }
            if let reason = HerdrCompatibility.incompatibility(for: connection.identity) {
                throw BessieProjectMaterializationOwnerError.incompatibleConnection(reason)
            }
            guard api.socketPath == connection.socketPath else {
                throw BessieProjectMaterializationOwnerError.invalidEndpoint
            }
            let endpointIdentity: HerdrServerIdentity
            do {
                endpointIdentity = try api.ping()
            } catch let error as HerdrClientError {
                throw BessieProjectMaterializationOwnerError.herdr(error)
            }
            guard endpointIdentity == connection.identity else {
                throw BessieProjectMaterializationOwnerError.connectionChanged
            }
            try checkBoundary()
            let plan = BessieProjectMaterializationPlan(project: normalizedProject, connection: connection)
            let firstTab = normalizedProject.tabs[0]
            let firstRoot = firstTab.panes.first { if case .root = $0.placement { return true }; return false }!

            stage = .creatingWorkspace
            attempt = .project(normalizedProject.id)
            progress()
            let createdWorkspace = try HerdrWorkspaceCreationResult(result: mutationRequest("workspace.create", [
                "cwd": .string(normalizedProject.workingDirectory),
                "label": .string(normalizedProject.name),
                "focus": .bool(true),
            ]))
            mutationOutcome = .acknowledged
            workspaceID = createdWorkspace.workspaceID
            tabIDs[firstTab.id] = createdWorkspace.tabID
            paneIDs[firstRoot.id] = createdWorkspace.rootPaneID
            try verifyCreation()

            stage = .renamingInitialTab
            attempt = .tab(firstTab.id)
            mutationOutcome = .notAttempted
            progress()
            let renamedInitialTab = try HerdrTabInfoResult(result: mutationRequest("tab.rename", [
                "tab_id": .string(createdWorkspace.tabID),
                "label": .string(firstTab.name),
            ]))
            guard renamedInitialTab.tabID == createdWorkspace.tabID else {
                throw BessieProjectMaterializationOwnerError.unexpected("tab.rename returned a different tab ID.")
            }
            mutationOutcome = .acknowledged
            if firstRoot.label != nil {
                try applyLabel(firstRoot, runtimePaneID: createdWorkspace.rootPaneID)
            }

            for tab in normalizedProject.tabs.dropFirst() {
                let root = tab.panes.first { if case .root = $0.placement { return true }; return false }!
                stage = .creatingTab
                attempt = .tab(tab.id)
                mutationOutcome = .notAttempted
                progress()
                let createdTab = try HerdrTabCreationResult(result: mutationRequest("tab.create", [
                    "workspace_id": .string(createdWorkspace.workspaceID),
                    "cwd": .string(normalizedProject.workingDirectory),
                    "label": .string(tab.name),
                    "focus": .bool(false),
                ]))
                guard !tabIDs.values.contains(createdTab.tabID) else {
                    throw BessieProjectMaterializationOwnerError.duplicateRuntimeTabID(createdTab.tabID)
                }
                guard !paneIDs.values.contains(createdTab.rootPaneID) else {
                    throw BessieProjectMaterializationOwnerError.duplicateRuntimePaneID(createdTab.rootPaneID)
                }
                mutationOutcome = .acknowledged
                tabIDs[tab.id] = createdTab.tabID
                paneIDs[root.id] = createdTab.rootPaneID
                try verifyCreation()
                if root.label != nil {
                    try applyLabel(root, runtimePaneID: createdTab.rootPaneID)
                }
            }

            for tab in normalizedProject.tabs {
                for pane in tab.panes {
                    guard case .split(let parentRecipeID, let direction, let ratio) = pane.placement else { continue }
                    stage = .splittingPane
                    attempt = .pane(pane.id)
                    mutationOutcome = .notAttempted
                    progress()
                    guard let parentRuntimeID = paneIDs[parentRecipeID] else {
                        throw BessieProjectMaterializationOwnerError.unexpected("Validated split parent was not materialized.")
                    }
                    let createdPane = try HerdrPaneCreationResult(result: mutationRequest("pane.split", [
                        "target_pane_id": .string(parentRuntimeID),
                        "direction": .string(direction.rawValue),
                        "ratio": .number(ratio),
                        "cwd": .string(normalizedProject.workingDirectory),
                        "focus": .bool(false),
                    ]))
                    guard !paneIDs.values.contains(createdPane.paneID) else {
                        throw BessieProjectMaterializationOwnerError.duplicateRuntimePaneID(createdPane.paneID)
                    }
                    mutationOutcome = .acknowledged
                    paneIDs[pane.id] = createdPane.paneID
                    try verifyCreation()
                    if pane.label != nil {
                        try applyLabel(pane, runtimePaneID: createdPane.paneID)
                    }
                }
            }

            stage = .verifyingTopology
            attempt = .project(normalizedProject.id)
            progress()
            try checkBoundary()
            var topologySnapshot = try authoritativeSnapshot()
            var issues = Self.verificationIssues(
                project: normalizedProject,
                workspaceID: workspaceID,
                tabIDs: tabIDs,
                paneIDs: paneIDs,
                snapshot: topologySnapshot,
                verifyMetadata: true
            )
            guard issues.isEmpty else { throw BessieProjectMaterializationOwnerError.verification(issues) }
            lastVerifiedSnapshot = topologySnapshot

            for tab in normalizedProject.tabs {
                for pane in tab.panes {
                    guard let command = pane.command, !command.isEmpty,
                          let runtimePaneID = paneIDs[pane.id] else { continue }
                    attempt = .command(paneID: pane.id)
                    stage = .waitingForCommandReadiness
                    commands.append(.init(recipePaneID: pane.id, runtimePaneID: runtimePaneID, command: command))
                    mutationOutcome = .notAttempted
                    progress()
                    let commandIndex = commands.index(before: commands.endIndex)
                    let submitter = HerdrStartupCommandSubmitter(
                        api: api,
                        policy: commandPolicy,
                        now: now,
                        wait: wait,
                        isCancelled: {
                            if isCancelled() { return true }
                            return connectionStatus(connection) != .current
                        }
                    )
                    do {
                        try submitter.submit(command: command, toPaneID: runtimePaneID) { event in
                            switch event {
                            case .readinessConfirmed:
                                commands[commandIndex].readinessConfirmed = true
                                stage = .submittingCommandText
                            case .submittingText:
                                mutationOutcome = .outcomeUnknown
                            case .textSubmitted:
                                commands[commandIndex].textSubmitted = true
                                mutationOutcome = .acknowledged
                                stage = .waitingForCommandEcho
                            case .echoConfirmed:
                                commands[commandIndex].echoConfirmed = true
                                stage = .submittingCommandEnter
                            case .submittingEnter:
                                mutationOutcome = .outcomeUnknown
                            case .enterSubmitted:
                                commands[commandIndex].enterSubmitted = true
                                mutationOutcome = .acknowledged
                            }
                            progress()
                        }
                    } catch let error as HerdrStartupCommandFailure {
                        if case .cancelled = error {
                            try checkBoundary()
                        }
                        throw BessieProjectMaterializationOwnerError.startup(error)
                    }
                }
            }

            stage = .verifyingComplete
            attempt = .project(normalizedProject.id)
            progress()
            try checkBoundary()
            topologySnapshot = try authoritativeSnapshot()
            issues = Self.verificationIssues(
                project: normalizedProject,
                workspaceID: workspaceID,
                tabIDs: tabIDs,
                paneIDs: paneIDs,
                snapshot: topologySnapshot,
                verifyMetadata: true
            )
            guard issues.isEmpty else { throw BessieProjectMaterializationOwnerError.verification(issues) }
            lastVerifiedSnapshot = topologySnapshot

            var facts = Self.verificationFacts(
                project: normalizedProject,
                workspaceID: createdWorkspace.workspaceID,
                tabIDs: tabIDs,
                paneIDs: paneIDs,
                snapshot: topologySnapshot
            )
            for command in commands where command.echoConfirmed {
                facts.append(.commandEchoConfirmed(recipePaneID: command.recipePaneID, runtimePaneID: command.runtimePaneID))
            }
            for command in commands where command.enterSubmitted {
                facts.append(.commandEnterSubmitted(recipePaneID: command.recipePaneID, runtimePaneID: command.runtimePaneID))
            }
            return .init(
                plan: plan,
                workspaceID: createdWorkspace.workspaceID,
                tabIDsByRecipeID: tabIDs,
                paneIDsByRecipeID: paneIDs,
                commands: commands,
                verificationFacts: facts,
                finalSnapshot: topologySnapshot
            )
        } catch {
            let ownerError = Self.ownerError(error)
            var freshSnapshot: HerdrSnapshot?
            if (workspaceID != nil || mutationOutcome == .outcomeUnknown), connectionStatus(connection) == .current {
                freshSnapshot = try? authoritativeSnapshot()
            }
            throw BessieProjectMaterializationFailure(
                stage: stage,
                attempt: attempt,
                ownerError: ownerError,
                partialResult: .init(
                    projectID: project.id,
                    connectionID: connection.definition.id,
                    socketPath: connection.socketPath,
                    generation: connection.generation,
                    workspaceID: workspaceID,
                    tabIDsByRecipeID: tabIDs,
                    paneIDsByRecipeID: paneIDs,
                    commands: commands,
                    mutationOutcome: mutationOutcome,
                    freshSnapshot: freshSnapshot,
                    lastVerifiedSnapshot: lastVerifiedSnapshot
                )
            )
        }
    }

    private static func ownerError(_ error: Error) -> BessieProjectMaterializationOwnerError {
        if let error = error as? BessieProjectMaterializationOwnerError { return error }
        if let error = error as? HerdrClientError { return .herdr(error) }
        if let error = error as? HerdrStartupCommandFailure { return .startup(error) }
        return .unexpected(error.localizedDescription)
    }

    private static func verificationIssues(
        project: BessieProject,
        workspaceID: String?,
        tabIDs: [UUID: String],
        paneIDs: [UUID: String],
        snapshot: HerdrSnapshot,
        verifyMetadata: Bool
    ) -> [BessieProjectVerificationIssue] {
        guard let workspaceID else { return [] }
        var issues: [BessieProjectVerificationIssue] = []
        let workspace = snapshot.workspaces.first { $0.string("workspace_id") == workspaceID }
        if workspace == nil {
            issues.append(.missingWorkspace(workspaceID))
        } else if verifyMetadata, workspace?.string("label") != project.name {
            issues.append(.workspaceLabelMismatch(
                runtimeWorkspaceID: workspaceID, expected: project.name, actual: workspace?.string("label")
            ))
        }

        for tab in project.tabs {
            guard let runtimeTabID = tabIDs[tab.id] else { continue }
            guard let runtimeTab = snapshot.tabs.first(where: { $0.string("tab_id") == runtimeTabID }) else {
                issues.append(.missingTab(recipeTabID: tab.id, runtimeTabID: runtimeTabID))
                continue
            }
            let actualWorkspaceID = runtimeTab.string("workspace_id")
            if actualWorkspaceID != workspaceID {
                issues.append(.tabWrongWorkspace(
                    recipeTabID: tab.id, runtimeTabID: runtimeTabID,
                    expectedWorkspaceID: workspaceID, actualWorkspaceID: actualWorkspaceID
                ))
            }
            if verifyMetadata, runtimeTab.string("label") != tab.name {
                issues.append(.tabLabelMismatch(
                    recipeTabID: tab.id, runtimeTabID: runtimeTabID,
                    expected: tab.name, actual: runtimeTab.string("label")
                ))
            }
            for pane in tab.panes {
                guard let runtimePaneID = paneIDs[pane.id] else { continue }
                guard let runtimePane = snapshot.panes.first(where: { $0.string("pane_id") == runtimePaneID }) else {
                    issues.append(.missingPane(recipePaneID: pane.id, runtimePaneID: runtimePaneID))
                    continue
                }
                let paneWorkspaceID = runtimePane.string("workspace_id")
                if paneWorkspaceID != workspaceID {
                    issues.append(.paneWrongWorkspace(
                        recipePaneID: pane.id, runtimePaneID: runtimePaneID,
                        expectedWorkspaceID: workspaceID, actualWorkspaceID: paneWorkspaceID
                    ))
                }
                let paneTabID = runtimePane.string("tab_id")
                if paneTabID != runtimeTabID {
                    issues.append(.paneWrongTab(
                        recipePaneID: pane.id, runtimePaneID: runtimePaneID,
                        expectedTabID: runtimeTabID, actualTabID: paneTabID
                    ))
                }
                let tabLayout = snapshot.layouts.first { $0.string("tab_id") == runtimeTabID }
                if tabLayout?.containsString(runtimePaneID, forKey: "pane_id") != true {
                    issues.append(.paneMissingFromLayout(
                        recipePaneID: pane.id,
                        runtimePaneID: runtimePaneID,
                        runtimeTabID: runtimeTabID
                    ))
                }
                guard let cwd = runtimePane.string("cwd") else {
                    issues.append(.paneCWDUnavailable(recipePaneID: pane.id, runtimePaneID: runtimePaneID))
                    continue
                }
                let canonicalCWD = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
                if canonicalCWD != project.workingDirectory {
                    issues.append(.paneCWDMismatch(
                        recipePaneID: pane.id, runtimePaneID: runtimePaneID,
                        expected: project.workingDirectory, actual: canonicalCWD
                    ))
                }
                if verifyMetadata, runtimePane.optionalString("label") != pane.label {
                    issues.append(.paneLabelMismatch(
                        recipePaneID: pane.id, runtimePaneID: runtimePaneID,
                        expected: pane.label, actual: runtimePane.optionalString("label")
                    ))
                }
            }
            if verifyMetadata {
                guard let layoutValue = snapshot.layouts.first(where: { $0.string("tab_id") == runtimeTabID }),
                      let actualLayout = try? MaterializedLayout(value: layoutValue) else {
                    issues.append(.tabLayoutUnavailable(recipeTabID: tab.id, runtimeTabID: runtimeTabID))
                    continue
                }
                if actualLayout.workspaceID != workspaceID ||
                    actualLayout.tabID != runtimeTabID ||
                    !actualLayout.matches(tab: tab, paneIDs: paneIDs) {
                    issues.append(.tabTopologyMismatch(recipeTabID: tab.id, runtimeTabID: runtimeTabID))
                }
            }
        }
        return issues
    }

    private static func verificationFacts(
        project: BessieProject,
        workspaceID: String,
        tabIDs: [UUID: String],
        paneIDs: [UUID: String],
        snapshot: HerdrSnapshot
    ) -> [BessieProjectVerifiedRuntimeFact] {
        var facts: [BessieProjectVerifiedRuntimeFact] = [
            .workspace(recipeProjectID: project.id, runtimeWorkspaceID: workspaceID),
        ]
        for tab in project.tabs {
            guard let runtimeTabID = tabIDs[tab.id] else { continue }
            facts.append(.tab(recipeTabID: tab.id, runtimeTabID: runtimeTabID, runtimeWorkspaceID: workspaceID))
            for pane in tab.panes {
                guard let runtimePaneID = paneIDs[pane.id],
                      let cwd = snapshot.panes.first(where: { $0.string("pane_id") == runtimePaneID })?.string("cwd") else { continue }
                facts.append(.pane(
                    recipePaneID: pane.id,
                    runtimePaneID: runtimePaneID,
                    runtimeTabID: runtimeTabID,
                    cwd: cwd
                ))
            }
        }
        return facts
    }
}

private struct MaterializedLayout {
    let workspaceID: String
    let tabID: String
    let root: MaterializedLayoutNode

    init(value: JSONValue) throws {
        let wire: MaterializedLayoutWire = try value.decode()
        workspaceID = wire.workspaceID
        tabID = wire.tabID
        let splits = Dictionary(uniqueKeysWithValues: wire.splits.map { (Self.path(for: $0.id), $0) })
        root = try Self.build(path: [], panes: wire.panes, splits: splits)
    }

    func matches(tab: BessieProjectTab, paneIDs: [UUID: String]) -> Bool {
        guard let rootPane = tab.panes.first(where: { if case .root = $0.placement { true } else { false } }),
              let rootRuntimeID = paneIDs[rootPane.id] else { return false }
        var expected = MaterializedLayoutNode.pane(rootRuntimeID)
        for pane in tab.panes {
            guard case .split(let parentRecipeID, let direction, let ratio) = pane.placement,
                  let parentRuntimeID = paneIDs[parentRecipeID],
                  let runtimeID = paneIDs[pane.id],
                  expected.replacing(
                    paneID: parentRuntimeID,
                    with: .split(direction: direction, ratio: ratio, first: .pane(parentRuntimeID), second: .pane(runtimeID))
                  ) else { continue }
        }
        return root.matches(expected)
    }

    private static func build(
        path: [Bool],
        panes: [MaterializedLayoutPaneWire],
        splits: [[Bool]: MaterializedLayoutSplitWire]
    ) throws -> MaterializedLayoutNode {
        guard let split = splits[path] else {
            guard panes.count == 1, let pane = panes.first else {
                throw HerdrClientError.unexpectedResponse("materialized layout path does not resolve to one pane")
            }
            return .pane(pane.paneID)
        }
        let splitCells = split.direction == .right
            ? (Float(split.rect.width) * Float(split.ratio)).rounded()
            : (Float(split.rect.height) * Float(split.ratio)).rounded()
        let boundary = split.direction == .right
            ? Double(split.rect.x) + Double(splitCells)
            : Double(split.rect.y) + Double(splitCells)
        let first = panes.filter {
            split.direction == .right
                ? Double($0.rect.x) + Double($0.rect.width) / 2 < boundary
                : Double($0.rect.y) + Double($0.rect.height) / 2 < boundary
        }
        let firstIDs = Set(first.map(\.paneID))
        let second = panes.filter { !firstIDs.contains($0.paneID) }
        return .split(
            direction: split.direction,
            ratio: split.ratio,
            first: try build(path: path + [false], panes: first, splits: splits),
            second: try build(path: path + [true], panes: second, splits: splits)
        )
    }

    private static func path(for splitID: String) -> [Bool] {
        guard let suffix = splitID.split(separator: "_").last, suffix != "root" else { return [] }
        return suffix.map { $0 == "1" }
    }
}

private indirect enum MaterializedLayoutNode {
    case pane(String)
    case split(direction: SplitDirection, ratio: Double, first: Self, second: Self)

    mutating func replacing(paneID: String, with replacement: Self) -> Bool {
        switch self {
        case .pane(let current) where current == paneID:
            self = replacement
            return true
        case .pane:
            return false
        case .split(let direction, let ratio, var first, var second):
            if first.replacing(paneID: paneID, with: replacement) {
                self = .split(direction: direction, ratio: ratio, first: first, second: second)
                return true
            }
            if second.replacing(paneID: paneID, with: replacement) {
                self = .split(direction: direction, ratio: ratio, first: first, second: second)
                return true
            }
            return false
        }
    }

    func matches(_ expected: Self) -> Bool {
        switch (self, expected) {
        case (.pane(let actual), .pane(let expected)):
            return actual == expected
        case let (.split(actualDirection, actualRatio, actualFirst, actualSecond),
                  .split(expectedDirection, expectedRatio, expectedFirst, expectedSecond)):
            return actualDirection == expectedDirection &&
                Float(actualRatio) == Float(expectedRatio) &&
                actualFirst.matches(expectedFirst) && actualSecond.matches(expectedSecond)
        default:
            return false
        }
    }
}

private struct MaterializedLayoutWire: Decodable {
    let workspaceID: String
    let tabID: String
    let panes: [MaterializedLayoutPaneWire]
    let splits: [MaterializedLayoutSplitWire]

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case tabID = "tab_id"
        case panes, splits
    }
}

private struct MaterializedLayoutPaneWire: Decodable {
    let paneID: String
    let rect: LayoutRect
    enum CodingKeys: String, CodingKey { case paneID = "pane_id", rect }
}

private struct MaterializedLayoutSplitWire: Decodable {
    let id: String
    let direction: SplitDirection
    let ratio: Double
    let rect: LayoutRect
}

private extension JSONValue {
    func string(_ key: String) -> String? {
        guard case .object(let object) = self,
              case .string(let value)? = object[key] else { return nil }
        return value
    }

    func optionalString(_ key: String) -> String? {
        guard case .object(let object) = self else { return nil }
        switch object[key] {
        case .string(let value): return value
        case .null, nil: return nil
        default: return nil
        }
    }

    func containsString(_ expected: String, forKey key: String) -> Bool {
        switch self {
        case .object(let object):
            if object[key] == .string(expected) { return true }
            return object.values.contains { $0.containsString(expected, forKey: key) }
        case .array(let values):
            return values.contains { $0.containsString(expected, forKey: key) }
        case .string, .number, .bool, .null:
            return false
        }
    }
}
