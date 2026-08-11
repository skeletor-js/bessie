import Darwin
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

public enum BessieWorkspaceScopePreference: Codable, Equatable, Sendable {
    case selectedTab(connectionID: String, workspaceID: String, tabID: String)
    case allTabs(connectionID: String, workspaceID: String)
    case allWorkspaces(connectionID: String)
    case allHerds

    private enum Kind: String, Codable {
        case selectedTab = "selected_tab"
        case allTabs = "all_tabs"
        case allWorkspaces = "all_workspaces"
        case allHerds = "all_herds"
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case connectionID = "connection_id"
        case workspaceID = "workspace_id"
        case tabID = "tab_id"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(Kind.self, forKey: .kind)
        func identifier(_ key: CodingKeys) throws -> String {
            let value = try values.decode(String.self, forKey: key)
            guard !value.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: values,
                    debugDescription: "Workspace scope identifiers must not be empty."
                )
            }
            return value
        }
        switch kind {
        case .selectedTab:
            self = try .selectedTab(
                connectionID: identifier(.connectionID),
                workspaceID: identifier(.workspaceID),
                tabID: identifier(.tabID)
            )
        case .allTabs:
            self = try .allTabs(
                connectionID: identifier(.connectionID),
                workspaceID: identifier(.workspaceID)
            )
        case .allWorkspaces:
            self = try .allWorkspaces(connectionID: identifier(.connectionID))
        case .allHerds:
            self = .allHerds
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .selectedTab(let connectionID, let workspaceID, let tabID):
            try values.encode(Kind.selectedTab, forKey: .kind)
            try values.encode(connectionID, forKey: .connectionID)
            try values.encode(workspaceID, forKey: .workspaceID)
            try values.encode(tabID, forKey: .tabID)
        case .allTabs(let connectionID, let workspaceID):
            try values.encode(Kind.allTabs, forKey: .kind)
            try values.encode(connectionID, forKey: .connectionID)
            try values.encode(workspaceID, forKey: .workspaceID)
        case .allWorkspaces(let connectionID):
            try values.encode(Kind.allWorkspaces, forKey: .kind)
            try values.encode(connectionID, forKey: .connectionID)
        case .allHerds:
            try values.encode(Kind.allHerds, forKey: .kind)
        }
    }
}

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
    public var ghosttyCompatibilityEnabled: Bool
    public var ghosttyCompatibilitySelectedPath: String?

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
        menuBarRowClickBehavior: BessieMenuBarRowClickBehavior = .focusPane,
        ghosttyCompatibilityEnabled: Bool = false,
        ghosttyCompatibilitySelectedPath: String? = nil
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
        self.ghosttyCompatibilityEnabled = ghosttyCompatibilityEnabled
        self.ghosttyCompatibilitySelectedPath = ghosttyCompatibilitySelectedPath
    }

    enum CodingKeys: String, CodingKey {
        case appearance, density, appIcon, cowprintEnabled, terminalFontSize, paneGap, notifications, startupBehavior, railCollapsed
        case menuBarVisible, menuBarBadgePolicy, menuBarRowClickBehavior
        case ghosttyCompatibilityEnabled, ghosttyCompatibilitySelectedPath
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
        ghosttyCompatibilityEnabled = try values.decodeIfPresent(Bool.self, forKey: .ghosttyCompatibilityEnabled) ?? false
        ghosttyCompatibilitySelectedPath = try values.decodeIfPresent(String.self, forKey: .ghosttyCompatibilitySelectedPath)
    }
}

