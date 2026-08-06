import Foundation
import CoreFoundation

public enum BessieProjectSchema {
    public static let currentVersion = 2
    public static let supportedVersions: ClosedRange<Int> = 1...2
}

public enum BessieProjectSchemaError: Error, Equatable, Sendable {
    case missingVersion
    case unsupportedVersion(Int)
    case invalidDocument(String)
}

public struct BessieProject: Codable, Equatable, Identifiable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public var name: String
    public var projectDescription: String
    /// Retained only so schema-v1 catalogs can round-trip without data loss.
    /// Grouping is not an active V1 product concept.
    public var group: String?
    public var folders: [BessieProjectFolder]
    public var tabs: [BessieProjectTab]
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    public init(
        schemaVersion: Int = BessieProjectSchema.currentVersion,
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        group: String? = nil,
        folders: [BessieProjectFolder],
        tabs: [BessieProjectTab],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.group = group
        self.folders = folders
        self.tabs = tabs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    public init(
        schemaVersion: Int = BessieProjectSchema.currentVersion,
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        group: String? = nil,
        workingDirectory: String,
        tabs: [BessieProjectTab],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.init(
            schemaVersion: schemaVersion,
            id: id,
            name: name,
            projectDescription: projectDescription,
            group: group,
            folders: [.init(id: id, name: "Primary", path: workingDirectory, isPrimary: true)],
            tabs: tabs,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: archivedAt
        )
    }

    public var primaryFolder: BessieProjectFolder? {
        folders.first(where: \.isPrimary)
    }

    /// Compatibility access for callers that only need the required primary folder.
    public var workingDirectory: String {
        get { primaryFolder?.path ?? "" }
        set {
            if let index = folders.firstIndex(where: \.isPrimary) {
                folders[index].path = newValue
            } else {
                folders.append(.init(name: "Primary", path: newValue, isPrimary: true))
            }
        }
    }

    public func folder(for pane: BessieProjectPane) -> BessieProjectFolder? {
        guard let folderID = pane.folderID else { return primaryFolder }
        return folders.first { $0.id == folderID }
    }

    public func workingDirectory(for pane: BessieProjectPane) -> String? {
        folder(for: pane)?.path
    }

    public func normalized(fileManager: FileManager = .default) throws -> BessieProject {
        try normalized(fileManager: fileManager, requireWorkingDirectoryExists: true)
    }

    func normalizedForCatalog(fileManager: FileManager = .default) throws -> BessieProject {
        try normalized(fileManager: fileManager, requireWorkingDirectoryExists: false)
    }

    private func normalized(
        fileManager: FileManager,
        requireWorkingDirectoryExists: Bool
    ) throws -> BessieProject {
        var project = self
        var issues: [BessieProjectValidationIssue] = []

        if schemaVersion != BessieProjectSchema.currentVersion {
            issues.append(.init(code: .unsupportedSchemaVersion, projectID: id, field: "schemaVersion"))
        }

        project.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if project.name.isEmpty {
            issues.append(.init(code: .emptyName, projectID: id, field: "name"))
        }
        project.group = group?.bessieTrimmedOrNil

        if folders.filter(\.isPrimary).count != 1 {
            issues.append(.init(code: .invalidPrimaryFolderCount, projectID: id, field: "folders"))
        }
        var seenFolderIDs: Set<UUID> = []
        var seenFolderPaths: Set<String> = []
        for folderIndex in project.folders.indices {
            var folder = project.folders[folderIndex]
            folder.name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if folder.name.isEmpty {
                issues.append(.init(code: .emptyFolderName, projectID: id, folderID: folder.id, field: "folders.name"))
            }
            if !seenFolderIDs.insert(folder.id).inserted {
                issues.append(.init(code: .duplicateFolderID, projectID: id, folderID: folder.id, field: "folders.id"))
            }
            guard NSString(string: folder.path).isAbsolutePath else {
                issues.append(.init(code: .folderNotAbsolute, projectID: id, folderID: folder.id, field: "folders.path"))
                continue
            }
            let standardized = URL(fileURLWithPath: folder.path, isDirectory: true).standardizedFileURL
            let normalizedPath = standardized.resolvingSymlinksInPath().path
            if !seenFolderPaths.insert(normalizedPath).inserted {
                issues.append(.init(code: .duplicateFolderPath, projectID: id, folderID: folder.id, field: "folders.path"))
            }
            if requireWorkingDirectoryExists {
                var isDirectory: ObjCBool = false
                if !fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
                    issues.append(.init(code: .folderNotDirectory, projectID: id, folderID: folder.id, field: "folders.path"))
                } else if !fileManager.isReadableFile(atPath: normalizedPath)
                    || !fileManager.isExecutableFile(atPath: normalizedPath)
                {
                    issues.append(.init(code: .folderInaccessible, projectID: id, folderID: folder.id, field: "folders.path"))
                }
            }
            folder.path = normalizedPath
            project.folders[folderIndex] = folder
        }

        if tabs.isEmpty {
            issues.append(.init(code: .missingTabs, projectID: id, field: "tabs"))
        }

        var seenTabIDs: Set<UUID> = []
        var paneTabByID: [UUID: UUID] = [:]
        for tab in tabs {
            if !seenTabIDs.insert(tab.id).inserted {
                issues.append(.init(code: .duplicateTabID, projectID: id, tabID: tab.id, field: "id"))
            }
            for pane in tab.panes {
                if paneTabByID.updateValue(tab.id, forKey: pane.id) != nil {
                    issues.append(.init(code: .duplicatePaneID, projectID: id, tabID: tab.id, paneID: pane.id, field: "id"))
                }
            }
        }

        for tabIndex in project.tabs.indices {
            project.tabs[tabIndex].name = project.tabs[tabIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)
            let tab = project.tabs[tabIndex]
            if tab.name.isEmpty {
                issues.append(.init(code: .emptyName, projectID: id, tabID: tab.id, field: "name"))
            }
            if tab.panes.isEmpty {
                issues.append(.init(code: .missingPanes, projectID: id, tabID: tab.id, field: "panes"))
            }

            let rootCount = tab.panes.reduce(into: 0) { count, pane in
                if case .root = pane.placement { count += 1 }
            }
            if rootCount != 1 {
                issues.append(.init(code: .invalidRootCount, projectID: id, tabID: tab.id, field: "panes"))
            }

            var earlierPaneIDs: Set<UUID> = []
            for paneIndex in project.tabs[tabIndex].panes.indices {
                var pane = project.tabs[tabIndex].panes[paneIndex]
                pane.label = pane.label?.bessieTrimmedOrNil
                if pane.command == "" { pane.command = nil }
                if let command = pane.command, command.contains("\r") || command.contains("\n") {
                    issues.append(.init(
                        code: .commandContainsLineBreak, projectID: id, tabID: tab.id,
                        paneID: pane.id, field: "command"
                    ))
                }
                if let folderID = pane.folderID, !seenFolderIDs.contains(folderID) {
                    issues.append(.init(
                        code: .paneFolderMissing, projectID: id, folderID: folderID,
                        tabID: tab.id, paneID: pane.id, field: "folderID"
                    ))
                }

                if case .split(let parentID, _, let ratio) = pane.placement {
                    if !ratio.isFinite || !(0.1...0.9).contains(ratio) {
                        issues.append(.init(
                            code: .invalidSplitRatio, projectID: id, tabID: tab.id,
                            paneID: pane.id, field: "placement.ratio"
                        ))
                    }
                    if paneTabByID[parentID] == nil {
                        issues.append(.init(
                            code: .splitParentMissing, projectID: id, tabID: tab.id,
                            paneID: pane.id, field: "placement.fromPaneID"
                        ))
                    } else if paneTabByID[parentID] != tab.id {
                        issues.append(.init(
                            code: .splitParentCrossTab, projectID: id, tabID: tab.id,
                            paneID: pane.id, field: "placement.fromPaneID"
                        ))
                    } else if !earlierPaneIDs.contains(parentID) {
                        issues.append(.init(
                            code: .splitParentNotEarlier, projectID: id, tabID: tab.id,
                            paneID: pane.id, field: "placement.fromPaneID"
                        ))
                    }
                }
                project.tabs[tabIndex].panes[paneIndex] = pane
                earlierPaneIDs.insert(pane.id)
            }

            issues.append(contentsOf: Self.cycleIssues(projectID: id, tab: tab))
        }

        guard issues.isEmpty else { throw BessieProjectValidationError(issues: issues) }
        return project
    }

    private static func cycleIssues(projectID: UUID, tab: BessieProjectTab) -> [BessieProjectValidationIssue] {
        var parentByPaneID: [UUID: UUID] = [:]
        for pane in tab.panes {
            guard case .split(let parentID, _, _) = pane.placement else { continue }
            parentByPaneID[pane.id] = parentID
        }
        let paneIDs = Set(tab.panes.map(\.id))
        var complete: Set<UUID> = []
        var issues: [BessieProjectValidationIssue] = []

        for startID in paneIDs where !complete.contains(startID) {
            var path: [UUID] = []
            var positions: [UUID: Int] = [:]
            var currentID: UUID? = startID
            while let id = currentID, paneIDs.contains(id), !complete.contains(id) {
                if let cycleStart = positions[id] {
                    for paneID in path[cycleStart...] {
                        issues.append(.init(
                            code: .splitCycle, projectID: projectID, tabID: tab.id,
                            paneID: paneID, field: "placement.fromPaneID"
                        ))
                    }
                    break
                }
                positions[id] = path.count
                path.append(id)
                currentID = parentByPaneID[id]
            }
            complete.formUnion(path)
        }
        return issues
    }
}

