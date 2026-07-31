import Foundation

public enum BessieAppearance: String, Codable, CaseIterable, Equatable, Sendable { case system, dark, light }
public enum BessieNotifications: String, Codable, CaseIterable, Equatable, Sendable { case off, blockedOnly, blockedAndDone }
public enum BessieStartupBehavior: String, Codable, CaseIterable, Equatable, Sendable { case lastWorkspace, workspaceChooser }

public struct BessiePreferences: Codable, Equatable, Sendable {
    public var appearance: BessieAppearance
    public var cowPrintIntensity: Double
    public var cowPrintMotion: Bool
    public var terminalFontSize: Double
    public var paneGap: Double
    public var notifications: BessieNotifications
    public var startupBehavior: BessieStartupBehavior

    public init(
        appearance: BessieAppearance = .system,
        cowPrintIntensity: Double = 0.05,
        cowPrintMotion: Bool = true,
        terminalFontSize: Double = 13,
        paneGap: Double = 7,
        notifications: BessieNotifications = .blockedOnly,
        startupBehavior: BessieStartupBehavior = .lastWorkspace
    ) {
        self.appearance = appearance
        self.cowPrintIntensity = cowPrintIntensity
        self.cowPrintMotion = cowPrintMotion
        self.terminalFontSize = terminalFontSize
        self.paneGap = paneGap
        self.notifications = notifications
        self.startupBehavior = startupBehavior
    }

    enum CodingKeys: String, CodingKey {
        case appearance, cowPrintIntensity, cowPrintMotion, terminalFontSize, paneGap, notifications, startupBehavior
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(BessieAppearance.self, forKey: .appearance) ?? .system
        cowPrintIntensity = try values.decodeIfPresent(Double.self, forKey: .cowPrintIntensity) ?? 0.05
        cowPrintMotion = try values.decodeIfPresent(Bool.self, forKey: .cowPrintMotion) ?? true
        terminalFontSize = try values.decodeIfPresent(Double.self, forKey: .terminalFontSize) ?? 13
        paneGap = try values.decodeIfPresent(Double.self, forKey: .paneGap) ?? 7
        notifications = try values.decodeIfPresent(BessieNotifications.self, forKey: .notifications) ?? .blockedOnly
        startupBehavior = try values.decodeIfPresent(BessieStartupBehavior.self, forKey: .startupBehavior) ?? .lastWorkspace
    }
}

public struct BessiePresentationState: Codable, Equatable, Sendable {
    public var lastWorkspaceID: String?
    public var preferences: BessiePreferences
    public init(lastWorkspaceID: String? = nil, preferences: BessiePreferences = BessiePreferences()) {
        self.lastWorkspaceID = lastWorkspaceID
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey {
        case lastWorkspaceID = "last_workspace_id"
        case preferences
    }
}

public struct BessiePresentationStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> BessiePresentationState {
        guard FileManager.default.fileExists(atPath: url.path) else { return BessiePresentationState() }
        return try JSONDecoder().decode(BessiePresentationState.self, from: Data(contentsOf: url))
    }
    public func save(_ state: BessiePresentationState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