public struct BessiePresentationState: Codable, Equatable, Sendable {
    public static let firstRealTerminalCompletionVersion = 1
    public var lastWorkspaceID: String?
    public var lastWorkspaceIDByConnectionID: [String: String]?
    public var preferences: BessiePreferences
    public var firstRealTerminalCompletionVersion: Int?
    public var panePresentationRevision: UInt64?
    public var panePresentationPreferences: [BessiePanePresentationPreference]?
    public var workspaceScope: BessieWorkspaceScopePreference?
    public init(
        lastWorkspaceID: String? = nil,
        lastWorkspaceIDByConnectionID: [String: String]? = nil,
        preferences: BessiePreferences = BessiePreferences(),
        firstRealTerminalCompletionVersion: Int? = nil,
        panePresentationRevision: UInt64? = nil,
        panePresentationPreferences: [BessiePanePresentationPreference]? = nil,
        workspaceScope: BessieWorkspaceScopePreference? = nil
    ) {
        self.lastWorkspaceID = lastWorkspaceID
        self.lastWorkspaceIDByConnectionID = lastWorkspaceIDByConnectionID
        self.preferences = preferences
        self.firstRealTerminalCompletionVersion = firstRealTerminalCompletionVersion
        self.panePresentationRevision = panePresentationRevision
        self.panePresentationPreferences = panePresentationPreferences
        self.workspaceScope = workspaceScope
    }

    enum CodingKeys: String, CodingKey {
        case lastWorkspaceID = "last_workspace_id"
        case lastWorkspaceIDByConnectionID = "last_workspace_id_by_connection_id"
        case preferences
        case firstRealTerminalCompletionVersion = "first_real_terminal_completion_version"
        case panePresentationRevision = "pane_presentation_revision"
        case panePresentationPreferences = "pane_presentation_preferences"
        case workspaceScope = "workspace_scope"
    }
}

public struct BessiePresentationStore: Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumFileBytes = 1_048_576
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load(now: Date = Date()) throws -> BessiePresentationState {
        try loadWithNormalizationStatus(now: now).state
    }

    public func loadWithNormalizationStatus(
        now: Date = Date()
    ) throws -> (state: BessiePresentationState, didNormalize: Bool) {
        var details = stat()
        guard lstat(url.path, &details) == 0 else {
            if errno == ENOENT { return (BessiePresentationState(), false) }
            throw BessiePresentationPersistenceError.invalidSource
        }
        guard (details.st_mode & S_IFMT) == S_IFREG, details.st_nlink == 1 else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        guard details.st_size <= Self.maximumFileBytes else {
            throw BessiePresentationPersistenceError.fileTooLarge
        }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw BessiePresentationPersistenceError.invalidSource }
        defer { close(descriptor) }
        let data = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readDataToEndOfFile()
        guard data.count <= Self.maximumFileBytes else { throw BessiePresentationPersistenceError.fileTooLarge }
        let probe = try JSONDecoder().decode(SchemaProbe.self, from: data)
        let state: BessiePresentationState
        guard let version = probe.schemaVersion else {
            state = try JSONDecoder().decode(BessiePresentationState.self, from: data)
            let result = try normalized(state, now: now)
            if result != state, state.panePresentationRevision == UInt64.max {
                throw BessiePanePresentationError.revisionOverflow
            }
            return (result, result != state)
        }
        guard version <= Self.currentSchemaVersion else {
            throw BessiePresentationPersistenceError.unsupportedSchema(version)
        }
        guard version == Self.currentSchemaVersion else {
            throw BessiePresentationPersistenceError.unsupportedSchema(version)
        }
        state = try JSONDecoder().decode(Envelope.self, from: data).state
        let result = try normalized(state, now: now)
        if result != state, state.panePresentationRevision == UInt64.max {
            throw BessiePanePresentationError.revisionOverflow
        }
        return (result, result != state)
    }
    public func save(_ state: BessiePresentationState) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        var parentDetails = stat()
        guard lstat(parent.path, &parentDetails) == 0,
              (parentDetails.st_mode & S_IFMT) == S_IFDIR,
              parent.standardizedFileURL.path == parent.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        var existingDetails = stat()
        if lstat(url.path, &existingDetails) == 0 {
            guard (existingDetails.st_mode & S_IFMT) == S_IFREG, existingDetails.st_nlink == 1 else {
                throw BessiePresentationPersistenceError.invalidSource
            }
        } else if errno != ENOENT {
            throw BessiePresentationPersistenceError.invalidSource
        }
        let normalized = try normalized(state, now: .distantPast)
        let data = try JSONEncoder().encode(Envelope(schemaVersion: Self.currentSchemaVersion, state: normalized))
        guard data.count <= Self.maximumFileBytes else { throw BessiePresentationPersistenceError.fileTooLarge }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func normalized(_ state: BessiePresentationState, now: Date) throws -> BessiePresentationState {
        var state = state
        let ledger = try BessiePanePresentationLedger(
            revision: state.panePresentationRevision ?? 0,
            records: state.panePresentationPreferences ?? [],
            now: now
        )
        state.panePresentationRevision = ledger.revision == 0 ? nil : ledger.revision
        state.panePresentationPreferences = ledger.records.isEmpty ? nil : ledger.records
        return state
    }

    private struct SchemaProbe: Decodable { let schemaVersion: Int? }
    private struct Envelope: Codable {
        let schemaVersion: Int
        let state: BessiePresentationState
    }
}

