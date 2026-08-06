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

public struct CommandPaletteEntity: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case pane, workspace, project, connection, command }

    public let id: CommandPaletteEntityID
    public let kind: Kind
    public let title: String
    public let detail: String
    public let state: String?
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
        state: String? = nil,
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
        self.state = state
        self.location = location
        self.shortcut = shortcut
        self.keywords = keywords
        self.route = route
        self.alternateRoute = alternateRoute
    }
}

public struct CommandPaletteSearch: Sendable {
    public init() {}

    public func results(query: String, entities: [CommandPaletteEntity]) -> [CommandPaletteEntity] {
        var unique: [CommandPaletteEntity] = []
        var indexByID: [CommandPaletteEntityID: Int] = [:]
        for entity in entities {
            if let index = indexByID[entity.id] {
                unique[index] = preferred(unique[index], entity)
            } else {
                indexByID[entity.id] = unique.count
                unique.append(entity)
            }
        }
        let terms = Self.tokens(query)
        guard !terms.isEmpty else { return unique }

        return unique.compactMap { entity -> (CommandPaletteEntity, Int)? in
            guard let score = score(entity, terms: terms) else { return nil }
            return (entity, score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.kind != $1.0.kind { return kindOrder($0.0.kind) < kindOrder($1.0.kind) }
            return $0.0.id.description < $1.0.id.description
        }.map(\.0)
    }

    private func preferred(_ lhs: CommandPaletteEntity, _ rhs: CommandPaletteEntity) -> CommandPaletteEntity {
        let left = lhs.location == nil ? 0 : 1
        let right = rhs.location == nil ? 0 : 1
        return right > left ? rhs : lhs
    }

    private func score(_ entity: CommandPaletteEntity, terms: [String]) -> Int? {
        let fields = [
            entity.title,
            entity.detail,
            entity.location ?? "",
            entity.state ?? "",
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
    public init() {}
    public mutating func take(_ entity: CommandPaletteEntity, alternate: Bool) -> CommandPaletteRouteIntent? {
        guard !dispatched else { return nil }
        guard !alternate || entity.alternateRoute != nil else { return nil }
        dispatched = true
        return alternate ? entity.alternateRoute : entity.route
    }
}

public enum CommandPaletteTargetResolution: Equatable, Sendable {
    case dispatch(CommandPaletteRouteIntent)
    case refreshRequired
}

public enum CommandPaletteTargetResolver {
    public static func resolve(
        _ entity: CommandPaletteEntity,
        currentEntityIDs: Set<CommandPaletteEntityID>
    ) -> CommandPaletteTargetResolution {
        switch entity.kind {
        case .pane, .workspace, .connection:
            currentEntityIDs.contains(entity.id) ? .dispatch(entity.route) : .refreshRequired
        case .project, .command:
            .dispatch(entity.route)
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
        let next = current + delta
        if next < 0 { return 0 }
        if next >= count { return count - 1 }
        return next
    }
}
