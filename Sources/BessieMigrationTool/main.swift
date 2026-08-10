import BessieCore
import Darwin
import Foundation

enum MigrationToolError: LocalizedError {
    case usage
    case targetUnavailable(String)
    case ssh(String)
    case lockUnavailable(String)
    case bessieRunning(String)
    case ownership(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: BessieMigrationTool <preflight|recover-prejournal|apply|resume|rollback|audit|status> --manifest /absolute/path/manifest.json"
        case .targetUnavailable(let id):
            "The manifest target connection \(id) is not a valid, enabled SSH herd with the preflight host."
        case .ssh(let reason):
            "Migration SSH ControlMaster failed. \(reason)"
        case .lockUnavailable(let path):
            "Another Bessie or migration operation owns the required lock at \(path)."
        case .bessieRunning(let pids):
            "Stop Bessie before migration. Running BessieApp PID(s): \(pids). Herdr and pane processes were not touched."
        case .ownership(let reason):
            "Migration SSH ownership evidence is invalid. \(reason)"
        }
    }
}

struct SSHOwnerMarker: Codable {
    let operationID: UUID
    let manifestSHA256: String
    let host: String
    let token: UUID
    let purpose: SSHMasterPurpose
    var pid: Int32?
}

enum SSHMasterPurpose: String, Codable {
    case migration
    case verification

    var directorySuffix: String {
        switch self {
        case .migration: "m"
        case .verification: "v"
        }
    }
}

private struct ActiveMigrationMarker: Codable {
    let operationID: UUID
    let manifestSHA256: String
    let journalPath: String
}

struct PrejournalRecoveryExpectation {
    let operationID: UUID
    let manifestSHA256: String
    let host: String
    let purpose: SSHMasterPurpose
}

private struct PrejournalRecoveryItemIdentity: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
    let mode: UInt16
    let ownerID: UInt32
    let groupID: UInt32
    let linkCount: UInt16
    let size: Int64
}

private struct PrejournalRecoveryGateReport: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let manifestSHA256: String
    let host: String
    let purpose: SSHMasterPurpose
    let ownerToken: UUID
    let sourceDirectory: String
    let controlPath: String
    let archiveDirectory: String
    let ownerSHA256: String
    let activeMarkerSHA256: String
    let directoryIdentity: PrejournalRecoveryItemIdentity
    let ownerIdentity: PrejournalRecoveryItemIdentity
    let inventory: [String]
    let muxCheckStatus: Int32
    let processInspection: String
    let checkedAt: Date
}

private struct PrejournalRecoveryTerminalReport: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let manifestSHA256: String
    let ownerSHA256: String
    let activeMarkerSHA256: String
    let gateReportSHA256: String
    let sourceDirectoryRemoved: Bool
    let journalAbsent: Bool
    let activeMarkerRetained: Bool
    let sourcesUnchanged: Bool
    let completedAt: Date
}

struct PrejournalRecoveryResult {
    let archiveDirectory: URL
    let reportURL: URL
    let reportSHA256: String
}

private struct PrejournalRecoveryInspection: Equatable {
    let directoryIdentity: PrejournalRecoveryItemIdentity
    let ownerIdentity: PrejournalRecoveryItemIdentity
    let ownerData: Data
    let owner: SSHOwnerMarker
    let muxCheckStatus: Int32

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.directoryIdentity == rhs.directoryIdentity
            && lhs.ownerIdentity == rhs.ownerIdentity
            && lhs.ownerData == rhs.ownerData
            && lhs.owner.operationID == rhs.owner.operationID
            && lhs.owner.manifestSHA256 == rhs.owner.manifestSHA256
            && lhs.owner.host == rhs.owner.host
            && lhs.owner.token == rhs.owner.token
            && lhs.owner.purpose == rhs.owner.purpose
            && lhs.owner.pid == rhs.owner.pid
            && lhs.muxCheckStatus == rhs.muxCheckStatus
    }
}

private struct MigrationSourceSnapshot: Equatable {
    let connectionSHA256: String
    let projectSHA256ByID: [UUID: String]
}

