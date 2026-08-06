import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct BessieProjectRevision: Equatable, Sendable {
    public let sourceURL: URL
    public let updatedAt: Date
    public let fileNumber: UInt64?
    public let fileSize: UInt64
    public let modificationDate: Date

    public init(sourceURL: URL, updatedAt: Date, fileNumber: UInt64?, fileSize: UInt64, modificationDate: Date) {
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
        self.fileNumber = fileNumber
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

public struct BessieStoredProject: Equatable, Sendable {
    public let project: BessieProject
    public let revision: BessieProjectRevision
    public let sourceURL: URL
    public let filenameMismatch: Bool

    public init(project: BessieProject, revision: BessieProjectRevision, sourceURL: URL, filenameMismatch: Bool) {
        self.project = project
        self.revision = revision
        self.sourceURL = sourceURL
        self.filenameMismatch = filenameMismatch
    }
}

public struct BessieProjectCatalogIssue: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case corrupt
        case unsupportedSchemaVersion
        case migrationFailed
        case filenameMismatch
        case duplicateEmbeddedID
    }

    public let kind: Kind
    public let filename: String
    public let embeddedProjectID: UUID?
    public let message: String

    public init(kind: Kind, filename: String, embeddedProjectID: UUID? = nil, message: String) {
        self.kind = kind
        self.filename = filename
        self.embeddedProjectID = embeddedProjectID
        self.message = message
    }
}

public struct BessieProjectCatalog: Equatable, Sendable {
    public let projects: [BessieStoredProject]
    public let issues: [BessieProjectCatalogIssue]

    public init(projects: [BessieStoredProject], issues: [BessieProjectCatalogIssue]) {
        self.projects = projects
        self.issues = issues
    }
}

public struct BessieProjectWriteConflict: Equatable, Sendable {
    public let existing: BessieProject
    public let attempted: BessieProject
    public let expectedRevision: BessieProjectRevision
    public let actualRevision: BessieProjectRevision

    public init(
        existing: BessieProject,
        attempted: BessieProject,
        expectedRevision: BessieProjectRevision,
        actualRevision: BessieProjectRevision
    ) {
        self.existing = existing
        self.attempted = attempted
        self.expectedRevision = expectedRevision
        self.actualRevision = actualRevision
    }
}

public enum BessieProjectStoreError: Error, Equatable, Sendable {
    case alreadyExists(UUID)
    case notFound(UUID)
    case duplicateEmbeddedID(UUID)
    case staleWrite(BessieProjectWriteConflict)
    case filenameMismatch(filename: String, embeddedProjectID: UUID)
    case unsafeProjectFile(filename: String, reason: String)
    case migrationFailed(filename: String, reason: String)
    case trashRecoveryFailed(filename: String, ownerError: String, recoveryError: String)
}

public struct BessieProjectStore: Sendable {
    public let rootURL: URL
    private let now: @Sendable () -> Date
    private let trash: @Sendable (URL) throws -> Void
    private let atomicReplace: @Sendable (URL, URL) throws -> Void