public enum BessiePresentationPersistenceError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    case fileTooLarge
    case invalidSource
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "This settings file uses unsupported schema version \(version). Update Bessie before changing settings."
        case .fileTooLarge:
            "The presentation settings file exceeds Bessie's 1 MiB safety limit."
        case .invalidSource:
            "The presentation settings path is not a safe regular file."
        }
    }
}

public enum BessiePresentationLeaseError: Error, Equatable, LocalizedError, Sendable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let path): "Bessie presentation settings are in use by another process: \(path)"
        }
    }
}

public final class BessiePresentationLease: @unchecked Sendable {
    private struct Entry { let descriptor: Int32; var references: Int }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: Entry] = [:]
    }
    private static let registry = Registry()
    private let path: String

    private init(path: String) { self.path = path }

    deinit {
        Self.registry.lock.withLock {
            guard var entry = Self.registry.entries[path] else { return }
            entry.references -= 1
            if entry.references == 0 {
                flock(entry.descriptor, LOCK_UN)
                close(entry.descriptor)
                Self.registry.entries.removeValue(forKey: path)
            } else {
                Self.registry.entries[path] = entry
            }
        }
    }

    public static func lockURL(for presentationURL: URL) -> URL {
        presentationURL.deletingLastPathComponent().appendingPathComponent(".bessie-presentation.lock")
    }

    public static func acquire(for presentationURL: URL) throws -> BessiePresentationLease {
        let lockURL = lockURL(for: presentationURL)
        if registry.lock.withLock({ () -> Bool in
            guard var entry = registry.entries[lockURL.path] else { return false }
            entry.references += 1
            registry.entries[lockURL.path] = entry
            return true
        }) {
            return BessiePresentationLease(path: lockURL.path)
        }
        let parent = lockURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        var parentDetails = stat()
        guard lstat(parent.path, &parentDetails) == 0,
              (parentDetails.st_mode & S_IFMT) == S_IFDIR,
              parentDetails.st_uid == geteuid(),
              (parentDetails.st_mode & 0o077) == 0,
              parent.standardizedFileURL.path == parent.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw BessiePresentationLeaseError.unavailable(lockURL.path)
        }
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BessiePresentationLeaseError.unavailable(lockURL.path) }
        var details = stat()
        guard fstat(descriptor, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFREG,
              details.st_uid == geteuid(),
              details.st_nlink == 1,
              (details.st_mode & 0o077) == 0,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw BessiePresentationLeaseError.unavailable(lockURL.path)
        }
        registry.lock.withLock {
            registry.entries[lockURL.path] = Entry(descriptor: descriptor, references: 1)
        }
        return BessiePresentationLease(path: lockURL.path)
    }
}
