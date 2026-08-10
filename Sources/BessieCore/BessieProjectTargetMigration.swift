import CryptoKit
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct BessieProjectTargetMigrationManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public struct FolderMapping: Codable, Equatable, Sendable {
        public let folderID: UUID
        public let sourcePath: String
        public let targetPath: String

        public init(folderID: UUID, sourcePath: String, targetPath: String) {
            self.folderID = folderID
            self.sourcePath = sourcePath
            self.targetPath = targetPath
        }
    }

    public struct ProjectMapping: Codable, Equatable, Sendable {
        public let projectID: UUID
        public let sourceSHA256: String
        public let folders: [FolderMapping]

        public init(projectID: UUID, sourceSHA256: String, folders: [FolderMapping]) {
            self.projectID = projectID
            self.sourceSHA256 = sourceSHA256
            self.folders = folders
        }
    }

    public let schemaVersion: Int
    public let operationID: UUID
    public let connectionsPath: String
    public let projectsPath: String
    public let backupPath: String
    public let journalPath: String
    public let connectionSourceSHA256: String
    public let sourceConnectionID: String
    public let targetConnectionID: String
    public let expectedProjectCount: Int
    public let approvedSourceRoots: [String]
    public let approvedTargetRoots: [String]
    public let projects: [ProjectMapping]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        operationID: UUID,
        connectionsPath: String,
        projectsPath: String,
        backupPath: String,
        journalPath: String,
        connectionSourceSHA256: String,
        sourceConnectionID: String,
        targetConnectionID: String,
        expectedProjectCount: Int,
        approvedSourceRoots: [String],
        approvedTargetRoots: [String],
        projects: [ProjectMapping]
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.connectionsPath = connectionsPath
        self.projectsPath = projectsPath
        self.backupPath = backupPath
        self.journalPath = journalPath
        self.connectionSourceSHA256 = connectionSourceSHA256
        self.sourceConnectionID = sourceConnectionID
        self.targetConnectionID = targetConnectionID
        self.expectedProjectCount = expectedProjectCount
        self.approvedSourceRoots = approvedSourceRoots
        self.approvedTargetRoots = approvedTargetRoots
        self.projects = projects
    }
}

public struct BessieMigrationFileMetadata: Codable, Equatable, Sendable {
    public let mode: UInt16
    public let ownerID: UInt32
    public let groupID: UInt32
    public let aclEntries: [String]
    public let extendedAttributes: [String: String]

    public init(
        mode: UInt16,
        ownerID: UInt32,
        groupID: UInt32,
        aclEntries: [String],
        extendedAttributes: [String: String]
    ) {
        self.mode = mode
        self.ownerID = ownerID
        self.groupID = groupID
        self.aclEntries = aclEntries
        self.extendedAttributes = extendedAttributes
    }
}

public struct BessieMigrationRemotePathFacts: Equatable, Sendable {
    public let requestedPath: String
    public let canonicalPath: String
    public let exists: Bool
    public let isDirectory: Bool
    public let isSymbolicLink: Bool

    public init(
        requestedPath: String,
        canonicalPath: String,
        exists: Bool,
        isDirectory: Bool,
        isSymbolicLink: Bool
    ) {
        self.requestedPath = requestedPath
        self.canonicalPath = canonicalPath
        self.exists = exists
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
    }
}

public struct BessieMigrationRemoteInspector: Sendable {
    private let inspectBody: @Sendable (String) throws -> BessieMigrationRemotePathFacts

    public init(inspect: @escaping @Sendable (String) throws -> BessieMigrationRemotePathFacts) {
        inspectBody = inspect
    }

    public func inspect(_ path: String) throws -> BessieMigrationRemotePathFacts {
        try inspectBody(path)
    }
}

public enum BessieMigrationBackupStep: Equatable, Sendable {
    case stagingDirectoryCreated
    case ownershipRecorded
    case connectionCopied
    case projectsCopied
}

public struct BessieProjectTargetMigrationJournal: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public enum Phase: String, Codable, Equatable, Sendable {
        case preflighted
        case applyingProjects
        case applyingConnections
        case applied
        case success
        case rollingBack
        case rolledBack
        case rollbackVerified
        case closingSSHMaster
        case readyForRelaunch

        public var isTerminal: Bool { self == .readyForRelaunch }
    }

    public enum TerminalOutcome: String, Codable, Equatable, Sendable {
        case migrated
        case rolledBack
    }

    public struct FileRecord: Codable, Equatable, Sendable {
        public let projectID: UUID?
        public let livePath: String
        public let backupPath: String
        public let sourceSHA256: String
        public let resultSHA256: String
        public let sourceMetadata: BessieMigrationFileMetadata
        public var completedResultSHA256: String?

        public init(
            projectID: UUID?,
            livePath: String,
            backupPath: String,
            sourceSHA256: String,
            resultSHA256: String,
            sourceMetadata: BessieMigrationFileMetadata,
            completedResultSHA256: String? = nil
        ) {
            self.projectID = projectID
            self.livePath = livePath
            self.backupPath = backupPath
            self.sourceSHA256 = sourceSHA256
            self.resultSHA256 = resultSHA256
            self.sourceMetadata = sourceMetadata
            self.completedResultSHA256 = completedResultSHA256
        }
    }

    public let schemaVersion: Int
    public let operationID: UUID
    public let manifestPath: String
    public let manifestSHA256: String
    public let createdAt: Date
    public var updatedAt: Date
    public var phase: Phase
    public let sshControlPath: String
    public let sshHost: String
    public var sshMasterPID: Int32
    public var sshOwnerToken: UUID
    public let backupTreeSHA256: String
    public let projectDirectoryMetadata: BessieMigrationFileMetadata
    public let connectionDirectoryMetadata: BessieMigrationFileMetadata
    public var projects: [FileRecord]
    public var connection: FileRecord
    public var sshMasterClosedAt: Date?
    public var auditMessage: String?
    public var terminalOutcome: TerminalOutcome?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        operationID: UUID,
        manifestPath: String,
        manifestSHA256: String,
        createdAt: Date,
        updatedAt: Date,
        phase: Phase,
        sshControlPath: String,
        sshHost: String,
        sshMasterPID: Int32,
        sshOwnerToken: UUID,
        backupTreeSHA256: String,
        projectDirectoryMetadata: BessieMigrationFileMetadata,
        connectionDirectoryMetadata: BessieMigrationFileMetadata,
        projects: [FileRecord],
        connection: FileRecord,
        sshMasterClosedAt: Date? = nil,
        auditMessage: String? = nil,
        terminalOutcome: TerminalOutcome? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.manifestPath = manifestPath
        self.manifestSHA256 = manifestSHA256
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phase = phase
        self.sshControlPath = sshControlPath
        self.sshHost = sshHost
        self.sshMasterPID = sshMasterPID
        self.sshOwnerToken = sshOwnerToken
        self.backupTreeSHA256 = backupTreeSHA256
        self.projectDirectoryMetadata = projectDirectoryMetadata
        self.connectionDirectoryMetadata = connectionDirectoryMetadata
        self.projects = projects
        self.connection = connection
        self.sshMasterClosedAt = sshMasterClosedAt
        self.auditMessage = auditMessage
        self.terminalOutcome = terminalOutcome
    }
}

public enum BessieProjectTargetMigrationError: LocalizedError, Equatable, Sendable {
    case invalidManifest(String)
    case activeJournal(String)
    case invalidJournal(String)
    case sourceDrift(String)
    case unsafeRemotePath(String)
    case backupFailed(String)
    case auditFailed(String)
    case wrongCommand(String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let reason): "Migration manifest is invalid. \(reason)"
        case .activeJournal(let reason): "A migration journal already exists. \(reason)"
        case .invalidJournal(let reason): "Migration journal is invalid. \(reason)"
        case .sourceDrift(let reason): "Migration source changed. \(reason)"
        case .unsafeRemotePath(let reason): "Remote target validation failed. \(reason)"
        case .backupFailed(let reason): "Migration backup failed. \(reason)"
        case .auditFailed(let reason): "Migration audit failed. \(reason)"
        case .wrongCommand(let reason): reason
        }
    }
}

public struct BessieProjectTargetMigration: Sendable {
    private struct BackupMarker: Codable {
        let schemaVersion: Int
        let operationID: UUID
        let manifestSHA256: String
    }

    private struct BackupTreeRecord: Codable, Equatable {
        let isDirectory: Bool
        let hash: String?
        let metadata: BessieMigrationFileMetadata
    }

    private struct BackupTreeDigestEntry: Codable {
        let path: String
        let record: BackupTreeRecord
    }

    private struct DirectoryIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private let remoteInspector: BessieMigrationRemoteInspector
    private let now: @Sendable () -> Date
    private let afterBackupStep: @Sendable (BessieMigrationBackupStep) throws -> Void
    private let afterJournalWrite: @Sendable () throws -> Void
    private let afterProjectWrite: @Sendable (Int) throws -> Void
    private let afterConnectionWrite: @Sendable () throws -> Void

    public init(
        remoteInspector: BessieMigrationRemoteInspector,
        now: @escaping @Sendable () -> Date = Date.init,
        afterBackupStep: @escaping @Sendable (BessieMigrationBackupStep) throws -> Void = { _ in },
        afterJournalWrite: @escaping @Sendable () throws -> Void = {},
        afterProjectWrite: @escaping @Sendable (Int) throws -> Void = { _ in },
        afterConnectionWrite: @escaping @Sendable () throws -> Void = {}
    ) {
        self.remoteInspector = remoteInspector
        self.now = now
        self.afterBackupStep = afterBackupStep
        self.afterJournalWrite = afterJournalWrite
        self.afterProjectWrite = afterProjectWrite
        self.afterConnectionWrite = afterConnectionWrite
    }

    public static func decodeManifest(at url: URL) throws -> (BessieProjectTargetMigrationManifest, Data) {
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(BessieProjectTargetMigrationManifest.self, from: data)
        return (manifest, data)
    }

