import Foundation

public struct CommandPaletteEntityID: Hashable, Sendable, CustomStringConvertible {
    public let kind: CommandPaletteEntity.Kind
    public let components: [String]

    public init(kind: CommandPaletteEntity.Kind, components: [String]) {
        self.kind = kind
        self.components = components
    }

    public var description: String { ([kind.rawValue] + components).joined(separator: "::") }
}

public enum CommandPaletteRouteIntent: Equatable, Sendable {
    case pane(connectionID: String, workspaceID: String, tabID: String, paneID: String)
    case workspace(connectionID: String, workspaceID: String)
    case project(UUID)
    case connection(String)
    case command(BessieShortcutCommand)
}

public enum CommandPaletteFreshness: String, Equatable, Sendable {
    case fresh
    case disconnected
}

public struct CommandPaletteEntity: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case pane, workspace, project, connection, command }

    public let id: CommandPaletteEntityID
    public let kind: Kind
    public let title: String
    public let detail: String
    public let semanticState: AgentSemanticState?
    public let freshness: CommandPaletteFreshness
    public let provider: String?
    public let location: String?
    public let shortcut: String?
    public let keywords: [String]
    public let route: CommandPaletteRouteIntent
    public let alternateRoute: CommandPaletteRouteIntent?

    public init(
        id: CommandPaletteEntityID,
        kind: Kind,
        title: String,
        detail: String,
        semanticState: AgentSemanticState? = nil,
        freshness: CommandPaletteFreshness = .fresh,
        provider: String? = nil,
        location: String? = nil,
        shortcut: String? = nil,
        keywords: [String] = [],
        route: CommandPaletteRouteIntent,
        alternateRoute: CommandPaletteRouteIntent? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.semanticState = semanticState
        self.freshness = freshness
        self.provider = provider
        self.location = location
        self.shortcut = shortcut
        self.keywords = keywords
        self.route = route
        self.alternateRoute = alternateRoute
    }

    public var connectionID: String? {
        switch route {
        case .pane(let connectionID, _, _, _), .workspace(let connectionID, _), .connection(let connectionID):
            connectionID
        case .project, .command:
            nil
        }
    }

    public var requiresUserAction: Bool { semanticState?.requiresUserAction == true }
}

public struct CommandPaletteSearch: Sendable {
    public init() {}

    public func results(
        query: String,
        entities: [CommandPaletteEntity],
        activeConnectionID: String? = nil
    ) -> [CommandPaletteEntity] {
        rankedResults(
            query: query,
            entities: deduplicated(entities),
            activeConnectionID: activeConnectionID
        )
    }

    func resultsFromDeduplicated(
        query: String,
        entities: [CommandPaletteEntity],
        activeConnectionID: String? = nil
    ) -> [CommandPaletteEntity] {
        rankedResults(query: query, entities: entities, activeConnectionID: activeConnectionID)
    }

    private func rankedResults(
        query: String,
        entities: [CommandPaletteEntity],
        activeConnectionID: String?
    ) -> [CommandPaletteEntity] {
        let terms = Self.tokens(query)
        guard !terms.isEmpty else { return [] }

        return entities.compactMap { entity -> (CommandPaletteEntity, Int)? in
            guard let score = score(entity, terms: terms) else { return nil }
            return (entity, score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.requiresUserAction != $1.0.requiresUserAction { return $0.0.requiresUserAction }
            let leftIsActive = $0.0.connectionID == activeConnectionID
            let rightIsActive = $1.0.connectionID == activeConnectionID
            if leftIsActive != rightIsActive { return leftIsActive }
            if $0.0.kind != $1.0.kind { return kindOrder($0.0.kind) < kindOrder($1.0.kind) }
            return $0.0.id.description < $1.0.id.description
        }.map(\.0)
    }

    func deduplicated(_ entities: [CommandPaletteEntity]) -> [CommandPaletteEntity] {
        var byID: [CommandPaletteEntityID: CommandPaletteEntity] = [:]
        for entity in entities {
            if let existing = byID[entity.id] {
                byID[entity.id] = preferred(existing, entity)
            } else {
                byID[entity.id] = entity
            }
        }
        return byID.values.sorted { $0.id.description < $1.id.description }
    }

    private func preferred(_ lhs: CommandPaletteEntity, _ rhs: CommandPaletteEntity) -> CommandPaletteEntity {
        if lhs.freshness != rhs.freshness {
            return rhs.freshness == .fresh ? rhs : lhs
        }
        let leftCompleteness = completeness(lhs)
        let rightCompleteness = completeness(rhs)
        if leftCompleteness != rightCompleteness {
            return rightCompleteness > leftCompleteness ? rhs : lhs
        }
        return canonicalKey(rhs) < canonicalKey(lhs) ? rhs : lhs
    }

    private func completeness(_ entity: CommandPaletteEntity) -> Int {
        [entity.detail, entity.location, entity.provider, entity.shortcut]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .count + (entity.semanticState == nil ? 0 : 1)
    }

    private func canonicalKey(_ entity: CommandPaletteEntity) -> String {
        [
            entity.title, entity.detail, entity.location ?? "", entity.provider ?? "",
            entity.semanticState?.rawValue ?? "", entity.freshness.rawValue, entity.shortcut ?? "",
            entity.keywords.joined(separator: "\u{1f}"), String(describing: entity.route),
            String(describing: entity.alternateRoute),
        ].joined(separator: "\u{1e}")
    }

    private func score(_ entity: CommandPaletteEntity, terms: [String]) -> Int? {
        let fields = [
            entity.title,
            entity.detail,
            entity.location ?? "",
            entity.semanticState.map { HerdPresentationStatus(state: $0).rawValue } ?? "",
        ] + entity.keywords + [entity.shortcut ?? ""]
        var total = 0
        for term in terms {
            let scores = fields.enumerated().compactMap { index, field in
                fuzzyScore(term, in: field.lowercased()).map {
                    $0 - min(index * 100, 50_000)
                }
            }
            guard let best = scores.max() else { return nil }
            total += best
        }
        return total
    }

    private func fuzzyScore(_ needle: String, in haystack: String) -> Int? {
        if haystack == needle { return 5_000_000 }
        if haystack.hasPrefix(needle) { return 4_000_000 - min(haystack.count, 100_000) }
        var contiguousPosition: Int?
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let position = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            let previous = haystack[haystack.index(before: range.lowerBound)]
            if !previous.isLetter && !previous.isNumber {
                return 3_000_000 - min(position, 100_000)
            }
            if contiguousPosition == nil { contiguousPosition = position }
            searchStart = haystack.index(after: range.lowerBound)
        }
        if let contiguousPosition {
            return 2_000_000 - min(contiguousPosition, 100_000)
        }
        var cursor = haystack.startIndex
        var gap = 0
        for character in needle {
            guard let match = haystack[cursor...].firstIndex(of: character) else { return nil }
            gap += haystack.distance(from: cursor, to: match)
            cursor = haystack.index(after: match)
        }
        return 1_000_000 - min(gap, 100_000)
    }