    public init(
        rootURL: URL = BessieProjectStore.resolveRoot(),
        now: @escaping @Sendable () -> Date = Date.init,
        trash: @escaping @Sendable (URL) throws -> Void = BessieProjectStore.moveToTrash,
        atomicReplace: @escaping @Sendable (URL, URL) throws -> Void = BessieProjectStore.replaceAtomically
    ) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.now = now
        self.trash = trash
        self.atomicReplace = atomicReplace
    }

    public static func resolveRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment["BESSIE_PROJECTS_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return homeDirectory
            .appendingPathComponent("Library/Application Support/Bessie/Projects", isDirectory: true)
            .standardizedFileURL
    }

    public func list() throws -> BessieProjectCatalog {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return BessieProjectCatalog(projects: [], issues: [])
        }
        return try withStoreLock(exclusive: true) { try unlockedList() }
    }

    private func unlockedList() throws -> BessieProjectCatalog {
        let urls = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var projects: [BessieStoredProject] = []
        var issues: [BessieProjectCatalogIssue] = []
        for url in urls {
            do {
                let stored = try loadFile(at: url)
                projects.append(stored)
                if stored.filenameMismatch {
                    issues.append(.init(
                        kind: .filenameMismatch,
                        filename: url.lastPathComponent,
                        embeddedProjectID: stored.project.id,
                        message: "Filename does not match embedded project UUID."
                    ))
                }
            } catch let BessieProjectSchemaError.unsupportedVersion(version) {
                issues.append(.init(
                    kind: .unsupportedSchemaVersion,
                    filename: url.lastPathComponent,
                    message: "Unsupported project schema version \(version)."
                ))
            } catch let BessieProjectStoreError.unsafeProjectFile(_, reason) {
                issues.append(.init(
                    kind: .corrupt,
                    filename: url.lastPathComponent,
                    message: reason
                ))
            } catch let BessieProjectStoreError.migrationFailed(_, reason) {
                issues.append(.init(
                    kind: .migrationFailed,
                    filename: url.lastPathComponent,
                    message: "Project migration failed. \(reason)"
                ))
            } catch {
                issues.append(.init(
                    kind: .corrupt,
                    filename: url.lastPathComponent,
                    message: error.localizedDescription
                ))
            }
        }

        let duplicateIDs = Dictionary(grouping: projects, by: { $0.project.id })
            .filter { $0.value.count > 1 }
            .keys
        for id in duplicateIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            issues.append(.init(
                kind: .duplicateEmbeddedID,
                filename: projects.filter { $0.project.id == id }.map { $0.sourceURL.lastPathComponent }.sorted().joined(separator: ", "),
                embeddedProjectID: id,
                message: "Multiple files contain the same embedded project UUID."
            ))
        }

        projects.sort { lhs, rhs in
            let leftName = lhs.project.name.lowercased()
            let rightName = rhs.project.name.lowercased()
            if leftName != rightName { return leftName < rightName }
            if lhs.project.name != rhs.project.name { return lhs.project.name < rhs.project.name }
            if lhs.project.id.uuidString != rhs.project.id.uuidString {
                return lhs.project.id.uuidString < rhs.project.id.uuidString
            }
            return lhs.sourceURL.lastPathComponent < rhs.sourceURL.lastPathComponent
        }
        return BessieProjectCatalog(projects: projects, issues: issues)
    }

    public func load(id: UUID) throws -> BessieStoredProject {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw BessieProjectStoreError.notFound(id)
        }
        return try withStoreLock(exclusive: true) {
            let matches = try unlockedList().projects.filter { $0.project.id == id }
            guard !matches.isEmpty else { throw BessieProjectStoreError.notFound(id) }
            if let canonical = matches.first(where: { $0.sourceURL == canonicalURL(for: id) }) {
                return canonical
            }
            guard matches.count == 1 else { throw BessieProjectStoreError.duplicateEmbeddedID(id) }
            return matches[0]
        }
    }

    public func save(
        _ project: BessieProject,
        expected revision: BessieProjectRevision? = nil
    ) throws -> BessieStoredProject {
        if let revision { return try update(project, expected: revision) }
        return try create(project)
    }

    public func create(_ project: BessieProject) throws -> BessieStoredProject {
        try withStoreLock(exclusive: true) {
            let url = canonicalURL(for: project.id)
            let embeddedIDExists = try unlockedList().projects.contains { $0.project.id == project.id }
            guard !embeddedIDExists, !FileManager.default.fileExists(atPath: url.path) else {
                throw BessieProjectStoreError.alreadyExists(project.id)
            }
            var created = project
            let timestamp = now()
            created.createdAt = timestamp
            created.updatedAt = timestamp
            created.archivedAt = nil
            created = try created.normalized()
            try write(created, to: url, replacing: false)
            return try loadFile(at: url)
        }
    }

    public func update(_ project: BessieProject, expected revision: BessieProjectRevision) throws -> BessieStoredProject {
        try withStoreLock(exclusive: true) {
            guard owns(revision.sourceURL) else {
                throw BessieProjectStoreError.notFound(project.id)
            }
            let expectedFilename = project.id.uuidString + ".json"
            guard revision.sourceURL.lastPathComponent.caseInsensitiveCompare(expectedFilename) == .orderedSame else {
                throw BessieProjectStoreError.filenameMismatch(
                    filename: revision.sourceURL.lastPathComponent,
                    embeddedProjectID: project.id
                )
            }

            let existing = try loadFile(at: revision.sourceURL)
            guard existing.revision == revision else {
                throw BessieProjectStoreError.staleWrite(.init(
                    existing: existing.project,
                    attempted: project,
                    expectedRevision: revision,
                    actualRevision: existing.revision
                ))
            }
            guard existing.project.id == project.id else {
                throw BessieProjectStoreError.filenameMismatch(
                    filename: revision.sourceURL.lastPathComponent,
                    embeddedProjectID: existing.project.id
                )
            }

            var updated = project
            updated.updatedAt = now()
            updated = try updated.normalized()
            try write(updated, to: revision.sourceURL, replacing: true)
            return try loadFile(at: revision.sourceURL)
        }
    }

    public func duplicate(_ source: BessieStoredProject) throws -> BessieStoredProject {
        var duplicate = BessieProject(
            id: UUID(),
            name: source.project.name,
            projectDescription: source.project.projectDescription,
            group: source.project.group,
            folders: source.project.folders,
            tabs: source.project.tabs,
            createdAt: now(),
            updatedAt: now()
        )
        duplicate.archivedAt = nil
        return try create(duplicate)
    }

    public func setArchived(_ archived: Bool, project stored: BessieStoredProject) throws -> BessieStoredProject {
        var project = stored.project
        project.archivedAt = archived ? now() : nil
        return try update(project, expected: stored.revision)
    }

    public func recoverFilenameMismatch(_ stored: BessieStoredProject) throws -> BessieStoredProject {
        try withStoreLock(exclusive: true) {
            guard stored.sourceURL == stored.revision.sourceURL,
                  owns(stored.sourceURL) else {
                throw BessieProjectStoreError.notFound(stored.project.id)
            }
            let current = try loadFile(at: stored.sourceURL)
            guard current.revision == stored.revision else {
                throw BessieProjectStoreError.staleWrite(.init(
                    existing: current.project,
                    attempted: stored.project,
                    expectedRevision: stored.revision,
                    actualRevision: current.revision
                ))
            }
            guard current.filenameMismatch else { return current }

            let destination = canonicalURL(for: current.project.id)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw BessieProjectStoreError.alreadyExists(current.project.id)
            }
            let duplicateExists = try unlockedList().projects.contains {
                $0.project.id == current.project.id && $0.sourceURL != current.sourceURL
            }
            guard !duplicateExists else {
                throw BessieProjectStoreError.duplicateEmbeddedID(current.project.id)
            }

            guard link(current.sourceURL.path, destination.path) == 0 else {
                if errno == EEXIST {
                    throw BessieProjectStoreError.alreadyExists(current.project.id)
                }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try FileManager.default.removeItem(at: current.sourceURL)
            return try loadFile(at: destination)
        }
    }

    public func delete(_ stored: BessieStoredProject) throws {
        try withStoreLock(exclusive: true) {
            guard stored.sourceURL == stored.revision.sourceURL,
                  owns(stored.sourceURL) else {
                throw BessieProjectStoreError.notFound(stored.project.id)
            }
            let current = try loadFile(at: stored.sourceURL)
            guard current.revision == stored.revision else {
                throw BessieProjectStoreError.staleWrite(.init(
                    existing: current.project,
                    attempted: stored.project,
                    expectedRevision: stored.revision,
                    actualRevision: current.revision
                ))
            }

            let backupURL = rootURL.appendingPathComponent(".\(UUID().uuidString).trash-backup")
            guard link(current.sourceURL.path, backupURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            do {
                try trash(current.sourceURL)
                try FileManager.default.removeItem(at: backupURL)
            } catch {
                let ownerError = error
                do {
                    if FileManager.default.fileExists(atPath: current.sourceURL.path) {
                        try FileManager.default.removeItem(at: backupURL)
                    } else {
                        guard rename(backupURL.path, current.sourceURL.path) == 0 else {
                            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                        }
                    }
                } catch {
                    throw BessieProjectStoreError.trashRecoveryFailed(
                        filename: current.sourceURL.lastPathComponent,
                        ownerError: ownerError.localizedDescription,
                        recoveryError: error.localizedDescription
                    )
                }
                throw ownerError
            }
        }
    }

    private func loadFile(at url: URL) throws -> BessieStoredProject {
        let sourceURL = url.standardizedFileURL
        if try sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw BessieProjectStoreError.unsafeProjectFile(
                filename: sourceURL.lastPathComponent,
                reason: "Project catalog entries cannot be symbolic links."
            )
        }
        var data = try Data(contentsOf: sourceURL)
        if try BessieProjectCodec.schemaVersion(in: data) == 1 {
            data = try migrateVersionOneFile(data, at: sourceURL)
        }
        let project = try BessieProjectCodec.decode(data).normalizedForCatalog()
        let revision = try fileRevision(at: sourceURL, updatedAt: project.updatedAt)
        let filenameID = UUID(uuidString: sourceURL.deletingPathExtension().lastPathComponent)
        return BessieStoredProject(
            project: project,
            revision: revision,
            sourceURL: sourceURL,
            filenameMismatch: filenameID != project.id
        )
    }

    private func migrateVersionOneFile(_ originalData: Data, at sourceURL: URL) throws -> Data {
        let backupURL = sourceURL.appendingPathExtension("v1-backup")
        let temporaryURL = rootURL.appendingPathComponent(".\(UUID().uuidString).migration.tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            let migrated = try BessieProjectMigration.migrate(originalData)
            _ = try migrated.normalizedForCatalog()
            let migratedData = try BessieProjectCodec.encode(migrated)
            let decoded = try BessieProjectCodec.decode(migratedData)
            _ = try decoded.normalizedForCatalog()
            guard decoded == migrated else {
                throw BessieProjectStoreError.migrationFailed(
                    filename: sourceURL.lastPathComponent,
                    reason: "The validated schema-v2 representation did not match the migrated project."
                )
            }
            try migratedData.write(to: temporaryURL, options: .withoutOverwriting)

            if FileManager.default.fileExists(atPath: backupURL.path) {
                guard try Data(contentsOf: backupURL) == originalData else {
                    throw BessieProjectStoreError.migrationFailed(
                        filename: sourceURL.lastPathComponent,
                        reason: "A different migration backup already exists at \(backupURL.lastPathComponent)."
                    )
                }
            } else {
                try originalData.write(to: backupURL, options: .withoutOverwriting)
            }

            do {
                try atomicReplace(temporaryURL, sourceURL)
                let installedData = try Data(contentsOf: sourceURL)
                _ = try BessieProjectCodec.decode(installedData).normalizedForCatalog()
                return installedData
            } catch {
                let ownerError = error
                do {
                    try restoreMigrationBackup(backupURL, to: sourceURL)
                } catch {
                    throw BessieProjectStoreError.migrationFailed(
                        filename: sourceURL.lastPathComponent,
                        reason: "Replacement failed (\(ownerError.localizedDescription)); restoring the schema-v1 backup also failed (\(error.localizedDescription))."
                    )
                }
                throw BessieProjectStoreError.migrationFailed(
                    filename: sourceURL.lastPathComponent,
                    reason: "Replacement failed and was rolled back: \(ownerError.localizedDescription)"
                )
            }
        } catch let error as BessieProjectStoreError {
            throw error
        } catch {
            throw BessieProjectStoreError.migrationFailed(
                filename: sourceURL.lastPathComponent,
                reason: error.localizedDescription
            )
        }
    }

    private func restoreMigrationBackup(_ backupURL: URL, to sourceURL: URL) throws {
        let restoreURL = rootURL.appendingPathComponent(".\(UUID().uuidString).rollback.tmp")
        defer { try? FileManager.default.removeItem(at: restoreURL) }
        try Data(contentsOf: backupURL).write(to: restoreURL, options: .withoutOverwriting)
        try BessieProjectStore.replaceAtomically(restoreURL, sourceURL)
    }

    private func fileRevision(at url: URL, updatedAt: Date) throws -> BessieProjectRevision {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return BessieProjectRevision(
            sourceURL: url,
            updatedAt: updatedAt,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date ?? .distantPast
        )
    }

    private func write(_ project: BessieProject, to destination: URL, replacing: Bool) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let temporary = rootURL.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try BessieProjectCodec.encode(project).write(to: temporary, options: .withoutOverwriting)

        if replacing {
            try atomicReplace(temporary, destination)
        } else {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw BessieProjectStoreError.alreadyExists(project.id)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private func canonicalURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
    }

    private func owns(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            == rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func withStoreLock<T>(exclusive: Bool, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let lockURL = rootURL.appendingPathComponent(".store.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    public static func moveToTrash(_ url: URL) throws {
        #if os(macOS)
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    public static func replaceAtomically(_ source: URL, _ destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