    public static func loadJournal(for manifest: BessieProjectTargetMigrationManifest) throws -> BessieProjectTargetMigrationJournal {
        let data = try Data(contentsOf: URL(fileURLWithPath: manifest.journalPath))
        return try migrationDecoder.decode(BessieProjectTargetMigrationJournal.self, from: data)
    }

    public static func migrationSSHControlPath(operationID: UUID) -> String {
        let compactID = operationID.uuidString.replacingOccurrences(of: "-", with: "")
        return "/private/tmp/.bessie-migration-\(compactID)-m/control.sock"
    }

    /// Validates the complete local recovery envelope before an operator uses journal-owned paths or SSH identity.
    public func validateJournal(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        try validatedJournal(manifest: manifest, manifestData: manifestData)
    }

    /// Validates every manifest-owned local path before the operator creates locks,
    /// migration markers, backups, journals, or SSH control artifacts.
    public func validateLocalEnvelope(
        manifest: BessieProjectTargetMigrationManifest
    ) throws {
        try validateManifestShape(manifest)
        let connectionURL = URL(fileURLWithPath: manifest.connectionsPath)
        let projectsURL = URL(fileURLWithPath: manifest.projectsPath, isDirectory: true)
        let backupURL = URL(fileURLWithPath: manifest.backupPath, isDirectory: true)
        let journalURL = URL(fileURLWithPath: manifest.journalPath)
        try requireRegularFile(connectionURL, label: "connection configuration")
        try requireDirectory(projectsURL, label: "Project catalog")
        try requireCanonicalExistingPath(connectionURL, label: "connection configuration")
        try requireCanonicalExistingPath(projectsURL, label: "Project catalog")
        try Self.requireOwnedSafeDirectory(
            connectionURL.deletingLastPathComponent(),
            label: "connection configuration parent"
        )
        try Self.requireOwnedSafeDirectory(projectsURL, label: "Project catalog")
        try requireCanonicalExistingPath(backupURL.deletingLastPathComponent(), label: "backup parent")
        try requireCanonicalExistingPath(journalURL.deletingLastPathComponent(), label: "journal parent")
        try Self.requireOwnedSafeDirectory(backupURL.deletingLastPathComponent(), label: "backup parent")
        try Self.requireOwnedSafeDirectory(journalURL.deletingLastPathComponent(), label: "journal parent")
        guard !Self.contains(parent: projectsURL, child: backupURL),
              !Self.contains(parent: projectsURL, child: journalURL),
              journalURL.standardizedFileURL != connectionURL.standardizedFileURL else {
            throw BessieProjectTargetMigrationError.invalidManifest(
                "Backup and journal paths must be outside the live Project catalog and cannot replace the connection file."
            )
        }
    }

    public func preflight(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data,
        manifestPath: String,
        sshControlPath: String,
        sshHost: String,
        sshMasterPID: Int32,
        sshOwnerToken: UUID
    ) throws -> BessieProjectTargetMigrationJournal {
        try validateLocalEnvelope(manifest: manifest)
        let journalURL = URL(fileURLWithPath: manifest.journalPath)
        if FileManager.default.fileExists(atPath: journalURL.path) {
            let existing = try? Self.loadJournal(for: manifest)
            let status = existing.map { "Its phase is \($0.phase.rawValue)." } ?? "It cannot be decoded."
            throw BessieProjectTargetMigrationError.activeJournal(status + " Use resume, rollback, or a new operation ID.")
        }

        let connectionURL = URL(fileURLWithPath: manifest.connectionsPath)
        let projectsURL = URL(fileURLWithPath: manifest.projectsPath, isDirectory: true)
        let backupURL = URL(fileURLWithPath: manifest.backupPath, isDirectory: true)

        let connectionData = try Data(contentsOf: connectionURL)
        guard Self.sha256(connectionData) == manifest.connectionSourceSHA256.lowercased() else {
            throw BessieProjectTargetMigrationError.sourceDrift("Connection configuration hash does not match the manifest.")
        }
        let connectionState = try JSONDecoder().decode(BessieConnectionState.self, from: connectionData)
        guard connectionState.connections.contains(where: { $0.id == manifest.sourceConnectionID }) else {
            throw BessieProjectTargetMigrationError.invalidManifest("Source connection \(manifest.sourceConnectionID) is not configured.")
        }
        guard connectionState.connections.first(where: { $0.id == manifest.sourceConnectionID })?.enabled == true else {
            throw BessieProjectTargetMigrationError.invalidManifest("Source connection \(manifest.sourceConnectionID) must still be enabled before migration.")
        }
        guard let targetConnection = connectionState.connections.first(where: { $0.id == manifest.targetConnectionID }),
              targetConnection.kind == .ssh,
              targetConnection.enabled,
              targetConnection.sshHost == sshHost,
              (try? targetConnection.validated()) != nil else {
            throw BessieProjectTargetMigrationError.invalidManifest("Target connection \(manifest.targetConnectionID) must be a configured SSH herd.")
        }

        let canonicalTargetRoots = try manifest.approvedTargetRoots.map { root -> String in
            let facts = try remoteInspector.inspect(root)
            guard facts.exists, facts.isDirectory, !facts.isSymbolicLink,
                  facts.canonicalPath == Self.standardizedAbsolutePath(root) else {
                throw BessieProjectTargetMigrationError.unsafeRemotePath("Approved root is not a canonical, non-symlink directory: \(root)")
            }
            return facts.canonicalPath
        }

        let projectURLs = try FileManager.default.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard projectURLs.count == manifest.expectedProjectCount else {
            throw BessieProjectTargetMigrationError.invalidManifest(
                "Expected exactly \(manifest.expectedProjectCount) Project files, found \(projectURLs.count)."
            )
        }
        let mappingByID = Dictionary(uniqueKeysWithValues: manifest.projects.map { ($0.projectID, $0) })
        guard mappingByID.count == manifest.projects.count,
              manifest.projects.count == manifest.expectedProjectCount else {
            throw BessieProjectTargetMigrationError.invalidManifest("Project mappings must contain exactly one entry per expected Project UUID.")
        }

        var preparedProjects: [(mapping: BessieProjectTargetMigrationManifest.ProjectMapping, url: URL, source: Data, result: Data, metadata: BessieMigrationFileMetadata)] = []
        var seenProjectIDs: Set<UUID> = []
        for projectURL in projectURLs {
            try requireRegularFile(projectURL, label: "Project file")
            let sourceData = try Data(contentsOf: projectURL)
            let schema = try Self.schemaVersion(sourceData)
            guard schema == BessieProjectSchema.currentVersion else {
                throw BessieProjectTargetMigrationError.invalidManifest("\(projectURL.lastPathComponent) is schema v\(schema), not schema v\(BessieProjectSchema.currentVersion).")
            }
            let project = try BessieProjectCodec.decode(sourceData)
            guard seenProjectIDs.insert(project.id).inserted else {
                throw BessieProjectTargetMigrationError.invalidManifest("Duplicate embedded Project UUID \(project.id.uuidString).")
            }
            guard projectURL.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(project.id.uuidString) == .orderedSame else {
                throw BessieProjectTargetMigrationError.invalidManifest("Project filename does not match embedded UUID: \(projectURL.lastPathComponent).")
            }
            guard let mapping = mappingByID[project.id] else {
                throw BessieProjectTargetMigrationError.invalidManifest("No manifest entry exists for Project \(project.id.uuidString).")
            }
            guard Self.sha256(sourceData) == mapping.sourceSHA256.lowercased() else {
                throw BessieProjectTargetMigrationError.sourceDrift("Project \(project.id.uuidString) hash does not match the manifest.")
            }
            let result = try preparedResult(
                project: project,
                mapping: mapping,
                manifest: manifest,
                canonicalTargetRoots: canonicalTargetRoots,
                validateRemote: true
            )
            preparedProjects.append((mapping, projectURL, sourceData, result, try Self.metadata(at: projectURL)))
        }
        guard seenProjectIDs == Set(mappingByID.keys) else {
            throw BessieProjectTargetMigrationError.invalidManifest("Manifest and Project catalog UUID sets differ.")
        }

        let connectionResult = try preparedConnectionResult(connectionData, manifest: manifest)
        let projectDirectoryMetadata = try Self.metadata(at: projectsURL)
        let connectionDirectoryMetadata = try Self.metadata(at: connectionURL.deletingLastPathComponent())
        let connectionMetadata = try Self.metadata(at: connectionURL)
        try prepareOrRecoverBackup(
            at: backupURL,
            manifest: manifest,
            manifestData: manifestData,
            connectionURL: connectionURL,
            projectsURL: projectsURL
        )
        let connectionBackupURL = backupURL.appendingPathComponent("connections.json")
        let projectBackupURL = backupURL.appendingPathComponent("Projects", isDirectory: true)
        guard Self.sha256(try Data(contentsOf: connectionBackupURL)) == Self.sha256(connectionData),
              try Self.metadata(at: connectionBackupURL) == connectionMetadata,
              try Self.metadata(at: projectBackupURL) == projectDirectoryMetadata else {
            throw BessieProjectTargetMigrationError.backupFailed("Published connection or Project-directory backup differs from its source.")
        }

        var records: [BessieProjectTargetMigrationJournal.FileRecord] = []
        for prepared in preparedProjects {
            let destination = projectBackupURL.appendingPathComponent(prepared.url.lastPathComponent)
            guard Self.sha256(try Data(contentsOf: destination)) == Self.sha256(prepared.source),
                  try Self.metadata(at: destination) == prepared.metadata else {
                throw BessieProjectTargetMigrationError.backupFailed("Backup bytes or metadata differ for \(prepared.url.lastPathComponent).")
            }
            records.append(.init(
                projectID: prepared.mapping.projectID,
                livePath: prepared.url.path,
                backupPath: destination.path,
                sourceSHA256: Self.sha256(prepared.source),
                resultSHA256: Self.sha256(prepared.result),
                sourceMetadata: prepared.metadata
            ))
        }

        let timestamp = now()
        let backupTreeSHA256 = try Self.backupTreeSHA256(backupURL)
        let journal = BessieProjectTargetMigrationJournal(
            operationID: manifest.operationID,
            manifestPath: manifestPath,
            manifestSHA256: Self.sha256(manifestData),
            createdAt: timestamp,
            updatedAt: timestamp,
            phase: .preflighted,
            sshControlPath: sshControlPath,
            sshHost: sshHost,
            sshMasterPID: sshMasterPID,
            sshOwnerToken: sshOwnerToken,
            backupTreeSHA256: backupTreeSHA256,
            projectDirectoryMetadata: projectDirectoryMetadata,
            connectionDirectoryMetadata: connectionDirectoryMetadata,
            projects: records,
            connection: .init(
                projectID: nil,
                livePath: connectionURL.path,
                backupPath: connectionBackupURL.path,
                sourceSHA256: Self.sha256(connectionData),
                resultSHA256: Self.sha256(connectionResult),
                sourceMetadata: connectionMetadata
            )
        )
        try saveJournal(journal, to: journalURL)
        return journal
    }