    private static func tokens(_ value: String) -> [String] {
        value.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private func kindOrder(_ kind: CommandPaletteEntity.Kind) -> Int {
        CommandPaletteEntity.Kind.allCases.firstIndex(of: kind) ?? 0
    }
}

public struct CommandPaletteDispatchGate: Sendable {
    private var dispatched = false
    private var activationInFlight = false
    public init() {}

    public mutating func begin(_ entity: CommandPaletteEntity, alternate: Bool) -> CommandPaletteRouteIntent? {
        guard !dispatched, !activationInFlight else { return nil }
        guard !alternate || entity.alternateRoute != nil else { return nil }
        activationInFlight = true
        return alternate ? entity.alternateRoute : entity.route
    }

    public mutating func commit(_ route: CommandPaletteRouteIntent) -> CommandPaletteRouteIntent? {
        guard activationInFlight, !dispatched else { return nil }
        activationInFlight = false
        dispatched = true
        return route
    }

    public mutating func cancelActivation() {
        guard !dispatched else { return }
        activationInFlight = false
    }

    public mutating func take(_ entity: CommandPaletteEntity, alternate: Bool) -> CommandPaletteRouteIntent? {
        guard let route = begin(entity, alternate: alternate) else { return nil }
        return commit(route)
    }
}

public enum CommandPaletteTargetResolution: Equatable, Sendable {
    case dispatch(CommandPaletteRouteIntent)
    case refreshRequired
    case connectionUnavailable(String)
}

public enum CommandPaletteTargetResolver {
    public static func resolve(
        _ entity: CommandPaletteEntity,
        currentEntities: [CommandPaletteEntity],
        alternate: Bool = false
    ) -> CommandPaletteTargetResolution {
        let current = currentEntities.first { $0.id == entity.id }
        switch entity.kind {
        case .pane, .workspace:
            if let current {
                return .dispatch(alternate ? current.alternateRoute ?? current.route : current.route)
            }
            if let connectionID = entity.connectionID,
               currentEntities.contains(where: {
                   $0.kind == .connection
                       && $0.connectionID == connectionID
                       && $0.freshness == .disconnected
               }) {
                return .connectionUnavailable(connectionID)
            }
            return .refreshRequired
        case .connection:
            guard let current else { return .refreshRequired }
            return .dispatch(alternate ? current.alternateRoute ?? current.route : current.route)
        case .project, .command:
            return .dispatch(alternate ? entity.alternateRoute ?? entity.route : entity.route)
        }
    }
}

/// Pure keyboard routing for the open command palette.
/// Arrow keys must move the result selection even while the search field owns first responder.
public enum CommandPaletteKeyboard {
    public enum Action: Equatable, Sendable {
        case moveSelection(delta: Int)
        case activate(alternate: Bool)
        case dismiss
        case ignore
    }

    /// macOS key codes used by the palette monitor.
    public static let upArrow: UInt16 = 126
    public static let downArrow: UInt16 = 125
    public static let escape: UInt16 = 53
    public static let returnKey: UInt16 = 36
    public static let keypadEnter: UInt16 = 76

    public static func action(
        keyCode: UInt16,
        command: Bool,
        option: Bool,
        control: Bool,
        shift: Bool
    ) -> Action {
        // Only plain navigation / return / escape (plus ⌘↩ alternate).
        if option || control { return .ignore }
        if shift { return .ignore }

        switch keyCode {
        case upArrow:
            return command ? .ignore : .moveSelection(delta: -1)
        case downArrow:
            return command ? .ignore : .moveSelection(delta: 1)
        case escape:
            return command ? .ignore : .dismiss
        case returnKey, keypadEnter:
            return .activate(alternate: command)
        default:
            return .ignore
        }
    }

    public static func movedSelection(current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        guard count > 1 else { return 0 }
        let normalizedCurrent = min(max(current, 0), count - 1)
        let next = (normalizedCurrent + delta) % count
        return next >= 0 ? next : next + count
    }
}
