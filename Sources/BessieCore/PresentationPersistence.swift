import Foundation

public enum BessieThemeID: String, Codable, CaseIterable, Equatable, Sendable {
    case system, dark, light
    case catppuccinLatte, catppuccinFrappe, catppuccinMacchiato, catppuccinMocha

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .dark
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public typealias BessieAppearance = BessieThemeID
public enum BessieDensity: String, Codable, CaseIterable, Equatable, Sendable { case comfortable, compact }
public enum BessieAppIcon: String, Codable, CaseIterable, Equatable, Sendable { case dark, light }
public enum BessieNotifications: String, Codable, CaseIterable, Equatable, Sendable { case off, blockedOnly, blockedAndDone }
public enum BessieStartupBehavior: String, Codable, CaseIterable, Equatable, Sendable { case lastWorkspace, workspaceChooser }
public enum BessieMenuBarBadgePolicy: String, Codable, CaseIterable, Equatable, Sendable { case needsYou, needsYouAndUnknown, nothing }
public enum BessieMenuBarRowClickBehavior: String, Codable, CaseIterable, Equatable, Sendable { case focusPane, openBessie }

public enum BessieFeature: String, CaseIterable, Equatable, Sendable {
    case fileBrowserEditor
    case followFiles
}

public struct BessieFeatureFlags: Equatable, Sendable {
    public static let developerEnvironmentKey = "BESSIE_DEVELOPER_FEATURES"
    public static let v1 = BessieFeatureFlags()

    private let enabled: Set<BessieFeature>

    public init(enabled: Set<BessieFeature> = []) {
        self.enabled = enabled
    }

    public init(environment: [String: String]) {
        let values = environment[Self.developerEnvironmentKey, default: ""]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        enabled = Set(values.compactMap(BessieFeature.init(rawValue:)))
    }

    public func isEnabled(_ feature: BessieFeature) -> Bool { enabled.contains(feature) }
}

public struct BessiePreferences: Codable, Equatable, Sendable {
    public var appearance: BessieAppearance
    public var density: BessieDensity
    public var appIcon: BessieAppIcon
    public var cowprintEnabled: Bool
    public var terminalFontSize: Double
    public var paneGap: Double
    public var notifications: BessieNotifications
    public var startupBehavior: BessieStartupBehavior
    public var railCollapsed: Bool
    public var menuBarVisible: Bool
    public var menuBarBadgePolicy: BessieMenuBarBadgePolicy
    public var menuBarRowClickBehavior: BessieMenuBarRowClickBehavior

    public init(
        appearance: BessieAppearance = .dark,
        density: BessieDensity = .comfortable,
        appIcon: BessieAppIcon = .dark,
        cowprintEnabled: Bool = true,
        terminalFontSize: Double = 13,
        paneGap: Double = 7,
        notifications: BessieNotifications = .blockedOnly,
        startupBehavior: BessieStartupBehavior = .workspaceChooser,
        railCollapsed: Bool = false,
        menuBarVisible: Bool = true,
        menuBarBadgePolicy: BessieMenuBarBadgePolicy = .needsYou,
        menuBarRowClickBehavior: BessieMenuBarRowClickBehavior = .focusPane
    ) {
        self.appearance = appearance
        self.density = density
        self.appIcon = appIcon
        self.cowprintEnabled = cowprintEnabled
        self.terminalFontSize = terminalFontSize
        self.paneGap = paneGap
        self.notifications = notifications
        self.startupBehavior = startupBehavior
        self.railCollapsed = railCollapsed
        self.menuBarVisible = menuBarVisible
        self.menuBarBadgePolicy = menuBarBadgePolicy
        self.menuBarRowClickBehavior = menuBarRowClickBehavior
    }