    public func apply(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data,
        resume: Bool
    ) throws -> BessieProjectTargetMigrationJournal {
        var journal = try validatedJournal(manifest: manifest, manifestData: manifestData)
        let canonicalTargetRoots = try validateAllRemoteTargets(manifest)
        try validateTargetConnectionBeforeApply(manifest: manifest, journal: journal)
        if resume {
            guard [.applyingProjects, .applyingConnections].contains(journal.phase) else {
                throw BessieProjectTargetMigrationError.wrongCommand("Resume requires an interrupted applyingProjects or applyingConnections journal; current phase is \(journal.phase.rawValue).")
            }
        } else {
            guard journal.phase == .preflighted else {
                throw BessieProjectTargetMigrationError.wrongCommand("Apply requires a preflighted journal; current phase is \(journal.phase.rawValue). Use resume or rollback.")
            }
            journal.phase = .applyingProjects
            try updateJournal(&journal, manifest: manifest)
        }

        let mappingByID = Dictionary(uniqueKeysWithValues: manifest.projects.map { ($0.projectID, $0) })
        for index in journal.projects.indices {
            guard let projectID = journal.projects[index].projectID,
                  let mapping = mappingByID[projectID] else {
                throw BessieProjectTargetMigrationError.invalidJournal("Missing Project mapping for journal entry \(index).")
            }
            let record = journal.projects[index]
            let liveURL = URL(fileURLWithPath: record.livePath)
            let currentData = try Data(contentsOf: liveURL)
            let currentHash = Self.sha256(currentData)
            if let completed = record.completedResultSHA256 {
                guard completed == record.resultSHA256, currentHash == completed else {
                    throw BessieProjectTargetMigrationError.sourceDrift("Completed Project \(projectID.uuidString) no longer matches its journal result hash.")
                }
                continue
            }

            if currentHash == record.resultSHA256 {
                // The atomic replacement completed before the prior process could persist its journal entry.
                journal.projects[index].completedResultSHA256 = currentHash
                try updateJournal(&journal, manifest: manifest)
                continue
            }
            guard currentHash == record.sourceSHA256 else {
                throw BessieProjectTargetMigrationError.sourceDrift("Project \(projectID.uuidString) matches neither its source nor prepared result hash.")
            }
            let sourceProject = try BessieProjectCodec.decode(currentData)
            let resultData = try preparedResult(
                project: sourceProject,
                mapping: mapping,
                manifest: manifest,
                canonicalTargetRoots: canonicalTargetRoots,
                validateRemote: true
            )
            guard Self.sha256(resultData) == record.resultSHA256 else {
                throw BessieProjectTargetMigrationError.invalidJournal("Prepared result changed for Project \(projectID.uuidString).")
            }
            try Self.replaceDurably(resultData, at: liveURL, preservingFrom: URL(fileURLWithPath: record.backupPath))
            try afterProjectWrite(index)
            guard Self.sha256(try Data(contentsOf: liveURL)) == record.resultSHA256 else {
                throw BessieProjectTargetMigrationError.auditFailed("Installed Project \(projectID.uuidString) did not retain its prepared hash.")
            }
            journal.projects[index].completedResultSHA256 = record.resultSHA256
            try updateJournal(&journal, manifest: manifest)
        }

        try verifyProjectResultsBeforeConnection(
            manifest: manifest,
            journal: journal,
            canonicalTargetRoots: try validateAllRemoteTargets(manifest)
        )
        journal.phase = .applyingConnections
        try updateJournal(&journal, manifest: manifest)
        let connectionURL = URL(fileURLWithPath: journal.connection.livePath)
        let connectionData = try Data(contentsOf: connectionURL)
        let connectionHash = Self.sha256(connectionData)
        if let completed = journal.connection.completedResultSHA256 {
            guard completed == journal.connection.resultSHA256, connectionHash == completed else {
                throw BessieProjectTargetMigrationError.sourceDrift("Completed connection configuration no longer matches its result hash.")
            }
        } else if connectionHash == journal.connection.resultSHA256 {
            journal.connection.completedResultSHA256 = connectionHash
            try updateJournal(&journal, manifest: manifest)
        } else {
            guard connectionHash == journal.connection.sourceSHA256 else {
                throw BessieProjectTargetMigrationError.sourceDrift("Connection configuration matches neither its source nor prepared result hash.")
            }
            let resultData = try preparedConnectionResult(connectionData, manifest: manifest)
            guard Self.sha256(resultData) == journal.connection.resultSHA256 else {
                throw BessieProjectTargetMigrationError.invalidJournal("Prepared connection result changed after preflight.")
            }
            try Self.replaceDurably(
                resultData,
                at: connectionURL,
                preservingFrom: URL(fileURLWithPath: journal.connection.backupPath)
            )
            try afterConnectionWrite()
            guard Self.sha256(try Data(contentsOf: connectionURL)) == journal.connection.resultSHA256 else {
                throw BessieProjectTargetMigrationError.auditFailed("Installed connection configuration did not retain its prepared hash.")
            }
            journal.connection.completedResultSHA256 = journal.connection.resultSHA256
            try updateJournal(&journal, manifest: manifest)
        }

        journal.phase = .applied
        try updateJournal(&journal, manifest: manifest)
        return journal
    }

    public func rollback(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        var journal = try validatedJournal(manifest: manifest, manifestData: manifestData)
        guard journal.phase != .rollbackVerified,
              journal.phase != .rolledBack,
              !(journal.phase == .readyForRelaunch && journal.terminalOutcome == .rolledBack) else {
            throw BessieProjectTargetMigrationError.wrongCommand("Rollback is already complete; current phase is \(journal.phase.rawValue).")
        }
        journal.auditMessage = nil
        journal.terminalOutcome = nil
        journal.sshMasterClosedAt = nil
        journal.phase = .rollingBack
        try updateJournal(&journal, manifest: manifest)

        // Restore connection first so a partially applied remote-only state never points local recipes at a disabled herd.
        try restore(record: journal.connection)
        for record in journal.projects.reversed() {
            try restore(record: record)
        }
        journal.phase = .rolledBack
        journal.projects.indices.forEach { journal.projects[$0].completedResultSHA256 = nil }
        journal.connection.completedResultSHA256 = nil
        try updateJournal(&journal, manifest: manifest)
        return journal
    }

    public func recordSSHMasterOwnership(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data,
        sshMasterPID: Int32,
        sshOwnerToken: UUID
    ) throws -> BessieProjectTargetMigrationJournal {
        var journal = try validatedJournal(manifest: manifest, manifestData: manifestData)
        guard [.preflighted, .applyingProjects, .applyingConnections, .applied, .success].contains(journal.phase),
              sshMasterPID > 0 else {
            throw BessieProjectTargetMigrationError.wrongCommand(
                "SSH ownership can only rotate before the audited master-close phase."
            )
        }
        journal.sshMasterPID = sshMasterPID
        journal.sshOwnerToken = sshOwnerToken
        journal.sshMasterClosedAt = nil
        try updateJournal(&journal, manifest: manifest)
        return journal
    }

    public func audit(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        var journal = try validatedJournal(manifest: manifest, manifestData: manifestData)
        switch journal.phase {
        case .applied, .success:
            try auditApplied(manifest: manifest, journal: journal)
            journal.phase = .success
            journal.auditMessage = "Verified \(journal.projects.count) migrated schema-v\(BessieProjectSchema.currentVersion) Projects and remote-only connection state."
            journal.terminalOutcome = .migrated
        case .rolledBack, .rollbackVerified:
            try auditRolledBack(journal)
            journal.phase = .rollbackVerified
            journal.auditMessage = "Verified full byte-for-byte and metadata rollback for connections and \(journal.projects.count) Projects."
            journal.terminalOutcome = .rolledBack
        default:
            throw BessieProjectTargetMigrationError.wrongCommand("Audit requires applied or rolledBack state; current phase is \(journal.phase.rawValue).")
        }
        try updateJournal(&journal, manifest: manifest)
        return journal
    }

    public func recordSSHMasterClosed(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        var journal = try validatedJournal(manifest: manifest, manifestData: manifestData)
        guard journal.phase == .closingSSHMaster,
              journal.terminalOutcome != nil,
              journal.auditMessage != nil else {
            throw BessieProjectTargetMigrationError.wrongCommand("SSH master can only be marked closed after durable closing state.")
        }
        journal.sshMasterClosedAt = now()
        journal.phase = .readyForRelaunch
        try updateJournal(&journal, manifest: manifest)
        return journal
    }

    public func recordSSHMasterClosing(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        var journal = try validatedJournal(manifest: manifest, manifestData: manifestData)
        guard journal.phase == .success || journal.phase == .rollbackVerified,
              journal.terminalOutcome != nil,
              journal.auditMessage != nil else {
            throw BessieProjectTargetMigrationError.wrongCommand("SSH close can only begin after terminal audit success or verified rollback.")
        }
        journal.phase = .closingSSHMaster
        try updateJournal(&journal, manifest: manifest)
        return journal
    }