private final class ProcessDataCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?

    func store(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func load() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct OwnedSSHMaster {
    let directory: URL
    let controlPath: String
    let host: String
    let token: UUID
    let pid: Int32
    let purpose: SSHMasterPurpose
    let operationID: UUID
    let manifestSHA256: String
}

@main
struct BessieMigrationTool {
    static func main() {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count == 4, arguments[2] == "--manifest" else {
                throw MigrationToolError.usage
            }
            let command = arguments[1]
            let manifestURL = URL(fileURLWithPath: arguments[3])
            guard manifestURL.path == arguments[3] else { throw MigrationToolError.usage }
            try requireCanonicalRegularFile(manifestURL, label: "migration manifest")
            try requirePrivateOwnedRegularFile(manifestURL, label: "migration manifest")
            try requireOwnedSafeDirectory(manifestURL.deletingLastPathComponent(), label: "migration manifest parent")
            let (manifest, manifestData) = try BessieProjectTargetMigration.decodeManifest(at: manifestURL)
            guard manifest.expectedProjectCount == 18 else {
                throw BessieProjectTargetMigrationError.invalidManifest(
                    "This deployment operator requires exactly 18 Projects, not \(manifest.expectedProjectCount)."
                )
            }
            let localValidator = BessieProjectTargetMigration(remoteInspector: .init { path in
                throw BessieProjectTargetMigrationError.unsafeRemotePath(
                    "Unexpected remote inspection during local envelope validation for \(path)."
                )
            })
            try localValidator.validateLocalEnvelope(manifest: manifest)

            if command == "status" {
                try withExclusiveOperationLocks(manifest: manifest) {
                    try requireBessieStopped()
                    try localValidator.validateLocalEnvelope(manifest: manifest)
                    let journal = try validateJournalLocally(manifest: manifest, manifestData: manifestData)
                    guard journal.phase == .readyForRelaunch,
                          journal.sshMasterClosedAt != nil else {
                        throw BessieProjectTargetMigrationError.auditFailed("Migration has not reached SSH-closed readyForRelaunch state.")
                    }
                    try verifyReadyForRelaunch(
                        journal,
                        manifest: manifest,
                        manifestData: manifestData
                    )
                    printSummary(journal, journalPath: manifest.journalPath)
                }
                return
            }

            guard ["preflight", "recover-prejournal", "apply", "resume", "rollback", "audit"].contains(command) else {
                throw MigrationToolError.usage
            }
            try withExclusiveOperationLocks(manifest: manifest) {
                try requireBessieStopped()
                try localValidator.validateLocalEnvelope(manifest: manifest)
                switch command {
                case "recover-prejournal":
                    try requireActiveMarker(manifest: manifest, manifestData: manifestData)
                    try requireAbsent(
                        URL(fileURLWithPath: manifest.journalPath),
                        label: "migration journal"
                    )
                    let target = try loadTarget(manifest: manifest, expectedHost: nil)
                    let activeMarkerURL = BessieConfigurationLease.activeMigrationMarkerURL(
                        for: URL(fileURLWithPath: manifest.connectionsPath)
                    )
                    let activeMarkerData = try Data(contentsOf: activeMarkerURL)
                    let sourceSnapshot = try requireManifestSourcesUnchanged(manifest)
                    let sourceDirectory = ownedMasterDirectory(manifest: manifest, purpose: .migration)
                    let operationDirectory = manifestURL.deletingLastPathComponent()
                    let result = try archiveInertPrejournalEvidence(
                        sourceDirectory: sourceDirectory,
                        controlPath: sourceDirectory.appendingPathComponent("control.sock").path,
                        archiveDirectory: operationDirectory.appendingPathComponent(
                            "canonical-prejournal-recovery",
                            isDirectory: true
                        ),
                        activeMarkerURL: activeMarkerURL,
                        activeMarkerData: activeMarkerData,
                        expectation: .init(
                            operationID: manifest.operationID,
                            manifestSHA256: BessieProjectTargetMigration.sha256(manifestData),
                            host: try Required.unwrap(target.sshHost),
                            purpose: .migration
                        ),
                        inspectProcesses: { try requireNoSSHProcess(controlPath: $0) },
                        muxCheck: {
                            try runControlSSH(host: $1, controlPath: $0, operation: "check").status
                        },
                        requireSourcesUnchanged: {
                            guard try requireManifestSourcesUnchanged(manifest) == sourceSnapshot else {
                                throw BessieProjectTargetMigrationError.sourceDrift(
                                    "Connection or Project source bytes changed during pre-journal recovery."
                                )
                            }
                        },
                        requireJournalAbsent: {
                            try requireAbsent(
                                URL(fileURLWithPath: manifest.journalPath),
                                label: "migration journal"
                            )
                        }
                    )
                    print("operation_id=\(manifest.operationID.uuidString)")
                    print("phase=prejournalRecovered")
                    print("active_marker_retained=true")
                    print("recovery_report=\(result.reportURL.path)")
                    print("recovery_report_sha256=\(result.reportSHA256)")
                case "preflight":
                    if FileManager.default.fileExists(atPath: manifest.journalPath) {
                        let existing = try validateJournalLocally(manifest: manifest, manifestData: manifestData)
                        throw BessieProjectTargetMigrationError.activeJournal(
                            "Its phase is \(existing.phase.rawValue). Use resume, rollback, audit, or status; existing operation evidence was left untouched."
                        )
                    }
                    try establishActiveMarker(manifest: manifest, manifestData: manifestData)
                    var master: OwnedSSHMaster?
                    do {
                        let target = try loadTarget(manifest: manifest, expectedHost: nil)
                        let startedMaster = try startOwnedMaster(
                            manifest: manifest,
                            manifestData: manifestData,
                            host: try Required.unwrap(target.sshHost)
                        )
                        master = startedMaster
                        let journal = try makeMigration(host: startedMaster.host, controlPath: startedMaster.controlPath).preflight(
                            manifest: manifest,
                            manifestData: manifestData,
                            manifestPath: manifestURL.path,
                            sshControlPath: startedMaster.controlPath,
                            sshHost: startedMaster.host,
                            sshMasterPID: startedMaster.pid,
                            sshOwnerToken: startedMaster.token
                        )
                        printSummary(journal, journalPath: manifest.journalPath)
                    } catch {
                        switch try journalPublicationState(at: URL(fileURLWithPath: manifest.journalPath)) {
                        case .published:
                            // The journal owns the active marker and SSH evidence from this point.
                            // Preserve all three so resume, rollback, or audit can recover safely.
                            break
                        case .absent:
                            if let master {
                                try closeOwnedMaster(master)
                            } else if try journalPublicationState(
                                at: ownedMasterDirectory(manifest: manifest, purpose: .migration)
                            ) == .published {
                                // startOwnedMaster can fail after publishing ownership evidence but
                                // before returning its handle. Keep the startup gate for recovery.
                                break
                            }
                            try removeActiveMarker(manifest: manifest, manifestData: manifestData)
                        }
                        throw error
                    }
                case "apply", "resume":
                    try requireActiveMarker(manifest: manifest, manifestData: manifestData)
                    var journal = try validateJournalLocally(manifest: manifest, manifestData: manifestData)
                    _ = try loadTarget(manifest: manifest, expectedHost: journal.sshHost)
                    journal = try ensureOwnedMaster(
                        journal,
                        manifest: manifest,
                        manifestData: manifestData
                    )
                    let result = try makeMigration(host: journal.sshHost, controlPath: journal.sshControlPath).apply(
                        manifest: manifest,
                        manifestData: manifestData,
                        resume: command == "resume"
                    )
                    printSummary(result, journalPath: manifest.journalPath)
                case "rollback":
                    var journal = try validateJournalLocally(manifest: manifest, manifestData: manifestData)
                    let markerURL = BessieConfigurationLease.activeMigrationMarkerURL(
                        for: URL(fileURLWithPath: manifest.connectionsPath)
                    )
                    if !FileManager.default.fileExists(atPath: markerURL.path) {
                        guard journal.phase == .readyForRelaunch,
                              journal.terminalOutcome == .migrated else {
                            throw MigrationToolError.lockUnavailable(markerURL.path)
                        }
                        try establishActiveMarker(manifest: manifest, manifestData: manifestData)
                        journal = try validateJournalLocally(manifest: manifest, manifestData: manifestData)
                    }
                    try requireActiveMarker(manifest: manifest, manifestData: manifestData)
                    let result = try makeMigration(host: journal.sshHost, controlPath: journal.sshControlPath).rollback(
                        manifest: manifest,
                        manifestData: manifestData
                    )
                    printSummary(result, journalPath: manifest.journalPath)
                case "audit":
                    try requireActiveMarker(manifest: manifest, manifestData: manifestData)
                    var result = try validateJournalLocally(manifest: manifest, manifestData: manifestData)
                    if result.phase == .readyForRelaunch {
                        try verifyReadyForRelaunch(
                            result,
                            manifest: manifest,
                            manifestData: manifestData
                        )
                        try removeActiveMarker(manifest: manifest, manifestData: manifestData)
                        printSummary(result, journalPath: manifest.journalPath)
                        break
                    }
                    if result.phase != .closingSSHMaster {
                        if result.phase == .applied || result.phase == .success {
                            _ = try loadTarget(manifest: manifest, expectedHost: result.sshHost)
                            result = try ensureOwnedMaster(
                                result,
                                manifest: manifest,
                                manifestData: manifestData
                            )
                        }
                        let migration = makeMigration(host: result.sshHost, controlPath: result.sshControlPath)
                        result = try migration.audit(manifest: manifest, manifestData: manifestData)
                        result = try migration.recordSSHMasterClosing(
                            manifest: manifest,
                            manifestData: manifestData
                        )
                    }
                    try closeJournalMasterIfPresent(result)
                    result = try makeMigration(host: result.sshHost, controlPath: result.sshControlPath)
                        .recordSSHMasterClosed(manifest: manifest, manifestData: manifestData)
                    try verifyReadyForRelaunch(
                        result,
                        manifest: manifest,
                        manifestData: manifestData
                    )
                    try removeActiveMarker(manifest: manifest, manifestData: manifestData)
                    printSummary(result, journalPath: manifest.journalPath)
                default:
                    throw MigrationToolError.usage
                }
            }
        } catch {
            FileHandle.standardError.write(Data("BessieMigrationTool: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func loadTarget(
        manifest: BessieProjectTargetMigrationManifest,
        expectedHost: String?
    ) throws -> BessieConnectionDefinition {
        let state = try BessieConnectionStore(url: URL(fileURLWithPath: manifest.connectionsPath)).load()
        guard let target = state.connections.first(where: { $0.id == manifest.targetConnectionID }),
              target.kind == .ssh,
              target.enabled,
              let host = target.sshHost,
              expectedHost == nil || host == expectedHost,
              (try? target.validated()) != nil else {
            throw MigrationToolError.targetUnavailable(manifest.targetConnectionID)
        }
        return target
    }

    private static func makeMigration(host: String, controlPath: String) -> BessieProjectTargetMigration {
        let client = SSHRemoteFileClient(access: .init(
            host: host,
            controlPath: controlPath,
            requireControlMaster: true
        ))
        return BessieProjectTargetMigration(remoteInspector: .init { path in
            let stat = try client.stat(path)
            let canonical = try client.canonicalPath(path)
            return .init(
                requestedPath: path,
                canonicalPath: canonical,
                exists: stat.exists,
                isDirectory: stat.isDirectory,
                isSymbolicLink: stat.isSymbolicLink
            )
        })
    }

    private static func validateJournalLocally(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        let localValidator = BessieProjectTargetMigration(remoteInspector: .init { path in
            throw BessieProjectTargetMigrationError.unsafeRemotePath(
                "Unexpected remote inspection while validating local journal path \(path)."
            )
        })
        return try localValidator.validateJournal(manifest: manifest, manifestData: manifestData)
    }

    private static func verifyReadyForRelaunch(
        _ journal: BessieProjectTargetMigrationJournal,
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws {
        guard try journalPublicationState(at: URL(fileURLWithPath: journal.sshControlPath)) == .absent else {
            throw BessieProjectTargetMigrationError.auditFailed(
                "The journal-owned migration SSH control path still exists after its recorded close."
            )
        }
        if journal.terminalOutcome == .migrated {
            try withVerificationMaster(
                manifest: manifest,
                manifestData: manifestData,
                host: journal.sshHost,
                body: { master in
                    _ = try makeMigration(host: journal.sshHost, controlPath: master.controlPath)
                        .verifyReadyForRelaunch(manifest: manifest, manifestData: manifestData)
                }
            )
        } else {
            _ = try BessieProjectTargetMigration(remoteInspector: .init { path in
                throw BessieProjectTargetMigrationError.unsafeRemotePath(
                    "Unexpected remote inspection of rolled-back state for \(path)."
                )
            }).verifyReadyForRelaunch(manifest: manifest, manifestData: manifestData)
        }
    }

    private static func ensureOwnedMaster(
        _ journal: BessieProjectTargetMigrationJournal,
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws -> BessieProjectTargetMigrationJournal {
        do {
            try verifyOwnedMaster(journal)
            return journal
        } catch {
            guard processIsGone(journal.sshMasterPID) else { throw error }
            let directory = URL(fileURLWithPath: journal.sshControlPath).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: directory.path) {
                try requirePrivateOwnedDirectory(directory, label: "migration SSH control directory")
                let allowedItems = Set(["owner.json", "control.sock"])
                let items = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
                guard items.isSubset(of: allowedItems) else {
                    throw MigrationToolError.ownership(
                        "The dead SSH master directory contains unowned artifacts."
                    )
                }
                let ownerURL = directory.appendingPathComponent("owner.json")
                try requirePrivateOwnedRegularFile(ownerURL, label: "migration SSH owner record")
                var owner = try JSONDecoder().decode(SSHOwnerMarker.self, from: Data(contentsOf: ownerURL))
                guard owner.operationID == journal.operationID,
                      owner.manifestSHA256 == journal.manifestSHA256,
                      owner.host == journal.sshHost,
                      owner.token == journal.sshOwnerToken,
                      owner.purpose == .migration else {
                    throw MigrationToolError.ownership(
                        "A replacement SSH owner record is incomplete or not bound to the journal operation."
                    )
                }
                if FileManager.default.fileExists(atPath: journal.sshControlPath) {
                    guard items == Set(["owner.json", "control.sock"]) else {
                        throw MigrationToolError.ownership(
                            "The replacement SSH directory has incomplete socket evidence."
                        )
                    }
                    try requireOwnedSocket(URL(fileURLWithPath: journal.sshControlPath))
                    do {
                        let replacementPID = try checkedMasterPID(
                            host: journal.sshHost,
                            controlPath: journal.sshControlPath
                        )
                        guard replacementPID != journal.sshMasterPID,
                              owner.pid == nil || owner.pid == replacementPID else {
                            throw MigrationToolError.ownership(
                                "The replacement SSH socket PID does not match its owner evidence."
                            )
                        }
                        if owner.pid == nil {
                            owner.pid = replacementPID
                            try writeOwner(owner, to: ownerURL)
                        }
                        return try makeMigration(host: journal.sshHost, controlPath: journal.sshControlPath)
                            .recordSSHMasterOwnership(
                                manifest: manifest,
                                manifestData: manifestData,
                                sshMasterPID: replacementPID,
                                sshOwnerToken: journal.sshOwnerToken
                            )
                    } catch let ownership as MigrationToolError {
                        if case .ownership = ownership { throw ownership }
                        guard owner.pid.map(processIsGone) ?? false else { throw ownership }
                    } catch {
                        guard owner.pid.map(processIsGone) ?? false else { throw error }
                    }
                } else {
                    guard let ownerPID = owner.pid, processIsGone(ownerPID) else {
                        throw MigrationToolError.ownership(
                            "The pending replacement SSH owner has no complete, proven-dead process and socket state."
                        )
                    }
                }
                try FileManager.default.removeItem(at: directory)
                try syncDirectory(directory.deletingLastPathComponent())
            }
            let replacement = try startOwnedMaster(
                manifest: manifest,
                manifestData: manifestData,
                host: journal.sshHost,
                ownerToken: journal.sshOwnerToken
            )
            do {
                return try makeMigration(host: journal.sshHost, controlPath: replacement.controlPath)
                    .recordSSHMasterOwnership(
                    manifest: manifest,
                    manifestData: manifestData,
                    sshMasterPID: replacement.pid,
                    sshOwnerToken: replacement.token
                )
            } catch {
                try? closeOwnedMaster(replacement)
                throw error
            }
        }
    }

    private static func withExclusiveOperationLocks<T>(
        manifest: BessieProjectTargetMigrationManifest,
        _ body: () throws -> T
    ) throws -> T {
        let configurationLease = try BessieConfigurationLease.acquireExclusive(
            for: URL(fileURLWithPath: manifest.connectionsPath)
        )
        return try withExtendedLifetime(configurationLease) {
            let operationLock = URL(fileURLWithPath: manifest.journalPath).appendingPathExtension("operation.lock")
            let projectLock = URL(fileURLWithPath: manifest.projectsPath, isDirectory: true).appendingPathComponent(".store.lock")
            let operationDescriptor = try acquireLock(operationLock)
            defer { flock(operationDescriptor, LOCK_UN); close(operationDescriptor) }
            let projectDescriptor = try acquireLock(projectLock)
            defer { flock(projectDescriptor, LOCK_UN); close(projectDescriptor) }
            return try body()
        }
    }

    private static func establishActiveMarker(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws {
        let url = BessieConfigurationLease.activeMigrationMarkerURL(
            for: URL(fileURLWithPath: manifest.connectionsPath)
        )
        let expected = ActiveMigrationMarker(
            operationID: manifest.operationID,
            manifestSHA256: BessieProjectTargetMigration.sha256(manifestData),
            journalPath: manifest.journalPath
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try requirePrivateOwnedRegularFile(url, label: "active migration marker")
            let existing = try JSONDecoder().decode(ActiveMigrationMarker.self, from: Data(contentsOf: url))
            guard existing.operationID == expected.operationID,
                  existing.manifestSHA256 == expected.manifestSHA256,
                  existing.journalPath == expected.journalPath else {
                throw MigrationToolError.lockUnavailable(url.path)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writePrivateAtomically(encoder.encode(expected), to: url)
    }

    private static func requireActiveMarker(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws {
        let url = BessieConfigurationLease.activeMigrationMarkerURL(
            for: URL(fileURLWithPath: manifest.connectionsPath)
        )
        try requirePrivateOwnedRegularFile(url, label: "active migration marker")
        let marker = try JSONDecoder().decode(ActiveMigrationMarker.self, from: Data(contentsOf: url))
        guard marker.operationID == manifest.operationID,
              marker.manifestSHA256 == BessieProjectTargetMigration.sha256(manifestData),
              marker.journalPath == manifest.journalPath else {
            throw MigrationToolError.lockUnavailable(url.path)
        }
    }

    private static func removeActiveMarker(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data
    ) throws {
        try requireActiveMarker(manifest: manifest, manifestData: manifestData)
        let url = BessieConfigurationLease.activeMigrationMarkerURL(
            for: URL(fileURLWithPath: manifest.connectionsPath)
        )
        try FileManager.default.removeItem(at: url)
        try syncDirectory(url.deletingLastPathComponent())
    }

    private static func acquireLock(_ url: URL) throws -> Int32 {
        try requireOwnedSafeDirectory(url.deletingLastPathComponent(), label: "operation lock parent")
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var details = stat()
        guard fstat(descriptor, &details) == 0, (details.st_mode & S_IFMT) == S_IFREG,
              details.st_uid == geteuid(), details.st_nlink == 1,
              (details.st_mode & 0o077) == 0,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw MigrationToolError.lockUnavailable(url.path)
        }
        return descriptor
    }

    private static func requireBessieStopped() throws {
        let result = try run("/usr/bin/pgrep", ["-x", "BessieApp"])
        if result.status == 0 {
            let pids = result.output.split(whereSeparator: \.isWhitespace).joined(separator: ", ")
            throw MigrationToolError.bessieRunning(pids)
        }
        guard result.status == 1 else {
            throw MigrationToolError.bessieRunning("could not verify process ownership (pgrep status \(result.status))")
        }
    }

    private static func startOwnedMaster(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data,
        host: String,
        ownerToken: UUID? = nil,
        purpose: SSHMasterPurpose = .migration
    ) throws -> OwnedSSHMaster {
        let directory = ownedMasterDirectory(manifest: manifest, purpose: purpose)
        let ownerURL = directory.appendingPathComponent("owner.json")
        let controlPath = directory.appendingPathComponent("control.sock").path
        let manifestHash = BessieProjectTargetMigration.sha256(manifestData)

        if FileManager.default.fileExists(atPath: directory.path) {
            try requirePrivateOwnedDirectory(directory, label: "migration SSH control directory")
            try requirePrivateOwnedRegularFile(ownerURL, label: "migration SSH owner record")
            let contents = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
            guard contents.isSubset(of: Set(["owner.json", "control.sock"])) else {
                throw MigrationToolError.ownership("The SSH control directory contains unowned artifacts.")
            }
            guard var owner = try? JSONDecoder().decode(SSHOwnerMarker.self, from: Data(contentsOf: ownerURL)),
                  owner.operationID == manifest.operationID,
                  owner.manifestSHA256 == manifestHash,
                  owner.host == host,
                  owner.purpose == purpose,
                  ownerToken == nil || owner.token == ownerToken else {
                throw MigrationToolError.ownership("Refusing an existing unproven control directory at \(directory.path).")
            }
            if FileManager.default.fileExists(atPath: controlPath) {
                guard contents == Set(["owner.json", "control.sock"]) else {
                    throw MigrationToolError.ownership("The SSH control directory has incomplete socket evidence.")
                }
                try requireOwnedSocket(URL(fileURLWithPath: controlPath))
                let checkedPID = try resolveSocketOwnerPID(
                    owner: &owner,
                    directoryContents: contents,
                    checkPID: { try checkedMasterPID(host: host, controlPath: controlPath) },
                    persistOwner: { try writeOwner($0, to: ownerURL) }
                )
                let existing = OwnedSSHMaster(
                    directory: directory,
                    controlPath: controlPath,
                    host: host,
                    token: owner.token,
                    pid: checkedPID,
                    purpose: purpose,
                    operationID: manifest.operationID,
                    manifestSHA256: manifestHash
                )
                try verifyMaster(existing)
                return existing
            } else {
                guard let ownerPID = owner.pid,
                      processIsGone(ownerPID),
                      contents == Set(["owner.json"]) else {
                    throw MigrationToolError.ownership(
                        "An existing SSH owner record has no socket and no complete, proven-dead process state."
                    )
                }
                try FileManager.default.removeItem(at: directory)
                try syncDirectory(directory.deletingLastPathComponent())
            }
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let token = ownerToken ?? UUID()
        try writeOwner(.init(
            operationID: manifest.operationID,
            manifestSHA256: manifestHash,
            host: host,
            token: token,
            purpose: purpose,
            pid: nil
        ), to: ownerURL)
        let result = try runSSH([
            "-M", "-S", controlPath,
            "-o", "ControlPersist=no",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-fnNT", host,
        ])
        guard result.status == 0 else { throw MigrationToolError.ssh(result.error) }
        let pid = try checkedMasterPID(host: host, controlPath: controlPath)
        try writeOwner(.init(
            operationID: manifest.operationID,
            manifestSHA256: manifestHash,
            host: host,
            token: token,
            purpose: purpose,
            pid: pid
        ), to: ownerURL)
        return .init(
            directory: directory,
            controlPath: controlPath,
            host: host,
            token: token,
            pid: pid,
            purpose: purpose,
            operationID: manifest.operationID,
            manifestSHA256: manifestHash
        )
    }

    private static func ownedMasterDirectory(
        manifest: BessieProjectTargetMigrationManifest,
        purpose: SSHMasterPurpose
    ) -> URL {
        if purpose == .migration {
            return URL(
                fileURLWithPath: BessieProjectTargetMigration.migrationSSHControlPath(
                    operationID: manifest.operationID
                )
            ).deletingLastPathComponent()
        }
        let compactID = manifest.operationID.uuidString.replacingOccurrences(of: "-", with: "")
        return URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(".bessie-migration-\(compactID)-\(purpose.directorySuffix)", isDirectory: true)
    }

    private static func verifyOwnedMaster(_ journal: BessieProjectTargetMigrationJournal) throws {
        let controlURL = URL(fileURLWithPath: journal.sshControlPath)
        let directory = controlURL.deletingLastPathComponent()
        try requirePrivateOwnedDirectory(directory, label: "migration SSH control directory")
        try requirePrivateOwnedRegularFile(
            directory.appendingPathComponent("owner.json"),
            label: "migration SSH owner record"
        )
        try requireOwnedSocket(controlURL)
        guard controlURL.lastPathComponent == "control.sock",
              let data = try? Data(contentsOf: directory.appendingPathComponent("owner.json")),
              let owner = try? JSONDecoder().decode(SSHOwnerMarker.self, from: data),
              owner.operationID == journal.operationID,
              owner.manifestSHA256 == journal.manifestSHA256,
              owner.host == journal.sshHost,
              owner.token == journal.sshOwnerToken,
              owner.purpose == .migration,
              owner.pid == journal.sshMasterPID else {
            throw MigrationToolError.ownership("Journal and control-directory owner marker differ.")
        }
        try verifyMaster(.init(
            directory: directory,
            controlPath: journal.sshControlPath,
            host: journal.sshHost,
            token: journal.sshOwnerToken,
            pid: journal.sshMasterPID,
            purpose: .migration,
            operationID: journal.operationID,
            manifestSHA256: journal.manifestSHA256
        ))
    }

    private static func verifyMaster(_ master: OwnedSSHMaster) throws {
        try requirePrivateOwnedDirectory(master.directory, label: "migration SSH control directory")
        try requireOwnedSocket(URL(fileURLWithPath: master.controlPath))
        try requireMatchingMasterPID(
            recorded: master.pid,
            checked: try checkedMasterPID(host: master.host, controlPath: master.controlPath)
        )
    }

    private static func checkedMasterPID(host: String, controlPath: String) throws -> Int32 {
        let result = try runControlSSH(host: host, controlPath: controlPath, operation: "check")
        guard result.status == 0 else { throw MigrationToolError.ssh(result.error) }
        let combined = result.output + "\n" + result.error
        guard let range = combined.range(of: #"pid=([0-9]+)"#, options: .regularExpression),
              let pid = Int32(combined[range].dropFirst(4)) else {
            throw MigrationToolError.ssh("Could not parse the owned master PID from ssh -O check.")
        }
        return pid
    }

    private static func closeJournalMasterIfPresent(_ journal: BessieProjectTargetMigrationJournal) throws {
        let controlURL = URL(fileURLWithPath: journal.sshControlPath)
        let directory = controlURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: journal.sshControlPath) {
            do {
                try verifyOwnedMaster(journal)
                try closeOwnedMaster(.init(
                    directory: directory,
                    controlPath: journal.sshControlPath,
                    host: journal.sshHost,
                    token: journal.sshOwnerToken,
                    pid: journal.sshMasterPID,
                    purpose: .migration,
                    operationID: journal.operationID,
                    manifestSHA256: journal.manifestSHA256
                ))
            } catch {
                guard processIsGone(journal.sshMasterPID) else { throw error }
                try verifyOwnerMarker(journal, directory: directory)
                try requireOwnedSocket(controlURL)
                let items = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
                guard items == Set(["owner.json", "control.sock"]) else {
                    throw MigrationToolError.ownership(
                        "The stale SSH master directory contains unknown artifacts."
                    )
                }
                let check = try runControlSSH(
                    host: journal.sshHost,
                    controlPath: journal.sshControlPath,
                    operation: "check"
                )
                guard check.status != 0 else {
                    throw MigrationToolError.ownership(
                        "The recorded SSH PID is gone but its control socket still reaches a live master."
                    )
                }
                try FileManager.default.removeItem(at: directory)
                try syncDirectory(directory.deletingLastPathComponent())
            }
        } else {
            guard processIsGone(journal.sshMasterPID) else {
                throw MigrationToolError.ownership("Recorded SSH master still runs but its control socket is missing.")
            }
            if FileManager.default.fileExists(atPath: directory.path) {
                try verifyOwnerMarker(journal, directory: directory)
                guard Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == Set(["owner.json"]) else {
                    throw MigrationToolError.ownership(
                        "The SSH close-recovery directory contains unknown artifacts."
                    )
                }
                try FileManager.default.removeItem(at: directory)
                try syncDirectory(directory.deletingLastPathComponent())
            }
        }
    }

    private static func closeOwnedMaster(_ master: OwnedSSHMaster) throws {
        try requirePrivateOwnedDirectory(master.directory, label: "migration SSH control directory")
        try verifyOwnerMarker(master)
        try requireExactSSHDirectoryInventory(
            at: master.directory,
            expected: Set(["owner.json", "control.sock"])
        )
        try requireOwnedSocket(URL(fileURLWithPath: master.controlPath))
        try verifyMaster(master)
        let result = try runControlSSH(host: master.host, controlPath: master.controlPath, operation: "exit")
        guard result.status == 0 else { throw MigrationToolError.ssh(result.error) }
        for _ in 0..<40 where FileManager.default.fileExists(atPath: master.controlPath) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !FileManager.default.fileExists(atPath: master.controlPath) else {
            throw MigrationToolError.ssh("Control socket remained after the owned master acknowledged exit.")
        }
        for _ in 0..<40 where !processIsGone(master.pid) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard processIsGone(master.pid) else {
            throw MigrationToolError.ssh("Owned SSH master process remained after it acknowledged exit.")
        }
        try verifyOwnerMarker(master)
        try requireExactSSHDirectoryInventory(at: master.directory, expected: Set(["owner.json"]))
        try FileManager.default.removeItem(at: master.directory)
        try syncDirectory(master.directory.deletingLastPathComponent())
    }

    private static func withVerificationMaster<T>(
        manifest: BessieProjectTargetMigrationManifest,
        manifestData: Data,
        host: String,
        body: (OwnedSSHMaster) throws -> T
    ) throws -> T {
        let master = try startOwnedMaster(
            manifest: manifest,
            manifestData: manifestData,
            host: host,
            purpose: .verification
        )
        do {
            let result = try body(master)
            try closeOwnedMaster(master)
            return result
        } catch {
            // Best effort only: if close fails, deterministic owner evidence remains for
            // the next status/audit invocation to adopt or reject without guessing.
            try? closeOwnedMaster(master)
            throw error
        }
    }

    private static func writeOwner(_ marker: SSHOwnerMarker, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writePrivateAtomically(encoder.encode(marker), to: url)
    }

    private static func verifyOwnerMarker(
        _ journal: BessieProjectTargetMigrationJournal,
        directory: URL
    ) throws {
        try requirePrivateOwnedDirectory(directory, label: "migration SSH control directory")
        let ownerURL = directory.appendingPathComponent("owner.json")
        try requirePrivateOwnedRegularFile(ownerURL, label: "migration SSH owner record")
        let data = try Data(contentsOf: ownerURL)
        let owner = try JSONDecoder().decode(SSHOwnerMarker.self, from: data)
        guard owner.operationID == journal.operationID,
              owner.manifestSHA256 == journal.manifestSHA256,
              owner.host == journal.sshHost,
              owner.token == journal.sshOwnerToken,
              owner.purpose == .migration,
              owner.pid == journal.sshMasterPID else {
            throw MigrationToolError.ownership("Journal and SSH owner marker differ during close recovery.")
        }
    }

    private static func verifyOwnerMarker(_ master: OwnedSSHMaster) throws {
        try requirePrivateOwnedDirectory(master.directory, label: "migration SSH control directory")
        let ownerURL = master.directory.appendingPathComponent("owner.json")
        try requirePrivateOwnedRegularFile(ownerURL, label: "migration SSH owner record")
        let owner = try JSONDecoder().decode(SSHOwnerMarker.self, from: Data(contentsOf: ownerURL))
        guard owner.operationID == master.operationID,
              owner.manifestSHA256 == master.manifestSHA256,
              owner.host == master.host,
              owner.token == master.token,
              owner.purpose == master.purpose,
              owner.pid == master.pid else {
            throw MigrationToolError.ownership("SSH master and owner marker differ during close.")
        }
    }

    private static func processIsGone(_ pid: Int32) -> Bool {
        errno = 0
        return kill(pid, 0) != 0 && errno == ESRCH
    }

    static func resolveSocketOwnerPID(
        owner: inout SSHOwnerMarker,
        directoryContents: Set<String>,
        checkPID: () throws -> Int32,
        persistOwner: (SSHOwnerMarker) throws -> Void
    ) throws -> Int32 {
        guard directoryContents == Set(["owner.json", "control.sock"]) else {
            throw MigrationToolError.ownership("The SSH control directory has incomplete socket evidence.")
        }
        let checkedPID = try checkPID()
        if let ownerPID = owner.pid {
            guard ownerPID == checkedPID else {
                throw MigrationToolError.ownership("The SSH socket PID differs from its owner record.")
            }
        } else {
            owner.pid = checkedPID
            try persistOwner(owner)
        }
        return checkedPID
    }

    static func requireExactSSHDirectoryInventory(at directory: URL, expected: Set<String>) throws {
        guard Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == expected else {
            throw MigrationToolError.ownership(
                "The SSH control directory contains unknown or incomplete evidence."
            )
        }
    }

    static func requireMatchingMasterPID(recorded: Int32, checked: Int32) throws {
        guard recorded == checked else {
            throw MigrationToolError.ownership("The operation-owned SSH master PID or socket changed.")
        }
    }

    static func archiveInertPrejournalEvidence(
        sourceDirectory: URL,
        controlPath: String,
        archiveDirectory: URL,
        activeMarkerURL: URL,
        activeMarkerData: Data,
        expectation: PrejournalRecoveryExpectation,
        inspectProcesses: (String) throws -> Void,
        muxCheck: (String, String) throws -> Int32,
        requireSourcesUnchanged: () throws -> Void,
        requireJournalAbsent: () throws -> Void,
        afterGatePublished: () throws -> Void = {},
        afterOwnerUnlinked: () throws -> Void = {}
    ) throws -> PrejournalRecoveryResult {
        guard sourceDirectory.appendingPathComponent("control.sock").path == controlPath else {
            throw MigrationToolError.ownership("Pre-journal control path does not match its owner directory.")
        }
        try requireJournalAbsent()
        try requireSourcesUnchanged()
        try requirePrivateOwnedRegularFile(activeMarkerURL, label: "active migration marker")
        try requireCanonicalRegularFile(activeMarkerURL, label: "active migration marker")
        guard try Data(contentsOf: activeMarkerURL) == activeMarkerData else {
            throw MigrationToolError.ownership("Active migration marker changed before pre-journal recovery.")
        }
        let ownerArchiveURL = archiveDirectory.appendingPathComponent("owner.json")
        let terminalURL = archiveDirectory.appendingPathComponent("recovery.json")
        let parent = archiveDirectory.deletingLastPathComponent()
        try requireOwnedSafeDirectory(
            parent,
            label: "pre-journal recovery archive parent"
        )
        let first: PrejournalRecoveryInspection
        let gateData: Data
        if FileManager.default.fileExists(atPath: archiveDirectory.path) {
            (first, gateData) = try validatePublishedPrejournalGate(
                sourceDirectory: sourceDirectory,
                controlPath: controlPath,
                archiveDirectory: archiveDirectory,
                activeMarkerData: activeMarkerData,
                expectation: expectation
            )
        } else {
            try rejectIncompleteRecoveryStaging(for: archiveDirectory)
            first = try inspectInertPrejournalEvidence(
                sourceDirectory: sourceDirectory,
                controlPath: controlPath,
                expectation: expectation,
                inspectProcesses: inspectProcesses,
                muxCheck: muxCheck
            )
            let staging = parent.appendingPathComponent(
                ".\(archiveDirectory.lastPathComponent).staging-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: staging,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try syncDirectory(parent)
            try writePrivateAtomically(first.ownerData, to: staging.appendingPathComponent("owner.json"))
            try writePrivateAtomically(activeMarkerData, to: staging.appendingPathComponent("active-marker.json"))
            gateData = try encodeRecoveryReport(PrejournalRecoveryGateReport(
                schemaVersion: PrejournalRecoveryGateReport.currentSchemaVersion,
                operationID: expectation.operationID,
                manifestSHA256: expectation.manifestSHA256,
                host: expectation.host,
                purpose: expectation.purpose,
                ownerToken: first.owner.token,
                sourceDirectory: sourceDirectory.path,
                controlPath: controlPath,
                archiveDirectory: archiveDirectory.path,
                ownerSHA256: BessieProjectTargetMigration.sha256(first.ownerData),
                activeMarkerSHA256: BessieProjectTargetMigration.sha256(activeMarkerData),
                directoryIdentity: first.directoryIdentity,
                ownerIdentity: first.ownerIdentity,
                inventory: ["owner.json"],
                muxCheckStatus: first.muxCheckStatus,
                processInspection: "current-user process inventory complete; no matching ssh executable and control path",
                checkedAt: Date()
            ))
            try writePrivateAtomically(gateData, to: staging.appendingPathComponent("gate.json"))
            try syncDirectory(staging)
            guard renamex_np(staging.path, archiveDirectory.path, UInt32(RENAME_EXCL)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try syncDirectory(parent)
            _ = try validatePublishedPrejournalGate(
                sourceDirectory: sourceDirectory,
                controlPath: controlPath,
                archiveDirectory: archiveDirectory,
                activeMarkerData: activeMarkerData,
                expectation: expectation
            )
            try afterGatePublished()
        }

        try requireJournalAbsent()
        try requireSourcesUnchanged()
        guard try Data(contentsOf: activeMarkerURL) == activeMarkerData else {
            throw MigrationToolError.ownership("Active migration marker changed during pre-journal recovery.")
        }
        if FileManager.default.fileExists(atPath: terminalURL.path) {
            try requireAbsent(sourceDirectory, label: "recovered pre-journal owner directory")
            let terminalData = try validatePrejournalTerminalReport(
                terminalURL,
                expectation: expectation,
                first: first,
                activeMarkerData: activeMarkerData,
                gateData: gateData
            )
            return .init(
                archiveDirectory: archiveDirectory,
                reportURL: terminalURL,
                reportSHA256: BessieProjectTargetMigration.sha256(terminalData)
            )
        }

        var sourceDetails = stat()
        if lstat(sourceDirectory.path, &sourceDetails) == 0 {
            try requirePrivateOwnedDirectory(sourceDirectory, label: "pre-journal SSH owner directory")
            let inventory = Set(try FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path))
            if inventory == Set(["owner.json"]) {
                let second = try inspectInertPrejournalEvidence(
                    sourceDirectory: sourceDirectory,
                    controlPath: controlPath,
                    expectation: expectation,
                    inspectProcesses: inspectProcesses,
                    muxCheck: muxCheck
                )
                guard second == first,
                      try itemIdentity(sourceDirectory, expectedType: S_IFDIR) == first.directoryIdentity,
                      try itemIdentity(sourceDirectory.appendingPathComponent("owner.json"), expectedType: S_IFREG)
                        == first.ownerIdentity else {
                    throw MigrationToolError.ownership("Pre-journal owner evidence changed during recovery inspection.")
                }
                guard unlink(sourceDirectory.appendingPathComponent("owner.json").path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                try syncDirectory(sourceDirectory)
                try afterOwnerUnlinked()
            } else if !inventory.isEmpty {
                throw MigrationToolError.ownership(
                    "Pre-journal owner directory gained an unknown or late artifact; it was preserved."
                )
            }
            try requireExactSSHDirectoryInventory(at: sourceDirectory, expected: [])
            guard rmdir(sourceDirectory.path) == 0 else {
                throw MigrationToolError.ownership(
                    "Pre-journal owner directory could not be removed nonrecursively; late evidence was preserved."
                )
            }
            try syncDirectory(sourceDirectory.deletingLastPathComponent())
        } else if errno != ENOENT {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try requireAbsent(sourceDirectory, label: "recovered pre-journal owner directory")
        try requireJournalAbsent()
        try requireSourcesUnchanged()
        try requirePrivateOwnedRegularFile(activeMarkerURL, label: "active migration marker")
        guard try Data(contentsOf: activeMarkerURL) == activeMarkerData,
              try Data(contentsOf: ownerArchiveURL) == first.ownerData else {
            throw MigrationToolError.ownership("Recovery postconditions did not preserve marker and owner evidence.")
        }

        let terminalData = try encodeRecoveryReport(PrejournalRecoveryTerminalReport(
            schemaVersion: PrejournalRecoveryTerminalReport.currentSchemaVersion,
            operationID: expectation.operationID,
            manifestSHA256: expectation.manifestSHA256,
            ownerSHA256: BessieProjectTargetMigration.sha256(first.ownerData),
            activeMarkerSHA256: BessieProjectTargetMigration.sha256(activeMarkerData),
            gateReportSHA256: BessieProjectTargetMigration.sha256(gateData),
            sourceDirectoryRemoved: true,
            journalAbsent: true,
            activeMarkerRetained: true,
            sourcesUnchanged: true,
            completedAt: Date()
        ))
        try writePrivateAtomically(terminalData, to: terminalURL)
        try syncDirectory(archiveDirectory)
        return .init(
            archiveDirectory: archiveDirectory,
            reportURL: terminalURL,
            reportSHA256: BessieProjectTargetMigration.sha256(terminalData)
        )
    }

    private static func validatePublishedPrejournalGate(
        sourceDirectory: URL,
        controlPath: String,
        archiveDirectory: URL,
        activeMarkerData: Data,
        expectation: PrejournalRecoveryExpectation
    ) throws -> (PrejournalRecoveryInspection, Data) {
        try requirePrivateOwnedDirectory(archiveDirectory, label: "pre-journal recovery archive")
        guard archiveDirectory.standardizedFileURL.path
                == archiveDirectory.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw MigrationToolError.ownership("Pre-journal recovery archive is not canonical.")
        }
        let inventory = Set(try FileManager.default.contentsOfDirectory(atPath: archiveDirectory.path))
        guard inventory == Set(["owner.json", "active-marker.json", "gate.json"])
                || inventory == Set(["owner.json", "active-marker.json", "gate.json", "recovery.json"]) else {
            throw MigrationToolError.ownership("Pre-journal recovery archive has unknown or incomplete evidence.")
        }
        let ownerURL = archiveDirectory.appendingPathComponent("owner.json")
        let markerURL = archiveDirectory.appendingPathComponent("active-marker.json")
        let gateURL = archiveDirectory.appendingPathComponent("gate.json")
        for (url, label) in [
            (ownerURL, "archived pre-journal owner"),
            (markerURL, "archived active marker"),
            (gateURL, "pre-journal recovery gate"),
        ] {
            try requirePrivateOwnedRegularFile(url, label: label)
            try requireCanonicalRegularFile(url, label: label)
        }
        let ownerData = try Data(contentsOf: ownerURL)
        let markerData = try Data(contentsOf: markerURL)
        let gateData = try Data(contentsOf: gateURL)
        let owner = try JSONDecoder().decode(SSHOwnerMarker.self, from: ownerData)
        let gate: PrejournalRecoveryGateReport = try decodeRecoveryReport(gateData)
        guard markerData == activeMarkerData,
              owner.operationID == expectation.operationID,
              owner.manifestSHA256 == expectation.manifestSHA256,
              owner.host == expectation.host,
              owner.purpose == expectation.purpose,
              owner.pid == nil,
              gate.schemaVersion == PrejournalRecoveryGateReport.currentSchemaVersion,
              gate.operationID == expectation.operationID,
              gate.manifestSHA256 == expectation.manifestSHA256,
              gate.host == expectation.host,
              gate.purpose == expectation.purpose,
              gate.ownerToken == owner.token,
              gate.sourceDirectory == sourceDirectory.path,
              gate.controlPath == controlPath,
              gate.archiveDirectory == archiveDirectory.path,
              gate.ownerSHA256 == BessieProjectTargetMigration.sha256(ownerData),
              gate.activeMarkerSHA256 == BessieProjectTargetMigration.sha256(activeMarkerData),
              gate.inventory == ["owner.json"],
              gate.muxCheckStatus != 0,
              gate.processInspection == "current-user process inventory complete; no matching ssh executable and control path" else {
            throw MigrationToolError.ownership("Published pre-journal recovery gate is not bound to this operation.")
        }
        return (.init(
            directoryIdentity: gate.directoryIdentity,
            ownerIdentity: gate.ownerIdentity,
            ownerData: ownerData,
            owner: owner,
            muxCheckStatus: gate.muxCheckStatus
        ), gateData)
    }

    private static func validatePrejournalTerminalReport(
        _ url: URL,
        expectation: PrejournalRecoveryExpectation,
        first: PrejournalRecoveryInspection,
        activeMarkerData: Data,
        gateData: Data
    ) throws -> Data {
        try requirePrivateOwnedRegularFile(url, label: "pre-journal terminal recovery report")
        try requireCanonicalRegularFile(url, label: "pre-journal terminal recovery report")
        let data = try Data(contentsOf: url)
        let report: PrejournalRecoveryTerminalReport = try decodeRecoveryReport(data)
        guard report.schemaVersion == PrejournalRecoveryTerminalReport.currentSchemaVersion,
              report.operationID == expectation.operationID,
              report.manifestSHA256 == expectation.manifestSHA256,
              report.ownerSHA256 == BessieProjectTargetMigration.sha256(first.ownerData),
              report.activeMarkerSHA256 == BessieProjectTargetMigration.sha256(activeMarkerData),
              report.gateReportSHA256 == BessieProjectTargetMigration.sha256(gateData),
              report.sourceDirectoryRemoved,
              report.journalAbsent,
              report.activeMarkerRetained,
              report.sourcesUnchanged else {
            throw MigrationToolError.ownership("Pre-journal terminal recovery report is invalid.")
        }
        return data
    }

    private static func rejectIncompleteRecoveryStaging(for archiveDirectory: URL) throws {
        let prefix = ".\(archiveDirectory.lastPathComponent).staging-"
        let parent = archiveDirectory.deletingLastPathComponent()
        guard try FileManager.default.contentsOfDirectory(atPath: parent.path)
            .allSatisfy({ !$0.hasPrefix(prefix) }) else {
            throw MigrationToolError.ownership(
                "An incomplete pre-journal recovery staging directory was preserved for operator review."
            )
        }
    }

    private static func inspectInertPrejournalEvidence(
        sourceDirectory: URL,
        controlPath: String,
        expectation: PrejournalRecoveryExpectation,
        inspectProcesses: (String) throws -> Void,
        muxCheck: (String, String) throws -> Int32
    ) throws -> PrejournalRecoveryInspection {
        try requirePrivateOwnedDirectory(sourceDirectory, label: "pre-journal SSH owner directory")
        guard sourceDirectory.standardizedFileURL.path
                == sourceDirectory.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw MigrationToolError.ownership("Pre-journal SSH owner directory is not canonical.")
        }
        try requireExactSSHDirectoryInventory(at: sourceDirectory, expected: Set(["owner.json"]))
        let ownerURL = sourceDirectory.appendingPathComponent("owner.json")
        try requirePrivateOwnedRegularFile(ownerURL, label: "pre-journal SSH owner record")
        try requireCanonicalRegularFile(ownerURL, label: "pre-journal SSH owner record")
        try requireAbsent(URL(fileURLWithPath: controlPath), label: "pre-journal SSH control socket")
        let ownerData = try Data(contentsOf: ownerURL)
        let owner = try JSONDecoder().decode(SSHOwnerMarker.self, from: ownerData)
        guard owner.operationID == expectation.operationID,
              owner.manifestSHA256 == expectation.manifestSHA256,
              owner.host == expectation.host,
              owner.purpose == expectation.purpose,
              owner.pid == nil else {
            throw MigrationToolError.ownership(
                "Pre-journal owner record is not an inert nil-PID record bound to this operation."
            )
        }
        try inspectProcesses(controlPath)
        let muxStatus = try muxCheck(controlPath, expectation.host)
        guard muxStatus != 0 else {
            throw MigrationToolError.ownership("Pre-journal control path still reaches a live SSH master.")
        }
        try inspectProcesses(controlPath)
        try requireExactSSHDirectoryInventory(at: sourceDirectory, expected: Set(["owner.json"]))
        try requireAbsent(URL(fileURLWithPath: controlPath), label: "pre-journal SSH control socket")
        guard try Data(contentsOf: ownerURL) == ownerData else {
            throw MigrationToolError.ownership("Pre-journal owner bytes changed during process inspection.")
        }
        return .init(
            directoryIdentity: try itemIdentity(sourceDirectory, expectedType: S_IFDIR),
            ownerIdentity: try itemIdentity(ownerURL, expectedType: S_IFREG),
            ownerData: ownerData,
            owner: owner,
            muxCheckStatus: muxStatus
        )
    }

    private static func itemIdentity(_ url: URL, expectedType: mode_t) throws -> PrejournalRecoveryItemIdentity {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == expectedType else {
            throw MigrationToolError.ownership("Recovery evidence identity changed: \(url.path)")
        }
        return .init(
            device: UInt64(details.st_dev),
            inode: UInt64(details.st_ino),
            mode: UInt16(details.st_mode & 0o7777),
            ownerID: details.st_uid,
            groupID: details.st_gid,
            linkCount: UInt16(details.st_nlink),
            size: details.st_size
        )
    }

    private static func encodeRecoveryReport<T: Encodable>(_ report: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    private static func decodeRecoveryReport<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private static func requireNoSSHProcess(controlPath: String) throws {
        let result = try run("/bin/ps", ["-axo", "uid=,pid=,comm=,command="])
        guard result.status == 0 else {
            throw MigrationToolError.ownership("Could not inspect current-user SSH process arguments.")
        }
        for line in result.output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard fields.count == 4,
                  let uid = uid_t(fields[0]),
                  Int32(fields[1]) != nil else {
                throw MigrationToolError.ownership("Current-user process inventory could not be parsed completely.")
            }
            let executable = URL(fileURLWithPath: String(fields[2])).lastPathComponent
            let command = String(fields[3])
            if uid == geteuid(),
               executable == "ssh",
               command.contains(controlPath) {
                throw MigrationToolError.ownership(
                    "A current-user SSH process still references the pre-journal control path."
                )
            }
        }
    }

    private static func requireManifestSourcesUnchanged(
        _ manifest: BessieProjectTargetMigrationManifest
    ) throws -> MigrationSourceSnapshot {
        let connectionData = try Data(contentsOf: URL(fileURLWithPath: manifest.connectionsPath))
        let connectionSHA256 = BessieProjectTargetMigration.sha256(connectionData)
        guard connectionSHA256 == manifest.connectionSourceSHA256.lowercased() else {
            throw BessieProjectTargetMigrationError.sourceDrift(
                "Connection source hash differs from the migration manifest."
            )
        }
        let projectURLs = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: manifest.projectsPath, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        guard projectURLs.count == manifest.expectedProjectCount else {
            throw BessieProjectTargetMigrationError.sourceDrift(
                "Project source inventory differs from the migration manifest."
            )
        }
        let expected = Dictionary(uniqueKeysWithValues: manifest.projects.map {
            ($0.projectID, $0.sourceSHA256.lowercased())
        })
        var actual: [UUID: String] = [:]
        for url in projectURLs {
            guard let projectID = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  expected[projectID] != nil else {
                throw BessieProjectTargetMigrationError.sourceDrift(
                    "Project source inventory contains an unexpected file: \(url.lastPathComponent)."
                )
            }
            try requirePrivateOwnedRegularFile(url, label: "Project source")
            try requireCanonicalRegularFile(url, label: "Project source")
            actual[projectID] = BessieProjectTargetMigration.sha256(try Data(contentsOf: url))
        }
        guard actual == expected else {
            throw BessieProjectTargetMigrationError.sourceDrift(
                "One or more Project source hashes differ from the migration manifest."
            )
        }
        return .init(connectionSHA256: connectionSHA256, projectSHA256ByID: actual)
    }

    static func requireAbsent(_ url: URL, label: String) throws {
        var details = stat()
        if lstat(url.path, &details) == 0 {
            throw MigrationToolError.ownership("\(label) must be absent: \(url.path)")
        }
        guard errno == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private enum JournalPublicationState: Equatable {
        case absent
        case published
    }

    private static func journalPublicationState(at url: URL) throws -> JournalPublicationState {
        var details = stat()
        if lstat(url.path, &details) == 0 { return .published }
        guard errno == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return .absent
    }

    private static func requireCanonicalRegularFile(_ url: URL, label: String) throws {
        let standardized = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        var details = stat()
        guard standardized == resolved,
              lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFREG,
              details.st_nlink == 1 else {
            throw MigrationToolError.ownership("\(label) must be a canonical, non-symlink regular file: \(url.path)")
        }
    }

    private static func requirePrivateOwnedDirectory(_ url: URL, label: String) throws {
        try requirePrivateOwnedItem(url, label: label, type: S_IFDIR, mode: 0o700)
    }

    private static func requirePrivateOwnedRegularFile(_ url: URL, label: String) throws {
        try requirePrivateOwnedItem(url, label: label, type: S_IFREG, mode: 0o600)
    }

    private static func requireOwnedSocket(_ url: URL) throws {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFSOCK,
              details.st_uid == geteuid(),
              (details.st_mode & 0o077) == 0 else {
            throw MigrationToolError.ownership(
                "SSH control socket is not a private, current-user-owned socket: \(url.path)"
            )
        }
    }

    private static func requirePrivateOwnedItem(
        _ url: URL,
        label: String,
        type: mode_t,
        mode: mode_t
    ) throws {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == type,
              details.st_uid == geteuid(),
              (type != S_IFREG || details.st_nlink == 1),
              (details.st_mode & 0o777) == mode else {
            throw MigrationToolError.ownership(
                "\(label) must be private, current-user-owned, and non-symlink: \(url.path)"
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
            throw MigrationToolError.ownership(
                "\(label) must be current-user-owned, non-symlink, and not group/world-writable: \(url.path)"
            )
        }
    }

    private static func runSSH(_ arguments: [String]) throws -> (status: Int32, output: String, error: String) {
        try run("/usr/bin/ssh", SSHHostKeyPolicy.requiredArguments + arguments)
    }

    private static func runControlSSH(
        host: String,
        controlPath: String,
        operation: String
    ) throws -> (status: Int32, output: String, error: String) {
        try runSSH([
            "-S", controlPath,
            "-o", "ControlMaster=no",
            "-o", "ProxyCommand=/usr/bin/false",
            "-O", operation,
            host,
        ])
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        output.fileHandleForWriting.closeFile()
        error.fileHandleForWriting.closeFile()
        let outputCapture = ProcessDataCapture()
        let errorCapture = ProcessDataCapture()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputCapture.store(output.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorCapture.store(error.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        process.waitUntilExit()
        readers.wait()
        guard let outputData = outputCapture.load(),
              let errorData = errorCapture.load(),
              let outputString = String(data: outputData, encoding: .utf8),
              let errorString = String(data: errorData, encoding: .utf8) else {
            throw MigrationToolError.ownership(
                "Process output could not be captured and decoded as UTF-8 for \(executable)."
            )
        }
        return (
            process.terminationStatus,
            outputString.trimmingCharacters(in: .whitespacesAndNewlines),
            errorString.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func syncFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static func writePrivateAtomically(_ data: Data, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try requireOwnedSafeDirectory(parent, label: "private write parent")
        let parentIdentity = try directoryIdentity(parent)
        try requireSafePrivateDestination(destination)
        let temporary = parent
            .appendingPathComponent(".\(UUID().uuidString).migration.tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            try data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < data.count {
                    let written = write(descriptor, base.advanced(by: offset), data.count - offset)
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    offset += written
                }
            }
            if fcntl(descriptor, F_FULLFSYNC) != 0, fsync(descriptor) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard close(descriptor) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard try directoryIdentity(parent) == parentIdentity else {
                throw MigrationToolError.ownership(
                    "Private write parent changed during replacement: \(parent.path)"
                )
            }
            try requireSafePrivateDestination(destination)
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try syncDirectory(destination.deletingLastPathComponent())
        } catch {
            close(descriptor)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func directoryIdentity(_ url: URL) throws -> (dev_t, ino_t) {
        var details = stat()
        guard lstat(url.path, &details) == 0, (details.st_mode & S_IFMT) == S_IFDIR else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return (details.st_dev, details.st_ino)
    }

    private static func requireSafePrivateDestination(_ url: URL) throws {
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
              (details.st_mode & 0o777) == 0o600 else {
            throw MigrationToolError.ownership(
                "Private write destination is not a private current-user-owned regular file: \(url.path)"
            )
        }
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static func printSummary(_ journal: BessieProjectTargetMigrationJournal, journalPath: String) {
        let completed = journal.projects.filter { $0.completedResultSHA256 == $0.resultSHA256 }.count
        print("operation_id=\(journal.operationID.uuidString)")
        print("phase=\(journal.phase.rawValue)")
        print("outcome=\(journal.terminalOutcome?.rawValue ?? "pending")")
        print("projects=\(journal.projects.count)")
        print("completed_projects=\(completed)")
        print("journal=\(journalPath)")
        print("ssh_master_pid=\(journal.sshMasterPID)")
        print("ssh_master_closed=\(journal.sshMasterClosedAt != nil)")
        if let message = journal.auditMessage { print("audit=\(message)") }
    }
}

private enum Required {
    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw MigrationToolError.ownership("Expected value was absent.") }
        return value
    }
}
