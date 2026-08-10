import Foundation

public struct CommandPalettePaneInput: Equatable, Sendable {
    public let id: String
    public let workspaceID: String
    public let workspaceTitle: String
    public let tabID: String
    public let tabTitle: String
    public let title: String
    public let detail: String
    public let semanticState: AgentSemanticState
    public let provider: String?
    public let location: String?
    public let keywords: [String]

    public init(
        id: String,
        workspaceID: String,
        workspaceTitle: String,
        tabID: String,
        tabTitle: String,
        title: String,
        detail: String,
        semanticState: AgentSemanticState,
        provider: String? = nil,
        location: String? = nil,
        keywords: [String] = []
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.workspaceTitle = workspaceTitle
        self.tabID = tabID
        self.tabTitle = tabTitle
        self.title = title
        self.detail = detail
        self.semanticState = semanticState
        self.provider = provider
        self.location = location
        self.keywords = keywords
    }
}

public struct CommandPaletteWorkspaceInput: Equatable, Sendable {
    public let id: String
    public let number: Int
    public let title: String
    public let tabCount: Int
    public let paneCount: Int
    public let semanticState: AgentSemanticState

    public init(
        id: String,
        number: Int,
        title: String,
        tabCount: Int,
        paneCount: Int,
        semanticState: AgentSemanticState
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.tabCount = tabCount
        self.paneCount = paneCount
        self.semanticState = semanticState
    }
}

public struct CommandPaletteConnectionInput: Equatable, Sendable {
    public let connection: BessieConnectionDefinition
    public let freshness: CommandPaletteFreshness
    public let healthDetail: String
    public let panes: [CommandPalettePaneInput]
    public let workspaces: [CommandPaletteWorkspaceInput]

    public init(
        connection: BessieConnectionDefinition,
        freshness: CommandPaletteFreshness,
        healthDetail: String,
        panes: [CommandPalettePaneInput],
        workspaces: [CommandPaletteWorkspaceInput]
    ) {
        self.connection = connection
        self.freshness = freshness
        self.healthDetail = healthDetail
        self.panes = panes
        self.workspaces = workspaces
    }
}

public struct CommandPaletteProjectInput: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let location: String?
    public let keywords: [String]
    public let isRunning: Bool

    public init(
        id: UUID,
        title: String,
        detail: String,
        location: String? = nil,
        keywords: [String] = [],
        isRunning: Bool
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.location = location
        self.keywords = keywords
        self.isRunning = isRunning
    }
}

public struct CommandPaletteMRU: Equatable, Sendable {
    public static let capacity = 6
    public private(set) var ids: [CommandPaletteEntityID]

    public init(ids: [CommandPaletteEntityID] = []) {
        var seen: Set<CommandPaletteEntityID> = []
        self.ids = ids.filter { seen.insert($0).inserted }.prefix(Self.capacity).map { $0 }
    }

    public mutating func record(_ id: CommandPaletteEntityID) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > Self.capacity { ids.removeLast(ids.count - Self.capacity) }
    }
}

public struct CommandPaletteIndexContext: Equatable, Sendable {
    public let activeConnectionID: String?
    public let scope: ConnectionScope
    public let focusedWorkspaceID: String?
    public let focusedPaneID: String?
    public let mru: CommandPaletteMRU

    public init(
        activeConnectionID: String?,
        scope: ConnectionScope,
        focusedWorkspaceID: String?,
        focusedPaneID: String?,
        mru: CommandPaletteMRU
    ) {
        self.activeConnectionID = activeConnectionID
        self.scope = scope
        self.focusedWorkspaceID = focusedWorkspaceID
        self.focusedPaneID = focusedPaneID
        self.mru = mru
    }
}

public struct CommandPaletteIndexInput: Equatable, Sendable {
    public let connections: [CommandPaletteConnectionInput]
    public let projects: [CommandPaletteProjectInput]
    public let commands: [BessieCommandDefinition]
    public let context: CommandPaletteIndexContext