    enum CodingKeys: String, CodingKey {
        case appearance, density, appIcon, cowprintEnabled, terminalFontSize, paneGap, notifications, startupBehavior, railCollapsed
        case menuBarVisible, menuBarBadgePolicy, menuBarRowClickBehavior
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(BessieAppearance.self, forKey: .appearance) ?? .dark
        density = try values.decodeIfPresent(BessieDensity.self, forKey: .density) ?? .comfortable
        appIcon = try values.decodeIfPresent(BessieAppIcon.self, forKey: .appIcon) ?? .dark
        cowprintEnabled = try values.decodeIfPresent(Bool.self, forKey: .cowprintEnabled) ?? true
        terminalFontSize = try values.decodeIfPresent(Double.self, forKey: .terminalFontSize) ?? 13
        paneGap = try values.decodeIfPresent(Double.self, forKey: .paneGap) ?? 7
        notifications = try values.decodeIfPresent(BessieNotifications.self, forKey: .notifications) ?? .blockedOnly
        startupBehavior = try values.decodeIfPresent(BessieStartupBehavior.self, forKey: .startupBehavior) ?? .workspaceChooser
        railCollapsed = try values.decodeIfPresent(Bool.self, forKey: .railCollapsed) ?? false
        menuBarVisible = try values.decodeIfPresent(Bool.self, forKey: .menuBarVisible) ?? true
        menuBarBadgePolicy = try values.decodeIfPresent(BessieMenuBarBadgePolicy.self, forKey: .menuBarBadgePolicy) ?? .needsYou
        menuBarRowClickBehavior = try values.decodeIfPresent(BessieMenuBarRowClickBehavior.self, forKey: .menuBarRowClickBehavior) ?? .focusPane
    }
}

public struct BessiePresentationState: Codable, Equatable, Sendable {
    public static let firstRealTerminalCompletionVersion = 1
    public var lastWorkspaceID: String?
    public var lastWorkspaceIDByConnectionID: [String: String]?
    public var preferences: BessiePreferences
    public var firstRealTerminalCompletionVersion: Int?
    public init(
        lastWorkspaceID: String? = nil,
        lastWorkspaceIDByConnectionID: [String: String]? = nil,
        preferences: BessiePreferences = BessiePreferences(),
        firstRealTerminalCompletionVersion: Int? = nil
    ) {
        self.lastWorkspaceID = lastWorkspaceID
        self.lastWorkspaceIDByConnectionID = lastWorkspaceIDByConnectionID
        self.preferences = preferences
        self.firstRealTerminalCompletionVersion = firstRealTerminalCompletionVersion
    }

    enum CodingKeys: String, CodingKey {
        case lastWorkspaceID = "last_workspace_id"
        case lastWorkspaceIDByConnectionID = "last_workspace_id_by_connection_id"
        case preferences
        case firstRealTerminalCompletionVersion = "first_real_terminal_completion_version"
    }
}

public struct BessiePresentationStore: Sendable {
    public static let currentSchemaVersion = 1
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> BessiePresentationState {
        guard FileManager.default.fileExists(atPath: url.path) else { return BessiePresentationState() }
        let data = try Data(contentsOf: url)
        let probe = try JSONDecoder().decode(SchemaProbe.self, from: data)
        guard let version = probe.schemaVersion else {
            return try JSONDecoder().decode(BessiePresentationState.self, from: data)
        }
        guard version <= Self.currentSchemaVersion else {
            throw BessiePresentationPersistenceError.unsupportedSchema(version)
        }
        guard version == Self.currentSchemaVersion else {
            throw BessiePresentationPersistenceError.unsupportedSchema(version)
        }
        return try JSONDecoder().decode(Envelope.self, from: data).state
    }
    public func save(_ state: BessiePresentationState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Envelope(schemaVersion: Self.currentSchemaVersion, state: state)).write(to: url, options: .atomic)
    }

    private struct SchemaProbe: Decodable { let schemaVersion: Int? }
    private struct Envelope: Codable {
        let schemaVersion: Int
        let state: BessiePresentationState
    }
}

public enum BessiePresentationPersistenceError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    public var errorDescription: String? {
        switch self { case .unsupportedSchema(let version): "This settings file uses unsupported schema version \(version). Update Bessie before changing settings." }
    }
}