    public func verifyReadyForRelaunch(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        let journal = try validatedJournal(manifest: manifest, manifestData: manifestData)
        guard journal.phase == .readyForRelaunch,
              journal.sshMasterClosedAt != nil,
              journal.auditMessage != nil,
              let outcome = journal.terminalOutcome else {
            throw BessieProjectTargetMigrationError.auditFailed("Journal has not reached audited, SSH-closed readyForRelaunch state.")
        }
        switch outcome {
        case .migrated:
            try auditApplied(manifest: manifest, journal: journal)
        case .rolledBack:
            try auditRolledBack(journal)
        }
        return journal
    }

    private func auditApplied(
        manifest: BessieProjectTargetMigrationManifest,
        journal: BessieProjectTargetMigrationJournal
    ) throws {
        guard journal.projects.count == manifest.expectedProjectCount,
              journal.projects.allSatisfy({ $0.completedResultSHA256 == $0.resultSHA256 }) else {
            throw BessieProjectTargetMigrationError.auditFailed("Not every expected Project has a completed result hash.")
        }
        let canonicalRoots = try manifest.approvedTargetRoots.map { root -> String in
            let facts = try remoteInspector.inspect(root)
            guard facts.exists, facts.isDirectory, !facts.isSymbolicLink else {
                throw BessieProjectTargetMigrationError.auditFailed("Approved remote root is no longer a usable directory: \(root)")
            }
            return facts.canonicalPath
        }
        let mappingByID = Dictionary(uniqueKeysWithValues: manifest.projects.map { ($0.projectID, $0) })
        let projectsDirectory = URL(fileURLWithPath: manifest.projectsPath, isDirectory: true)
        let liveProjectURLs = try FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        guard liveProjectURLs.count == manifest.expectedProjectCount,
              Set(liveProjectURLs.map(\.standardizedFileURL)) == Set(journal.projects.map { URL(fileURLWithPath: $0.livePath).standardizedFileURL }) else {
            throw BessieProjectTargetMigrationError.auditFailed("Live Project catalog file set no longer matches the exact preflight inventory.")
        }
        for record in journal.projects {
            let liveURL = URL(fileURLWithPath: record.livePath)
            guard Self.sha256(try Data(contentsOf: liveURL)) == record.resultSHA256,
                  try Self.metadata(at: liveURL) == record.sourceMetadata,
                  let projectID = record.projectID,
                  let mapping = mappingByID[projectID] else {
                throw BessieProjectTargetMigrationError.auditFailed("A migrated Project hash, metadata record, or manifest entry is missing.")
            }
            let project = try BessieProjectCodec.decode(Data(contentsOf: liveURL))
            _ = try preparedResult(
                project: project,
                mapping: mapping,
                manifest: manifest,
                canonicalTargetRoots: canonicalRoots,
                validateRemote: true,
                projectIsAlreadyMigrated: true
            )
            try verifyBackup(record)
        }
        let liveConnectionURL = URL(fileURLWithPath: journal.connection.livePath)
        guard Self.sha256(try Data(contentsOf: liveConnectionURL)) == journal.connection.resultSHA256,
              try Self.metadata(at: liveConnectionURL) == journal.connection.sourceMetadata else {
            throw BessieProjectTargetMigrationError.auditFailed("Connection configuration result hash or metadata does not match.")
        }
        let state = try JSONDecoder().decode(
            BessieConnectionState.self,
            from: Data(contentsOf: URL(fileURLWithPath: journal.connection.livePath))
        )
        guard state.selectedConnectionID == manifest.targetConnectionID,
              state.defaultProjectConnectionID == manifest.targetConnectionID,
              state.connections.first(where: { $0.id == manifest.sourceConnectionID })?.enabled == false,
              let target = state.connections.first(where: { $0.id == manifest.targetConnectionID }),
              target.enabled,
              target.connectAtLaunch else {
            throw BessieProjectTargetMigrationError.auditFailed("Connection state is not disabled-source/enabled-selected-default-startup-target.")
        }
        try verifyBackup(journal.connection)
        try verifyDirectoryMetadata(journal)
    }

    private func validateAllRemoteTargets(_ manifest: BessieProjectTargetMigrationManifest) throws -> [String] {
        let canonicalRoots = try manifest.approvedTargetRoots.map { root -> String in
            let expected = Self.standardizedAbsolutePath(root)
            let facts = try remoteInspector.inspect(expected)
            guard facts.exists, facts.isDirectory, !facts.isSymbolicLink, facts.canonicalPath == expected else {
                throw BessieProjectTargetMigrationError.unsafeRemotePath("Approved root is no longer a canonical, non-symlink directory: \(root)")
            }
            return facts.canonicalPath
        }
        for mapping in manifest.projects {
            for folder in mapping.folders {
                let target = Self.standardizedAbsolutePath(folder.targetPath)
                guard canonicalRoots.contains(where: { Self.containsPath(parent: $0, child: target) }) else {
                    throw BessieProjectTargetMigrationError.unsafeRemotePath("Target path is outside every approved root: \(target)")
                }
                let facts = try remoteInspector.inspect(target)
                guard facts.exists, facts.isDirectory, !facts.isSymbolicLink, facts.canonicalPath == target else {
                    throw BessieProjectTargetMigrationError.unsafeRemotePath("Target is no longer an existing canonical, non-symlink directory: \(target)")
                }
            }
        }
        return canonicalRoots
    }