    public init(
        connections: [CommandPaletteConnectionInput],
        projects: [CommandPaletteProjectInput],
        commands: [BessieCommandDefinition],
        context: CommandPaletteIndexContext
    ) {
        self.connections = connections
        self.projects = projects
        self.commands = commands
        self.context = context
    }
}

public struct CommandPaletteSection: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case needsYou
        case recent
        case workspaces
        case projects
        case herds
        case commands
    }

    public let kind: Kind
    public let entities: [CommandPaletteEntity]

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .needsYou: "Needs you"
        case .recent: "Recent"
        case .workspaces: "Workspaces"
        case .projects: "Projects"
        case .herds: "Herds"
        case .commands: "Commands"
        }
    }

    public init(kind: Kind, entities: [CommandPaletteEntity]) {
        self.kind = kind
        self.entities = entities
    }
}

public struct CommandPaletteIndex: Equatable, Sendable {
    public let allEntities: [CommandPaletteEntity]
    public let sections: [CommandPaletteSection]
    public let activeConnectionID: String?

    public init(
        allEntities: [CommandPaletteEntity],
        sections: [CommandPaletteSection],
        activeConnectionID: String?
    ) {
        self.allEntities = allEntities
        self.sections = sections
        self.activeConnectionID = activeConnectionID
    }

    public func results(query: String) -> [CommandPaletteEntity] {
        CommandPaletteSearch().resultsFromDeduplicated(
            query: query,
            entities: allEntities,
            activeConnectionID: activeConnectionID
        )
    }

    public func entity(id: CommandPaletteEntityID) -> CommandPaletteEntity? {
        allEntities.first { $0.id == id }
    }
}

public struct CommandPaletteIndexBuilder: Sendable {
    public init() {}