public struct BessieProjectFolder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    public var isPrimary: Bool

    public init(id: UUID = UUID(), name: String, path: String, isPrimary: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.isPrimary = isPrimary
    }
}

public struct BessieProjectTab: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var panes: [BessieProjectPane]

    public init(id: UUID = UUID(), name: String, panes: [BessieProjectPane]) {
        self.id = id
        self.name = name
        self.panes = panes
    }
}

public struct BessieProjectPane: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var label: String?
    public var command: String?
    public var folderID: UUID?
    public var placement: BessieProjectPanePlacement

    public init(
        id: UUID = UUID(),
        label: String? = nil,
        command: String? = nil,
        folderID: UUID? = nil,
        placement: BessieProjectPanePlacement
    ) {
        self.id = id
        self.label = label
        self.command = command
        self.folderID = folderID
        self.placement = placement
    }
}

public enum BessieProjectPanePlacement: Codable, Equatable, Sendable {
    case root
    case split(fromPaneID: UUID, direction: SplitDirection, ratio: Double)

    private enum CodingKeys: String, CodingKey { case type, fromPaneID, direction, ratio }
    private enum Kind: String, Codable { case root, split }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .root:
            self = .root
        case .split:
            self = .split(
                fromPaneID: try values.decode(UUID.self, forKey: .fromPaneID),
                direction: try values.decode(SplitDirection.self, forKey: .direction),
                ratio: try values.decode(Double.self, forKey: .ratio)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .root:
            try values.encode(Kind.root, forKey: .type)
        case .split(let fromPaneID, let direction, let ratio):
            try values.encode(Kind.split, forKey: .type)
            try values.encode(fromPaneID, forKey: .fromPaneID)
            try values.encode(direction, forKey: .direction)
            try values.encode(ratio, forKey: .ratio)
        }
    }
}