    private func validateTargetConnectionBeforeApply(
        manifest: BessieProjectTargetMigrationManifest,
        journal: BessieProjectTargetMigrationJournal
    ) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: manifest.connectionsPath))
        let hash = Self.sha256(data)
        guard hash == journal.connection.sourceSHA256 || hash == journal.connection.resultSHA256 else {
            throw BessieProjectTargetMigrationError.sourceDrift("Connection configuration changed after preflight.")
        }
        let state = try JSONDecoder().decode(BessieConnectionState.self, from: data)
        guard let target = state.connections.first(where: { $0.id == manifest.targetConnectionID }),
              target.enabled,
              target.sshHost == journal.sshHost,
              (try? target.validated()) != nil else {
            throw BessieProjectTargetMigrationError.sourceDrift("The migration target herd is disabled, invalid, missing, or has a different SSH host.")
        }
        if journal.phase == .preflighted || journal.phase == .applyingProjects {
            guard hash == journal.connection.sourceSHA256 else {
                throw BessieProjectTargetMigrationError.sourceDrift(
                    "Connection result appeared before every Project completed and crossed the connection barrier."
                )
            }
        }
        if hash == journal.connection.sourceSHA256 {
            guard state.connections.first(where: { $0.id == manifest.sourceConnectionID })?.enabled == true else {
                throw BessieProjectTargetMigrationError.sourceDrift("The source herd was disabled before every Project result verified.")
            }
        }
    }

    private func verifyProjectResultsBeforeConnection(
        manifest: BessieProjectTargetMigrationManifest,
        journal: BessieProjectTargetMigrationJournal,
        canonicalTargetRoots: [String]
    ) throws {
        let liveURLs = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: manifest.projectsPath, isDirectory: true),
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        guard liveURLs.count == manifest.expectedProjectCount,
              Set(liveURLs.map(\.standardizedFileURL)) == Set(journal.projects.map { URL(fileURLWithPath: $0.livePath).standardizedFileURL }),
              journal.projects.allSatisfy({ $0.completedResultSHA256 == $0.resultSHA256 }) else {
            throw BessieProjectTargetMigrationError.auditFailed("Exact Project inventory and completed result hashes must verify before connection state changes.")
        }
        let mappingByID = Dictionary(uniqueKeysWithValues: manifest.projects.map { ($0.projectID, $0) })
        for record in journal.projects {
            guard let projectID = record.projectID,
                  let mapping = mappingByID[projectID] else {
                throw BessieProjectTargetMigrationError.invalidJournal("A pre-connection Project mapping is missing.")
            }
            let liveURL = URL(fileURLWithPath: record.livePath)
            let data = try Data(contentsOf: liveURL)
            guard Self.sha256(data) == record.resultSHA256,
                  try Self.metadata(at: liveURL) == record.sourceMetadata else {
                throw BessieProjectTargetMigrationError.auditFailed("Project \(projectID.uuidString) result bytes or metadata changed before the connection barrier.")
            }
            let project = try BessieProjectCodec.decode(data)
            let encoded = try preparedResult(
                project: project,
                mapping: mapping,
                manifest: manifest,
                canonicalTargetRoots: canonicalTargetRoots,
                validateRemote: true,
                projectIsAlreadyMigrated: true
            )
            guard Self.sha256(encoded) == record.resultSHA256 else {
                throw BessieProjectTargetMigrationError.auditFailed("Project \(projectID.uuidString) no longer matches its prepared target result.")
            }
        }
    }

    private func auditRolledBack(_ journal: BessieProjectTargetMigrationJournal) throws {
        guard let firstProject = journal.projects.first else {
            throw BessieProjectTargetMigrationError.auditFailed("Rollback journal has no Project inventory.")
        }
        let projectsDirectory = URL(fileURLWithPath: firstProject.livePath).deletingLastPathComponent()
        let liveProjectURLs = try FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        guard liveProjectURLs.count == journal.projects.count,
              Set(liveProjectURLs.map(\.standardizedFileURL))
                == Set(journal.projects.map { URL(fileURLWithPath: $0.livePath).standardizedFileURL }) else {
            throw BessieProjectTargetMigrationError.auditFailed(
                "Rollback Project inventory differs from the exact preflight catalog."
            )
        }
        for record in journal.projects + [journal.connection] {
            let liveURL = URL(fileURLWithPath: record.livePath)
            guard Self.sha256(try Data(contentsOf: liveURL)) == record.sourceSHA256,
                  try Self.metadata(at: liveURL) == record.sourceMetadata else {
                throw BessieProjectTargetMigrationError.auditFailed("Rollback did not restore source bytes and metadata for \(liveURL.lastPathComponent).")
            }
            try verifyBackup(record)
        }
        try verifyDirectoryMetadata(journal)
    }

    private func preparedResult(
        project sourceProject: BessieProject,
        mapping: BessieProjectTargetMigrationManifest.ProjectMapping,
        manifest: BessieProjectTargetMigrationManifest,
        canonicalTargetRoots: [String],
        validateRemote: Bool,
        projectIsAlreadyMigrated: Bool = false
    ) throws -> Data {
        guard sourceProject.id == mapping.projectID else {
            throw BessieProjectTargetMigrationError.invalidManifest("Project mapping UUID does not match embedded Project UUID.")
        }
        let expectedSourceConnection = projectIsAlreadyMigrated ? manifest.targetConnectionID : manifest.sourceConnectionID
        guard sourceProject.targetConnectionID == expectedSourceConnection else {
            throw BessieProjectTargetMigrationError.sourceDrift(
                "Project \(sourceProject.id.uuidString) targets \(sourceProject.targetConnectionID), expected \(expectedSourceConnection)."
            )
        }
        let folderMappings = Dictionary(uniqueKeysWithValues: mapping.folders.map { ($0.folderID, $0) })
        guard folderMappings.count == mapping.folders.count,
              folderMappings.count == sourceProject.folders.count,
              Set(folderMappings.keys) == Set(sourceProject.folders.map(\.id)) else {
            throw BessieProjectTargetMigrationError.invalidManifest("Project \(sourceProject.id.uuidString) must map every folder UUID exactly once.")
        }

        var result = sourceProject
        result.targetConnectionID = manifest.targetConnectionID
        for index in result.folders.indices {
            let sourceFolder = sourceProject.folders[index]
            guard let folderMapping = folderMappings[sourceFolder.id] else {
                throw BessieProjectTargetMigrationError.invalidManifest("Missing folder mapping \(sourceFolder.id.uuidString).")
            }
            let expectedSourcePath = projectIsAlreadyMigrated ? folderMapping.targetPath : folderMapping.sourcePath
            guard sourceFolder.path == expectedSourcePath else {
                throw BessieProjectTargetMigrationError.sourceDrift("Folder \(sourceFolder.id.uuidString) path does not match its explicit manifest source.")
            }
            let standardizedSource = Self.standardizedAbsolutePath(folderMapping.sourcePath)
            guard manifest.approvedSourceRoots.contains(where: {
                Self.containsPath(parent: Self.standardizedAbsolutePath($0), child: standardizedSource)
            }) else {
                throw BessieProjectTargetMigrationError.invalidManifest("Source path is outside every approved source root: \(folderMapping.sourcePath)")
            }
            let targetPath = Self.standardizedAbsolutePath(folderMapping.targetPath)
            guard canonicalTargetRoots.contains(where: { Self.containsPath(parent: $0, child: targetPath) }) else {
                throw BessieProjectTargetMigrationError.unsafeRemotePath("Target path is outside every approved target root: \(targetPath)")
            }
            if validateRemote {
                let facts = try remoteInspector.inspect(targetPath)
                guard facts.exists, facts.isDirectory, !facts.isSymbolicLink,
                      facts.canonicalPath == targetPath else {
                    throw BessieProjectTargetMigrationError.unsafeRemotePath("Target must be an existing canonical non-symlink directory: \(targetPath)")
                }
            }
            result.folders[index].path = targetPath
        }
        let normalized = try result.normalizedForCatalog()
        guard normalized == result else {
            throw BessieProjectTargetMigrationError.invalidManifest("Migrated Project normalization would change fields beyond explicit target routing.")
        }
        let data = try BessieProjectCodec.encode(result)
        guard try BessieProjectCodec.decode(data) == result else {
            throw BessieProjectTargetMigrationError.auditFailed("Migrated Project failed an exact BessieCore encode/decode round trip.")
        }
        return data
    }

    private func preparedConnectionResult(
        _ sourceData: Data,
        manifest: BessieProjectTargetMigrationManifest
    ) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
              var definitions = object["connections"] as? [[String: Any]] else {
            throw BessieProjectTargetMigrationError.invalidManifest("Connection configuration must be a JSON object with a connections array.")
        }
        let sourceIndices = definitions.indices.filter { definitions[$0]["id"] as? String == manifest.sourceConnectionID }
        let targetIndices = definitions.indices.filter { definitions[$0]["id"] as? String == manifest.targetConnectionID }
        guard sourceIndices.count == 1, targetIndices.count == 1,
              let sourceIndex = sourceIndices.first,
              let targetIndex = targetIndices.first else {
            throw BessieProjectTargetMigrationError.invalidManifest("Source and target connections must each occur exactly once in the raw configuration.")
        }
        definitions[sourceIndex]["enabled"] = false
        definitions[targetIndex]["enabled"] = true
        definitions[targetIndex]["connect_at_launch"] = true
        object["connections"] = definitions
        object["selected_connection_id"] = manifest.targetConnectionID
        object["default_project_connection_id"] = manifest.targetConnectionID
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let decoded = try JSONDecoder().decode(BessieConnectionState.self, from: data)
        guard decoded.selectedConnectionID == manifest.targetConnectionID,
              decoded.defaultProjectConnectionID == manifest.targetConnectionID,
              decoded.connections.first(where: { $0.id == manifest.sourceConnectionID })?.enabled == false,
              let target = decoded.connections.first(where: { $0.id == manifest.targetConnectionID }),
              target.enabled,
              target.connectAtLaunch else {
            throw BessieProjectTargetMigrationError.auditFailed("Patched connection result did not decode to the required remote-only state.")
        }
        return data
    }

    private func validateManifestShape(_ manifest: BessieProjectTargetMigrationManifest) throws {
        guard manifest.schemaVersion == BessieProjectTargetMigrationManifest.currentSchemaVersion else {
            throw BessieProjectTargetMigrationError.invalidManifest("Unsupported manifest schema v\(manifest.schemaVersion).")
        }
        guard manifest.sourceConnectionID != manifest.targetConnectionID,
              manifest.expectedProjectCount > 0,
              manifest.expectedProjectCount == manifest.projects.count,
              Set(manifest.projects.map(\.projectID)).count == manifest.projects.count,
              manifest.projects.allSatisfy({ Set($0.folders.map(\.folderID)).count == $0.folders.count }),
              !manifest.approvedSourceRoots.isEmpty,
              !manifest.approvedTargetRoots.isEmpty else {
            throw BessieProjectTargetMigrationError.invalidManifest("Connection IDs, expected count, mappings, and approved roots must be explicit and non-empty.")
        }
        let absolutePaths = [manifest.connectionsPath, manifest.projectsPath, manifest.backupPath, manifest.journalPath]
            + manifest.approvedSourceRoots + manifest.approvedTargetRoots
            + manifest.projects.flatMap { $0.folders.flatMap { [$0.sourcePath, $0.targetPath] } }
        guard absolutePaths.allSatisfy({ NSString(string: $0).isAbsolutePath }) else {
            throw BessieProjectTargetMigrationError.invalidManifest("Every local and remote path must be absolute.")
        }
        guard manifest.projects.allSatisfy({
            $0.sourceSHA256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil
        }), manifest.connectionSourceSHA256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
            throw BessieProjectTargetMigrationError.invalidManifest("Every source SHA-256 must contain exactly 64 hexadecimal characters.")
        }
    }

    private func validatedJournal(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        try validateManifestShape(manifest)
        let journalURL = URL(fileURLWithPath: manifest.journalPath)
        try Self.requirePrivateOwnedRegularFile(journalURL, label: "migration journal")
        try requireCanonicalExistingPath(journalURL, label: "migration journal")
        let journal = try Self.loadJournal(for: manifest)
        guard journal.schemaVersion == BessieProjectTargetMigrationJournal.currentSchemaVersion,
              journal.operationID == manifest.operationID,
              journal.manifestSHA256 == Self.sha256(manifestData),
              journal.projects.count == manifest.expectedProjectCount else {
            throw BessieProjectTargetMigrationError.invalidJournal("Schema, operation, manifest hash, or expected Project count does not match.")
        }
        let expectedProjectIDs = Set(manifest.projects.map(\.projectID))
        let journalProjectIDs = Set(journal.projects.compactMap(\.projectID))
        let mappingsByID = Dictionary(uniqueKeysWithValues: manifest.projects.map { ($0.projectID, $0) })
        let canonicalProjectsRoot = URL(fileURLWithPath: manifest.projectsPath, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let manifestBackupRoot = URL(fileURLWithPath: manifest.backupPath, isDirectory: true)
        try Self.requirePrivateOwnedDirectory(manifestBackupRoot, label: "migration backup")
        try requireCanonicalExistingPath(manifestBackupRoot, label: "migration backup")
        let expectedBackupRoot = manifestBackupRoot.standardizedFileURL
        try Self.requirePrivateOwnedDirectory(expectedBackupRoot, label: "migration backup")
        try requireCanonicalExistingPath(expectedBackupRoot, label: "migration backup")
        let expectedProjectBackupRoot = expectedBackupRoot.appendingPathComponent("Projects", isDirectory: true)
        let manifestTargetRoots = manifest.approvedTargetRoots.map(Self.standardizedAbsolutePath)
        let expectedControlPath = Self.migrationSSHControlPath(operationID: manifest.operationID)
        guard expectedProjectIDs == journalProjectIDs,
              Self.isSHA256(journal.backupTreeSHA256) else {
            throw BessieProjectTargetMigrationError.invalidJournal("Project UUID set does not match the manifest inventory.")
        }
        try Self.verifyPublishedBackupEvidence(
            expectedBackupRoot,
            manifest: manifest,
            manifestData: manifestData,
            expectedSHA256: journal.backupTreeSHA256
        )
        for record in journal.projects {
            guard let projectID = record.projectID else {
                throw BessieProjectTargetMigrationError.invalidJournal("A Project journal record has no Project UUID.")
            }
            let liveURL = URL(fileURLWithPath: record.livePath)
            let backupURL = URL(fileURLWithPath: record.backupPath)
            guard liveURL.lastPathComponent.caseInsensitiveCompare(projectID.uuidString + ".json") == .orderedSame,
                  try Self.sameFileSystemItem(liveURL.deletingLastPathComponent(), canonicalProjectsRoot),
                  backupURL.lastPathComponent.caseInsensitiveCompare(projectID.uuidString + ".json") == .orderedSame,
                  try Self.sameFileSystemItem(backupURL.deletingLastPathComponent(), expectedProjectBackupRoot),
                  record.sourceSHA256 == mappingsByID[projectID]?.sourceSHA256.lowercased(),
                  Self.isSHA256(record.resultSHA256) else {
                throw BessieProjectTargetMigrationError.invalidJournal(
                    "Project paths or hashes do not match the exact manifest and backup inventory for \(projectID.uuidString)."
                )
            }
            try requireRegularFile(backupURL, label: "Project backup")
            let backupData = try Data(contentsOf: backupURL)
            guard Self.sha256(backupData) == record.sourceSHA256,
                  let mapping = mappingsByID[projectID],
                  Self.sha256(try preparedResult(
                      project: BessieProjectCodec.decode(backupData),
                      mapping: mapping,
                      manifest: manifest,
                      canonicalTargetRoots: manifestTargetRoots,
                      validateRemote: false
                  )) == record.resultSHA256,
                  try Self.metadata(at: backupURL) == record.sourceMetadata else {
                throw BessieProjectTargetMigrationError.invalidJournal(
                    "Project journal hashes or metadata are not derivable from the verified source backup for \(projectID.uuidString)."
                )
            }
        }
        let connectionLiveURL = URL(fileURLWithPath: journal.connection.livePath)
        let manifestConnectionURL = URL(fileURLWithPath: manifest.connectionsPath)
        let connectionBackupURL = URL(fileURLWithPath: journal.connection.backupPath)
        guard connectionLiveURL.lastPathComponent == manifestConnectionURL.lastPathComponent,
              try Self.sameFileSystemItem(connectionLiveURL.deletingLastPathComponent(), manifestConnectionURL.deletingLastPathComponent()),
              journal.connection.projectID == nil,
              journal.connection.sourceSHA256 == manifest.connectionSourceSHA256.lowercased(),
              Self.isSHA256(journal.connection.resultSHA256),
              connectionBackupURL.lastPathComponent == "connections.json",
              try Self.sameFileSystemItem(connectionBackupURL.deletingLastPathComponent(), expectedBackupRoot) else {
            throw BessieProjectTargetMigrationError.invalidJournal("Connection record does not match the manifest connection path.")
        }
        try requireRegularFile(connectionBackupURL, label: "connection backup")
        let connectionBackupData = try Data(contentsOf: connectionBackupURL)
        guard Self.sha256(connectionBackupData) == journal.connection.sourceSHA256,
              Self.sha256(try preparedConnectionResult(connectionBackupData, manifest: manifest)) == journal.connection.resultSHA256,
              try Self.metadata(at: connectionBackupURL) == journal.connection.sourceMetadata else {
            throw BessieProjectTargetMigrationError.invalidJournal(
                "Connection journal hashes or metadata are not derivable from the verified source backup."
            )
        }
        guard journal.projects.allSatisfy({ Self.contains(parent: expectedBackupRoot, child: URL(fileURLWithPath: $0.backupPath)) }),
              Self.contains(parent: expectedBackupRoot, child: URL(fileURLWithPath: journal.connection.backupPath)) else {
            throw BessieProjectTargetMigrationError.invalidJournal("A backup record escapes the operation backup root.")
        }
        guard journal.sshControlPath == expectedControlPath,
              BessieConnectionDefinition.isSafeSSHHost(journal.sshHost),
              journal.sshMasterPID > 0 else {
            throw BessieProjectTargetMigrationError.invalidJournal("SSH host, PID, or control path does not match operation ownership.")
        }
        try validateJournalPhase(journal)
        return journal
    }

    private func validateJournalPhase(_ journal: BessieProjectTargetMigrationJournal) throws {
        let allProjectsComplete = journal.projects.allSatisfy { $0.completedResultSHA256 == $0.resultSHA256 }
        let noProjectsComplete = journal.projects.allSatisfy { $0.completedResultSHA256 == nil }
        let connectionComplete = journal.connection.completedResultSHA256 == journal.connection.resultSHA256
        let connectionIncomplete = journal.connection.completedResultSHA256 == nil
        let unaudited = journal.auditMessage == nil && journal.terminalOutcome == nil && journal.sshMasterClosedAt == nil
        let valid: Bool
        switch journal.phase {
        case .preflighted:
            valid = noProjectsComplete && connectionIncomplete && unaudited
        case .applyingProjects:
            valid = connectionIncomplete && unaudited
        case .applyingConnections:
            valid = allProjectsComplete && unaudited
        case .applied:
            valid = allProjectsComplete && connectionComplete && unaudited
        case .success:
            valid = allProjectsComplete && connectionComplete
                && journal.auditMessage != nil && journal.terminalOutcome == .migrated
                && journal.sshMasterClosedAt == nil
        case .rollingBack:
            valid = unaudited
        case .rolledBack:
            valid = noProjectsComplete && connectionIncomplete && unaudited
        case .rollbackVerified:
            valid = noProjectsComplete && connectionIncomplete
                && journal.auditMessage != nil && journal.terminalOutcome == .rolledBack
                && journal.sshMasterClosedAt == nil
        case .closingSSHMaster:
            let migrated = journal.terminalOutcome == .migrated && allProjectsComplete && connectionComplete
            let rolledBack = journal.terminalOutcome == .rolledBack && noProjectsComplete && connectionIncomplete
            valid = (migrated || rolledBack) && journal.auditMessage != nil && journal.sshMasterClosedAt == nil
        case .readyForRelaunch:
            let migrated = journal.terminalOutcome == .migrated && allProjectsComplete && connectionComplete
            let rolledBack = journal.terminalOutcome == .rolledBack && noProjectsComplete && connectionIncomplete
            valid = (migrated || rolledBack) && journal.auditMessage != nil && journal.sshMasterClosedAt != nil
        }
        guard valid else {
            throw BessieProjectTargetMigrationError.invalidJournal(
                "Phase \(journal.phase.rawValue) has inconsistent completion, audit, outcome, or SSH-close state."
            )
        }
    }

    private func restore(record: BessieProjectTargetMigrationJournal.FileRecord) throws {
        let liveURL = URL(fileURLWithPath: record.livePath)
        let currentHash = (try? Data(contentsOf: liveURL)).map(Self.sha256)
        guard currentHash == record.sourceSHA256 || currentHash == record.resultSHA256 else {
            throw BessieProjectTargetMigrationError.sourceDrift(
                "Refusing rollback because \(liveURL.lastPathComponent) is missing or matches neither known migration hash. The verified backup was retained for operator review."
            )
        }
        try verifyBackup(record)
        if currentHash == record.sourceSHA256,
           try Self.metadata(at: liveURL) == record.sourceMetadata {
            return
        }
        try Self.replaceDurably(
            Data(contentsOf: URL(fileURLWithPath: record.backupPath)),
            at: liveURL,
            preservingFrom: URL(fileURLWithPath: record.backupPath)
        )
        guard Self.sha256(try Data(contentsOf: liveURL)) == record.sourceSHA256,
              try Self.metadata(at: liveURL) == record.sourceMetadata else {
            throw BessieProjectTargetMigrationError.auditFailed("Rollback did not restore \(liveURL.lastPathComponent) exactly.")
        }
    }

    private func verifyBackup(_ record: BessieProjectTargetMigrationJournal.FileRecord) throws {
        let backupURL = URL(fileURLWithPath: record.backupPath)
        guard Self.sha256(try Data(contentsOf: backupURL)) == record.sourceSHA256,
              try Self.metadata(at: backupURL) == record.sourceMetadata else {
            throw BessieProjectTargetMigrationError.backupFailed("Backup bytes or metadata changed for \(backupURL.lastPathComponent).")
        }
    }

    private func verifyDirectoryMetadata(_ journal: BessieProjectTargetMigrationJournal) throws {
        let projectsDirectory = URL(fileURLWithPath: journal.projects[0].livePath).deletingLastPathComponent()
        let connectionDirectory = URL(fileURLWithPath: journal.connection.livePath).deletingLastPathComponent()
        guard try Self.metadata(at: projectsDirectory) == journal.projectDirectoryMetadata,
              try Self.metadata(at: connectionDirectory) == journal.connectionDirectoryMetadata else {
            throw BessieProjectTargetMigrationError.auditFailed("Live configuration or Project directory metadata changed during migration.")
        }
    }

    private func prepareOrRecoverBackup(
        at backupURL: URL,
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data,
        connectionURL: URL,
        projectsURL: URL
    ) throws {
        let marker = BackupMarker(
            schemaVersion: 1,
            operationID: manifest.operationID,
            manifestSHA256: Self.sha256(manifestData)
        )
        let markerURL = backupURL.appendingPathComponent("operation.json")
        let ownerURL = backupURL.appendingPathComponent("owner.json")
        let retainedManifestURL = backupURL.appendingPathComponent("manifest.json")
        if try Self.pathEntryExists(backupURL) {
            try Self.requirePrivateOwnedDirectory(backupURL, label: "migration backup")
            guard try Self.matchesBackupMarker(marker, at: ownerURL),
                  try Self.matchesBackupMarker(marker, at: markerURL),
                  try Data(contentsOf: retainedManifestURL) == manifestData else {
                throw BessieProjectTargetMigrationError.backupFailed("An existing backup does not prove ownership by this exact operation and manifest.")
            }
            try Self.verifyBackupTree(
                backupURL,
                connectionURL: connectionURL,
                projectsURL: projectsURL,
                manifestData: manifestData,
                marker: marker
            )
            return
        }

        let stagingURL = backupURL.deletingLastPathComponent()
            .appendingPathComponent(".\(backupURL.lastPathComponent).staging", isDirectory: true)
        if try Self.pathEntryExists(stagingURL) {
            try Self.requirePrivateOwnedDirectory(stagingURL, label: "staging migration backup")
            let stagedOwnerURL = stagingURL.appendingPathComponent("owner.json")
            let stagedMarkerURL = stagingURL.appendingPathComponent("operation.json")
            let stagedManifestURL = stagingURL.appendingPathComponent("manifest.json")
            let contents = try FileManager.default.contentsOfDirectory(atPath: stagingURL.path)
            if contents.isEmpty {
                try FileManager.default.removeItem(at: stagingURL)
                try Self.fsyncDirectory(stagingURL.deletingLastPathComponent())
            } else {
                guard try Self.matchesBackupMarker(marker, at: stagedOwnerURL) else {
                    throw BessieProjectTargetMigrationError.backupFailed(
                        "An incomplete staging backup has no exact-operation owner record; preserve it for operator review."
                    )
                }
                let allowedItems = Set(["owner.json", "connections.json", "Projects", "manifest.json", "operation.json"])
                guard Set(contents).isSubset(of: allowedItems) else {
                    throw BessieProjectTargetMigrationError.backupFailed(
                        "The incomplete staging backup contains unknown evidence; preserve it for operator review."
                    )
                }
                try Self.requireKnownStagingItemTypes(stagingURL, contents: contents)
                if FileManager.default.fileExists(atPath: stagedMarkerURL.path) {
                    guard try Self.matchesBackupMarker(marker, at: stagedMarkerURL),
                          try Data(contentsOf: stagedManifestURL) == manifestData else {
                        throw BessieProjectTargetMigrationError.backupFailed(
                            "The staged backup completion evidence does not match this operation and manifest."
                        )
                    }
                    try Self.verifyBackupTree(
                        stagingURL,
                        connectionURL: connectionURL,
                        projectsURL: projectsURL,
                        manifestData: manifestData,
                        marker: marker
                    )
                    try Self.fullSyncTree(stagingURL)
                    guard rename(stagingURL.path, backupURL.path) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    try Self.fsyncDirectory(backupURL.deletingLastPathComponent())
                    return
                }

                // Rebuild only when every staged payload item is a verified source copy.
                if FileManager.default.fileExists(atPath: stagingURL.appendingPathComponent("connections.json").path) {
                    let stagedConnection = stagingURL.appendingPathComponent("connections.json")
                    guard Self.sha256(try Data(contentsOf: stagedConnection)) == Self.sha256(try Data(contentsOf: connectionURL)),
                          try Self.metadata(at: stagedConnection) == Self.metadata(at: connectionURL) else {
                        throw BessieProjectTargetMigrationError.backupFailed(
                            "The incomplete staged connection copy is not exact; preserve it for operator review."
                        )
                    }
                }
                if FileManager.default.fileExists(atPath: stagedManifestURL.path),
                   try Data(contentsOf: stagedManifestURL) != manifestData {
                    throw BessieProjectTargetMigrationError.backupFailed(
                        "The incomplete staged manifest is not exact; preserve it for operator review."
                    )
                }
                let stagedProjects = stagingURL.appendingPathComponent("Projects", isDirectory: true)
                if FileManager.default.fileExists(atPath: stagedProjects.path) {
                    guard try Self.backupTreeIsVerifiedSubset(stagedProjects, of: projectsURL) else {
                        throw BessieProjectTargetMigrationError.backupFailed(
                            "The incomplete staged Project payload is not a verified source subset; preserve it for operator review."
                        )
                    }
                }
                try FileManager.default.removeItem(at: stagingURL)
                try Self.fsyncDirectory(stagingURL.deletingLastPathComponent())
            }
        }

        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try afterBackupStep(.stagingDirectoryCreated)
        try Self.replaceDurably(
            Self.migrationEncoder.encode(marker),
            at: stagingURL.appendingPathComponent("owner.json"),
            preservingFrom: nil
        )
        try afterBackupStep(.ownershipRecorded)
        let stagedConnection = stagingURL.appendingPathComponent("connections.json")
        let stagedProjects = stagingURL.appendingPathComponent("Projects", isDirectory: true)
        try Self.copyPreservingMetadata(from: connectionURL, to: stagedConnection)
        try afterBackupStep(.connectionCopied)
        try Self.copyPreservingMetadata(from: projectsURL, to: stagedProjects)
        try afterBackupStep(.projectsCopied)
        try Self.replaceDurably(manifestData, at: stagingURL.appendingPathComponent("manifest.json"), preservingFrom: nil)
        try Self.fullSyncTree(stagingURL)
        guard Self.sha256(try Data(contentsOf: stagedConnection)) == Self.sha256(try Data(contentsOf: connectionURL)),
              try Self.metadata(at: stagedConnection) == Self.metadata(at: connectionURL),
              try Self.backupTreeInventory(stagedProjects) == Self.backupTreeInventory(projectsURL) else {
            throw BessieProjectTargetMigrationError.backupFailed("Staged backup payload differs from the live connection or Project catalog.")
        }
        try Self.replaceDurably(Self.migrationEncoder.encode(marker), at: stagingURL.appendingPathComponent("operation.json"), preservingFrom: nil)
        try Self.verifyBackupTree(
            stagingURL,
            connectionURL: connectionURL,
            projectsURL: projectsURL,
            manifestData: manifestData,
            marker: marker
        )
        guard rename(stagingURL.path, backupURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try Self.fsyncDirectory(backupURL.deletingLastPathComponent())
    }

    private static func pathEntryExists(_ url: URL) throws -> Bool {
        var details = stat()
        if lstat(url.path, &details) == 0 { return true }
        guard errno == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return false
    }

    private static func verifyBackupTree(
        _ backupURL: URL,
        connectionURL: URL,
        projectsURL: URL,
        manifestData: Data,
        marker: BackupMarker
    ) throws {
        let backupConnection = backupURL.appendingPathComponent("connections.json")
        let backupProjects = backupURL.appendingPathComponent("Projects", isDirectory: true)
        let backupManifest = backupURL.appendingPathComponent("manifest.json")
        let backupOwner = backupURL.appendingPathComponent("owner.json")
        let backupMarker = backupURL.appendingPathComponent("operation.json")
        try requirePrivateOwnedDirectory(backupURL, label: "migration backup")
        let expectedItems = Set(["connections.json", "Projects", "manifest.json", "owner.json", "operation.json"])
        guard try Set(FileManager.default.contentsOfDirectory(atPath: backupURL.path)) == expectedItems,
              try Data(contentsOf: backupManifest) == manifestData,
              try matchesBackupMarker(marker, at: backupOwner),
              try matchesBackupMarker(marker, at: backupMarker),
              sha256(try Data(contentsOf: backupConnection)) == sha256(try Data(contentsOf: connectionURL)),
              try metadata(at: backupConnection) == metadata(at: connectionURL),
              try backupTreeInventory(backupProjects) == backupTreeInventory(projectsURL) else {
            throw BessieProjectTargetMigrationError.backupFailed("Backup payload, inventory, metadata, manifest, or completion marker is incomplete or changed.")
        }
    }

    private static func verifyPublishedBackupEvidence(
        _ backupURL: URL,
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data,
        expectedSHA256: String
    ) throws {
        let marker = BackupMarker(
            schemaVersion: 1,
            operationID: manifest.operationID,
            manifestSHA256: sha256(manifestData)
        )
        let expectedItems = Set(["connections.json", "Projects", "manifest.json", "owner.json", "operation.json"])
        guard try Set(FileManager.default.contentsOfDirectory(atPath: backupURL.path)) == expectedItems,
              try Data(contentsOf: backupURL.appendingPathComponent("manifest.json")) == manifestData,
              try matchesBackupMarker(marker, at: backupURL.appendingPathComponent("owner.json")),
              try matchesBackupMarker(marker, at: backupURL.appendingPathComponent("operation.json")),
              try backupTreeSHA256(backupURL) == expectedSHA256 else {
            throw BessieProjectTargetMigrationError.invalidJournal(
                "Published backup ownership, manifest, exact inventory, or tree digest changed."
            )
        }
    }

    private static func requireKnownStagingItemTypes(_ stagingURL: URL, contents: [String]) throws {
        for name in contents {
            let expectedType: mode_t = name == "Projects" ? S_IFDIR : S_IFREG
            let url = stagingURL.appendingPathComponent(name, isDirectory: expectedType == S_IFDIR)
            var details = stat()
            guard lstat(url.path, &details) == 0,
                  (details.st_mode & S_IFMT) == expectedType,
                  details.st_uid == geteuid(),
                  (expectedType != S_IFREG || details.st_nlink == 1) else {
                throw BessieProjectTargetMigrationError.backupFailed(
                    "Known staging entry has an unsafe type, owner, or link count; preserve it for operator review: \(url.path)"
                )
            }
        }
    }

    private static func matchesBackupMarker(_ expected: BackupMarker, at url: URL) throws -> Bool {
        try requirePrivateOwnedRegularFile(url, label: "migration backup marker")
        let actual = try migrationDecoder.decode(BackupMarker.self, from: Data(contentsOf: url))
        return actual.schemaVersion == expected.schemaVersion
            && actual.operationID == expected.operationID
            && actual.manifestSHA256 == expected.manifestSHA256
    }

    private static func backupTreeInventory(_ root: URL) throws -> [String: BackupTreeRecord] {
        var result = [".": BackupTreeRecord(isDirectory: true, hash: nil, metadata: try metadata(at: root))]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { url, error in
                enumerationError = BessieProjectTargetMigrationError.backupFailed("Could not inventory \(url.path): \(error.localizedDescription)")
                return false
            }
        ) else {
            throw BessieProjectTargetMigrationError.backupFailed("Could not enumerate the Project catalog backup.")
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true else {
                throw BessieProjectTargetMigrationError.backupFailed("Project catalog contains an unsupported or symbolic-link item: \(url.path)")
            }
            let relative = String(url.path.dropFirst(root.path.count + (root.path.hasSuffix("/") ? 0 : 1)))
            let isDirectory = values.isDirectory == true
            result[relative] = BackupTreeRecord(
                isDirectory: isDirectory,
                hash: isDirectory ? nil : sha256(try Data(contentsOf: url)),
                metadata: try metadata(at: url)
            )
        }
        if let enumerationError { throw enumerationError }
        return result
    }

    private static func backupTreeSHA256(_ root: URL) throws -> String {
        let inventory = try backupTreeInventory(root)
        let entries = inventory.keys.sorted().map {
            BackupTreeDigestEntry(path: $0, record: inventory[$0]!)
        }
        return sha256(try migrationEncoder.encode(entries))
    }

    private static func backupTreeIsVerifiedSubset(_ candidate: URL, of source: URL) throws -> Bool {
        let candidateInventory = try backupTreeInventory(candidate)
        let sourceInventory = try backupTreeInventory(source)
        return candidateInventory.allSatisfy { sourceInventory[$0.key] == $0.value }
    }

    private func updateJournal(
        _ journal: inout BessieProjectTargetMigrationJournal,
        manifest: BessieProjectTargetMigrationManifest
    ) throws {
        journal.updatedAt = now()
        try saveJournal(journal, to: URL(fileURLWithPath: manifest.journalPath))
    }

    private func saveJournal(_ journal: BessieProjectTargetMigrationJournal, to url: URL) throws {
        try Self.replaceDurably(Self.migrationEncoder.encode(journal), at: url, preservingFrom: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try Self.fsyncFile(url)
        try Self.fsyncDirectory(url.deletingLastPathComponent())
        try afterJournalWrite()
    }

    private func requireRegularFile(_ url: URL, label: String) throws {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFREG,
              details.st_uid == geteuid(),
              details.st_nlink == 1,
              (details.st_mode & 0o022) == 0 else {
            throw BessieProjectTargetMigrationError.invalidManifest("\(label) must be a regular non-symlink file: \(url.path)")
        }
    }

    private func requireDirectory(_ url: URL, label: String) throws {
        try Self.requireOwnedSafeDirectory(url, label: label)
    }

    private func requireCanonicalExistingPath(_ url: URL, label: String) throws {
        let standardized = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard standardized == resolved else {
            throw BessieProjectTargetMigrationError.invalidManifest("\(label) contains a symbolic-link or noncanonical parent component: \(url.path)")
        }
    }

    private static func requirePrivateOwnedDirectory(_ url: URL, label: String) throws {
        try requirePrivateOwnedItem(url, label: label, expectedType: S_IFDIR, requiredMode: 0o700)
    }

    private static func requirePrivateOwnedRegularFile(_ url: URL, label: String) throws {
        try requirePrivateOwnedItem(url, label: label, expectedType: S_IFREG, requiredMode: 0o600)
    }

    private static func requirePrivateOwnedItem(
        _ url: URL,
        label: String,
        expectedType: mode_t,
        requiredMode: mode_t
    ) throws {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == expectedType,
              details.st_uid == geteuid(),
              (expectedType != S_IFREG || details.st_nlink == 1),
              (details.st_mode & 0o777) == requiredMode else {
            throw BessieProjectTargetMigrationError.backupFailed(
                "\(label) must be a private, current-user-owned, non-symlink filesystem item: \(url.path)"
            )
        }
    }

    private static func requireOwnedSafeDirectory(_ url: URL, label: String) throws {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFDIR,
              details.st_uid == geteuid(),
              (details.st_mode & 0o022) == 0,
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw BessieProjectTargetMigrationError.invalidManifest(
                "\(label) must be current-user-owned, non-symlink, and not group/world-writable: \(url.path)"
            )
        }
    }

    private static func sameFileSystemItem(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        let lhsIdentifier = try lhs.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject
        let rhsIdentifier = try rhs.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject
        return lhsIdentifier?.isEqual(rhsIdentifier) == true
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func metadata(at url: URL) throws -> BessieMigrationFileMetadata {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value ?? 0
        let group = (attributes[.groupOwnerAccountID] as? NSNumber)?.uint32Value ?? 0
        #if os(macOS)
        let aclOutput = try runProcess("/bin/ls", ["-le", url.path], allowFailure: false)
        let aclEntries = aclOutput.split(whereSeparator: \.isNewline).dropFirst().map(String.init)
            .filter { $0.range(of: #"^\s*\d+:"#, options: .regularExpression) != nil }
        let namesOutput = try runProcess("/usr/bin/xattr", [url.path], allowFailure: false)
        let names = namesOutput.split(whereSeparator: \.isNewline).map(String.init).sorted()
        var xattrs: [String: String] = [:]
        for name in names {
            xattrs[name] = try runProcess("/usr/bin/xattr", ["-px", name, url.path], allowFailure: false)
                .filter { !$0.isWhitespace }.lowercased()
        }
        #else
        let aclEntries: [String] = []
        let xattrs: [String: String] = [:]
        #endif
        return .init(mode: mode, ownerID: owner, groupID: group, aclEntries: aclEntries, extendedAttributes: xattrs)
    }

    public static func containsPath(parent: String, child: String) -> Bool {
        let normalizedParent = standardizedAbsolutePath(parent)
        let normalizedChild = standardizedAbsolutePath(child)
        return normalizedChild == normalizedParent || normalizedChild.hasPrefix(normalizedParent == "/" ? "/" : normalizedParent + "/")
    }

    private static func contains(parent: URL, child: URL) -> Bool {
        containsPath(parent: parent.standardizedFileURL.path, child: child.standardizedFileURL.path)
    }

    private static func standardizedAbsolutePath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    private static func schemaVersion(_ data: Data) throws -> Int {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schemaVersion"] as? NSNumber else {
            throw BessieProjectTargetMigrationError.invalidManifest("Project document has no integer schemaVersion.")
        }
        return version.intValue
    }

    private static var migrationEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var migrationDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func copyPreservingMetadata(from source: URL, to destination: URL) throws {
        #if os(macOS)
        _ = try runProcess("/usr/bin/ditto", ["--rsrc", "--extattr", "--acl", source.path, destination.path], allowFailure: false)
        #else
        try FileManager.default.copyItem(at: source, to: destination)
        #endif
    }

    private static func fullSyncTree(_ root: URL) throws {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { url, error in
                enumerationError = BessieProjectTargetMigrationError.backupFailed("Could not sync \(url.path): \(error.localizedDescription)")
                return false
            }
        ) else {
            throw BessieProjectTargetMigrationError.backupFailed("Could not enumerate the staged backup for durability verification.")
        }
        var directories: [URL] = [root]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { directories.append(url) }
            else if values.isRegularFile == true { try fsyncFile(url) }
        }
        if let enumerationError { throw enumerationError }
        for directory in directories.reversed() { try fsyncDirectory(directory) }
    }

    private static func replaceDurably(_ data: Data, at destination: URL, preservingFrom metadataSource: URL?) throws {
        let parent = destination.deletingLastPathComponent()
        let parentIdentity = try safeDirectoryIdentity(parent)
        try requireSafeReplacementDestination(destination)
        let temporary = parent.appendingPathComponent(".\(UUID().uuidString).migration.tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let metadataSource {
            try requireSafeReplacementSource(metadataSource)
            try copyPreservingMetadata(from: metadataSource, to: temporary)
            try requireSafeReplacementSource(temporary)
            try writeAndSync(data, toExistingFile: temporary)
        } else {
            let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            do {
                try writeAll(data, descriptor: descriptor)
                try durableSync(descriptor, full: true)
                guard close(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            } catch {
                close(descriptor)
                throw error
            }
        }
        guard try safeDirectoryIdentity(parent) == parentIdentity else {
            throw BessieProjectTargetMigrationError.backupFailed(
                "Replacement parent changed during the durable write: \(parent.path)"
            )
        }
        try requireSafeReplacementDestination(destination)
        guard rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try fsyncDirectory(destination.deletingLastPathComponent())
    }

    private static func writeAndSync(_ data: Data, toExistingFile url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_TRUNC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            try writeAll(data, descriptor: descriptor)
            try durableSync(descriptor, full: true)
            guard close(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let written = write(descriptor, base.advanced(by: offset), data.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += written
            }
        }
    }

    private static func fsyncFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try durableSync(descriptor, full: true)
    }

    private static func fsyncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try durableSync(descriptor, full: false)
    }

    private static func durableSync(_ descriptor: Int32, full: Bool) throws {
        #if os(macOS)
        if full, fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        #endif
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func safeDirectoryIdentity(_ url: URL) throws -> DirectoryIdentity {
        try requireOwnedSafeDirectory(url, label: "replacement parent")
        var details = stat()
        guard lstat(url.path, &details) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return DirectoryIdentity(device: details.st_dev, inode: details.st_ino)
    }

    private static func requireSafeReplacementDestination(_ url: URL) throws {
        var details = stat()
        if lstat(url.path, &details) != 0 {
            guard errno == ENOENT else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return
        }
        guard (details.st_mode & S_IFMT) == S_IFREG,
              details.st_uid == geteuid(),
              details.st_nlink == 1,
              (details.st_mode & 0o022) == 0 else {
            throw BessieProjectTargetMigrationError.backupFailed(
                "Replacement destination is not a safe current-user-owned regular file: \(url.path)"
            )
        }
    }

    private static func requireSafeReplacementSource(_ url: URL) throws {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFREG,
              details.st_uid == geteuid(),
              details.st_nlink == 1,
              (details.st_mode & 0o022) == 0 else {
            throw BessieProjectTargetMigrationError.backupFailed(
                "Replacement metadata source is not a safe current-user-owned regular file: \(url.path)"
            )
        }
    }

    private static func runProcess(_ executable: String, _ arguments: [String], allowFailure: Bool) throws -> String {
        let result: FoundationProcessCommandResult
        do {
            result = try FoundationProcessCommandRunner.run(
                executableURL: URL(fileURLWithPath: executable),
                arguments: arguments,
                timeout: 120
            )
        } catch FoundationProcessCommandError.timedOut {
            throw BessieProjectTargetMigrationError.backupFailed("\(executable) timed out.")
        }
        guard allowFailure || result.exitCode == 0 else {
            let reason = String(data: result.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BessieProjectTargetMigrationError.backupFailed(reason?.isEmpty == false ? reason! : "\(executable) failed with status \(result.exitCode).")
        }
        return String(data: result.stdout, encoding: .utf8) ?? ""
    }
}