    public func build(_ input: CommandPaletteIndexInput) -> CommandPaletteIndex {
        let rankingConnectionID: String?
        switch input.context.scope {
        case .all:
            rankingConnectionID = input.context.activeConnectionID
        case .connection(let id):
            rankingConnectionID = id
        }
        let search = CommandPaletteSearch()
        var paneEntities: [CommandPaletteEntity] = []
        var workspaceEntities: [CommandPaletteEntity] = []
        var connectionEntities: [CommandPaletteEntity] = []

        for item in input.connections {
            let connectionID = item.connection.id
            connectionEntities.append(CommandPaletteEntity(
                id: .init(kind: .connection, components: [connectionID]),
                kind: .connection,
                title: item.connection.name,
                detail: item.healthDetail,
                freshness: item.freshness,
                location: item.connection.detail,
                keywords: [item.connection.kind.rawValue, item.connection.sshHost ?? "", item.connection.session ?? ""],
                route: .connection(connectionID)
            ))
            guard item.freshness == .fresh else { continue }

            paneEntities += item.panes.map { pane in
                CommandPaletteEntity(
                    id: .init(kind: .pane, components: [connectionID, pane.id]),
                    kind: .pane,
                    title: pane.title,
                    detail: pane.detail,
                    semanticState: pane.semanticState,
                    freshness: .fresh,
                    provider: pane.provider,
                    location: pane.location ?? "\(item.connection.name) / \(pane.workspaceTitle) / \(pane.tabTitle)",
                    keywords: pane.keywords,
                    route: .pane(
                        connectionID: connectionID,
                        workspaceID: pane.workspaceID,
                        tabID: pane.tabID,
                        paneID: pane.id
                    )
                )
            }
            workspaceEntities += item.workspaces.map { workspace in
                CommandPaletteEntity(
                    id: .init(kind: .workspace, components: [connectionID, workspace.id]),
                    kind: .workspace,
                    title: workspace.title,
                    detail: "\(workspace.tabCount) tabs · \(workspace.paneCount) panes",
                    semanticState: workspace.semanticState,
                    freshness: .fresh,
                    location: item.connection.name,
                    keywords: [String(workspace.number)],
                    route: .workspace(connectionID: connectionID, workspaceID: workspace.id)
                )
            }
        }

        let projectEntities = input.projects.map { project in
            let detail = project.isRunning
                ? (project.detail.isEmpty ? "Running" : "\(project.detail) · Running")
                : project.detail
            return CommandPaletteEntity(
                id: .init(kind: .project, components: [project.id.uuidString]),
                kind: .project,
                title: project.title,
                detail: detail,
                freshness: .fresh,
                location: project.location,
                keywords: project.keywords + (project.isRunning ? ["running"] : []),
                route: .project(project.id)
            )
        }
        let commandEntities = input.commands.compactMap { definition -> CommandPaletteEntity? in
            guard definition.command != .showCommandPalette else { return nil }
            return CommandPaletteEntity(
                id: .init(kind: .command, components: [String(describing: definition.command)]),
                kind: .command,
                title: definition.title,
                detail: definition.detail,
                freshness: .fresh,
                shortcut: definition.shortcut,
                keywords: [definition.keywords],
                route: .command(definition.command),
                alternateRoute: definition.alternateCommand.map(CommandPaletteRouteIntent.command)
            )
        }

        paneEntities = search.deduplicated(paneEntities)
        workspaceEntities = search.deduplicated(workspaceEntities)
        connectionEntities = orderedDeduplicated(connectionEntities, search: search)
        let projects = orderedDeduplicated(projectEntities, search: search)
        let commands = orderedDeduplicated(commandEntities, search: search)
        let allEntities = search.deduplicated(
            paneEntities + workspaceEntities + projects + connectionEntities + commands
        )
        let byID = Dictionary(allEntities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let needsYou = paneEntities.filter(\.requiresUserAction).sorted { lhs, rhs in
            agentListPrecedes(
                lhs: (lhs.semanticState ?? .unknown, lhs.connectionID ?? "", lhs.location ?? "", lhs.title, lhs.id.description),
                rhs: (rhs.semanticState ?? .unknown, rhs.connectionID ?? "", rhs.location ?? "", rhs.title, rhs.id.description)
            )
        }
        let needsYouIDs = Set(needsYou.map(\.id))
        let recent = input.context.mru.ids
            .prefix(CommandPaletteMRU.capacity)
            .compactMap { byID[$0] }
            .filter { !needsYouIDs.contains($0.id) }
        let orderedWorkspaces = orderWorkspaces(workspaceEntities, input: input)

        let candidates: [CommandPaletteSection] = [
            .init(kind: .needsYou, entities: needsYou),
            .init(kind: .recent, entities: recent),
            .init(kind: .workspaces, entities: orderedWorkspaces),
            .init(kind: .projects, entities: projects),
            .init(kind: .herds, entities: connectionEntities),
            .init(kind: .commands, entities: commands),
        ]
        return CommandPaletteIndex(
            allEntities: allEntities,
            sections: candidates.filter { !$0.entities.isEmpty },
            activeConnectionID: rankingConnectionID
        )
    }

    private func orderedDeduplicated(
        _ entities: [CommandPaletteEntity],
        search: CommandPaletteSearch
    ) -> [CommandPaletteEntity] {
        let resolved = Dictionary(
            search.deduplicated(entities).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen: Set<CommandPaletteEntityID> = []
        return entities.compactMap { entity in
            guard seen.insert(entity.id).inserted else { return nil }
            return resolved[entity.id]
        }
    }

    private func orderWorkspaces(
        _ entities: [CommandPaletteEntity],
        input: CommandPaletteIndexInput
    ) -> [CommandPaletteEntity] {
        var result: [CommandPaletteEntity] = []
        var seen: Set<CommandPaletteEntityID> = []
        let byID = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for connection in input.connections where connection.freshness == .fresh {
            for workspace in connection.workspaces.sorted(by: {
                if $0.number != $1.number { return $0.number < $1.number }
                return $0.id < $1.id
            }) {
                let id = CommandPaletteEntityID(
                    kind: .workspace,
                    components: [connection.connection.id, workspace.id]
                )
                if let entity = byID[id], seen.insert(id).inserted { result.append(entity) }
            }
        }
        return result
    }
}