public struct BessieProjectValidationIssue: Error, Codable, Equatable, Sendable {
    public enum Code: String, Codable, Equatable, Sendable {
        case unsupportedSchemaVersion
        case emptyName
        case invalidPrimaryFolderCount
        case emptyFolderName
        case duplicateFolderID
        case duplicateFolderPath
        case folderNotAbsolute
        case folderNotDirectory
        case folderInaccessible
        case paneFolderMissing
        // Schema-v1 aliases retained for source compatibility.
        case workingDirectoryNotAbsolute
        case workingDirectoryNotDirectory
        case missingTabs
        case missingPanes
        case duplicateTabID
        case duplicatePaneID
        case invalidRootCount
        case splitParentMissing
        case splitParentCrossTab
        case splitParentNotEarlier
        case splitCycle
        case invalidSplitRatio
        case commandContainsLineBreak
    }

    public let code: Code
    public let projectID: UUID
    public let folderID: UUID?
    public let tabID: UUID?
    public let paneID: UUID?
    public let field: String

    public init(
        code: Code,
        projectID: UUID,
        folderID: UUID? = nil,
        tabID: UUID? = nil,
        paneID: UUID? = nil,
        field: String
    ) {
        self.code = code
        self.projectID = projectID
        self.folderID = folderID
        self.tabID = tabID
        self.paneID = paneID
        self.field = field
    }
}

public struct BessieProjectValidationError: Error, Equatable, Sendable {
    public let issues: [BessieProjectValidationIssue]
    public init(issues: [BessieProjectValidationIssue]) { self.issues = issues }
}

public enum BessieProjectMigration {
    public static func migrate(_ data: Data) throws -> BessieProject {
        let version = try BessieProjectCodec.schemaVersion(in: data)
        switch version {
        case 1:
            return try BessieProjectCodec.decodeVersionOne(data).migrated()
        case 2:
            return try BessieProjectCodec.decodeVersionTwo(data)
        default:
            throw BessieProjectSchemaError.unsupportedVersion(version)
        }
    }
}

public enum BessieProjectCodec {
    public static func decode(_ data: Data) throws -> BessieProject {
        try BessieProjectMigration.migrate(data)
    }

    public static func encode(_ project: BessieProject) throws -> Data {
        guard project.schemaVersion == BessieProjectSchema.currentVersion else {
            throw BessieProjectSchemaError.unsupportedVersion(project.schemaVersion)
        }
        return try encoder.encode(project)
    }

    static func schemaVersion(in data: Data) throws -> Int {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                throw BessieProjectSchemaError.invalidDocument("Expected a JSON object.")
            }
            guard let number = dictionary["schemaVersion"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == Double(number.intValue) else {
                throw BessieProjectSchemaError.missingVersion
            }
            return number.intValue
        } catch let error as BessieProjectSchemaError {
            throw error
        } catch {
            throw BessieProjectSchemaError.invalidDocument(error.localizedDescription)
        }
    }

    fileprivate static func decodeVersionOne(_ data: Data) throws -> BessieProjectVersionOne {
        do {
            try validateVersionOneDocument(data)
            return try decoder.decode(BessieProjectVersionOne.self, from: data)
        } catch let error as BessieProjectSchemaError {
            throw error
        } catch {
            throw BessieProjectSchemaError.invalidDocument(error.localizedDescription)
        }
    }

    fileprivate static func decodeVersionTwo(_ data: Data) throws -> BessieProject {
        do {
            try validateVersionTwoDocument(data)
            return try decoder.decode(BessieProject.self, from: data)
        } catch let error as BessieProjectSchemaError {
            throw error
        } catch {
            throw BessieProjectSchemaError.invalidDocument(error.localizedDescription)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let versionOneProjectKeys: Set<String> = [
        "schemaVersion", "id", "name", "projectDescription", "group", "workingDirectory",
        "tabs", "createdAt", "updatedAt", "archivedAt",
    ]
    private static let versionTwoProjectKeys: Set<String> = [
        "schemaVersion", "id", "name", "projectDescription", "group", "folders",
        "tabs", "createdAt", "updatedAt", "archivedAt",
    ]
    private static let folderKeys: Set<String> = ["id", "name", "path", "isPrimary"]
    private static let tabKeys: Set<String> = ["id", "name", "panes"]
    private static let versionOnePaneKeys: Set<String> = ["id", "label", "command", "placement"]
    private static let versionTwoPaneKeys: Set<String> = ["id", "label", "command", "folderID", "placement"]
    private static let rootPlacementKeys: Set<String> = ["type"]
    private static let splitPlacementKeys: Set<String> = ["type", "fromPaneID", "direction", "ratio"]

    private static func validateVersionOneDocument(_ data: Data) throws {
        guard let project = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BessieProjectSchemaError.invalidDocument("Expected a JSON object.")
        }
        try validateKeys(project, allowed: versionOneProjectKeys, context: "project")
        try validateTabs(in: project, paneKeys: versionOnePaneKeys)
    }

    private static func validateVersionTwoDocument(_ data: Data) throws {
        guard let project = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BessieProjectSchemaError.invalidDocument("Expected a JSON object.")
        }
        try validateKeys(project, allowed: versionTwoProjectKeys, context: "project")
        guard let folders = project["folders"] as? [[String: Any]] else {
            throw BessieProjectSchemaError.invalidDocument("Expected project folders.")
        }
        for folder in folders {
            try validateKeys(folder, allowed: folderKeys, context: "folder")
        }
        try validateTabs(in: project, paneKeys: versionTwoPaneKeys)
    }

    private static func validateTabs(in project: [String: Any], paneKeys: Set<String>) throws {
        guard let tabs = project["tabs"] as? [[String: Any]] else {
            throw BessieProjectSchemaError.invalidDocument("Expected project tabs.")
        }
        for tab in tabs {
            try validateKeys(tab, allowed: tabKeys, context: "tab")
            guard let panes = tab["panes"] as? [[String: Any]] else {
                throw BessieProjectSchemaError.invalidDocument("Expected tab panes.")
            }
            for pane in panes {
                try validateKeys(pane, allowed: paneKeys, context: "pane")
                guard let placement = pane["placement"] as? [String: Any],
                      let type = placement["type"] as? String else {
                    throw BessieProjectSchemaError.invalidDocument("Expected pane placement.")
                }
                switch type {
                case "root":
                    try validateKeys(placement, allowed: rootPlacementKeys, context: "root placement")
                case "split":
                    try validateKeys(placement, allowed: splitPlacementKeys, context: "split placement")
                default:
                    throw BessieProjectSchemaError.invalidDocument("Unknown pane placement type \(type).")
                }
            }
        }
    }

    private static func validateKeys(_ object: [String: Any], allowed: Set<String>, context: String) throws {
        let unknown = Set(object.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw BessieProjectSchemaError.invalidDocument(
                "Unknown \(context) field(s): \(unknown.joined(separator: ", "))."
            )
        }
    }
}

fileprivate struct BessieProjectVersionOne: Codable {
    let schemaVersion: Int
    let id: UUID
    var name: String
    var projectDescription: String
    var group: String?
    var workingDirectory: String
    var tabs: [BessieProjectTabVersionOne]
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    func migrated() -> BessieProject {
        BessieProject(
            id: id,
            name: name,
            projectDescription: projectDescription,
            group: group,
            folders: [.init(id: id, name: "Primary", path: workingDirectory, isPrimary: true)],
            tabs: tabs.map { $0.migrated() },
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: archivedAt
        )
    }
}

fileprivate struct BessieProjectTabVersionOne: Codable {
    let id: UUID
    var name: String
    var panes: [BessieProjectPaneVersionOne]

    func migrated() -> BessieProjectTab {
        .init(id: id, name: name, panes: panes.map { $0.migrated() })
    }
}

fileprivate struct BessieProjectPaneVersionOne: Codable {
    let id: UUID
    var label: String?
    var command: String?
    var placement: BessieProjectPanePlacement

    func migrated() -> BessieProjectPane {
        .init(id: id, label: label, command: command, folderID: nil, placement: placement)
    }
}

private extension String {
    var bessieTrimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
