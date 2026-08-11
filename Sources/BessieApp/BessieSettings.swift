import AppKit
import BessieCore
import CoreGraphics
import Darwin
import Foundation
import SwiftUI
import UserNotifications

struct BessieOnboardingSettingsJournal: Codable, Equatable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let previousPresentationExists: Bool
    let previousPresentation: BessiePresentationState
    let previousConnectionsExists: Bool
    let previousConnections: BessieConnectionState
    let acceptedPresentation: BessiePresentationState
    let acceptedConnections: BessieConnectionState

    init(
        previousPresentationExists: Bool,
        previousPresentation: BessiePresentationState,
        previousConnectionsExists: Bool,
        previousConnections: BessieConnectionState,
        acceptedPresentation: BessiePresentationState,
        acceptedConnections: BessieConnectionState
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.previousPresentationExists = previousPresentationExists
        self.previousPresentation = previousPresentation
        self.previousConnectionsExists = previousConnectionsExists
        self.previousConnections = previousConnections
        self.acceptedPresentation = acceptedPresentation
        self.acceptedConnections = acceptedConnections
    }
}

private enum BessieOnboardingDurableFile {
    static let maximumBytes = 1_048_576

    static func writeNewPrivateFile(_ data: Data, to destination: URL) throws {
        guard data.count <= maximumBytes else { throw BessiePresentationPersistenceError.invalidSource }
        let parent = destination.deletingLastPathComponent()
        let parentIdentity = try preparePrivateDirectory(parent)
        guard !pathExists(destination) else { throw BessiePresentationPersistenceError.invalidSource }
        let temporary = parent.appendingPathComponent(".\(UUID().uuidString).onboarding.tmp")
        let descriptor = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw posixError() }
        var descriptorOpen = true
        defer {
            if descriptorOpen { close(descriptor) }
            try? FileManager.default.removeItem(at: temporary)
        }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw posixError() }
                offset += written
            }
        }
        try fullSync(descriptor)
        let closeResult = close(descriptor)
        descriptorOpen = false
        guard closeResult == 0 else { throw posixError() }
        guard try directoryIdentity(parent) == parentIdentity,
              !pathExists(destination),
              rename(temporary.path, destination.path) == 0 else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        try syncDirectory(parent)
    }

    static func readPrivateFile(at url: URL) throws -> Data {
        try requirePrivateDirectory(url.deletingLastPathComponent())
        let expected = try privateFileDetails(at: url)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw BessiePresentationPersistenceError.invalidSource }
        defer { close(descriptor) }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0,
              opened.st_dev == expected.st_dev,
              opened.st_ino == expected.st_ino,
              isPrivateRegularFile(opened) else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw posixError() }
            if count == 0 { break }
            guard data.count + count <= maximumBytes else {
                throw BessiePresentationPersistenceError.invalidSource
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    static func syncPrivateFile(at url: URL) throws {
        let expected = try ownedRegularFileDetails(at: url)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw BessiePresentationPersistenceError.invalidSource }
        defer { close(descriptor) }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0,
              opened.st_dev == expected.st_dev,
              opened.st_ino == expected.st_ino,
              isOwnedRegularFile(opened),
              fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        try fullSync(descriptor)
        try syncDirectory(url.deletingLastPathComponent())
    }

    static func removePrivateFileDurably(at url: URL) throws {
        _ = try privateFileDetails(at: url)
        guard unlink(url.path) == 0 else { throw posixError() }
        try syncDirectory(url.deletingLastPathComponent())
    }

    static func removeOwnedRegularFileDurablyIfPresent(at url: URL) throws {
        var details = stat()
        guard lstat(url.path, &details) == 0 else {
            if errno == ENOENT { return }
            throw BessiePresentationPersistenceError.invalidSource
        }
        guard isOwnedRegularFile(details), unlink(url.path) == 0 else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        try syncDirectory(url.deletingLastPathComponent())
    }

    static func isSafePrivateFile(at url: URL) -> Bool {
        (try? privateFileDetails(at: url)) != nil
    }

    private static func preparePrivateDirectory(_ url: URL) throws -> (dev_t, ino_t) {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw BessiePresentationPersistenceError.invalidSource }
        defer { close(descriptor) }
        var details = stat()
        guard fstat(descriptor, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFDIR,
              details.st_uid == geteuid(),
              fchmod(descriptor, S_IRWXU) == 0 else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        return (details.st_dev, details.st_ino)
    }

    private static func requirePrivateDirectory(_ url: URL) throws {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFDIR,
              details.st_uid == geteuid(),
              (details.st_mode & 0o777) == 0o700 else {
            throw BessiePresentationPersistenceError.invalidSource
        }
    }

    private static func directoryIdentity(_ url: URL) throws -> (dev_t, ino_t) {
        var details = stat()
        guard lstat(url.path, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFDIR,
              details.st_uid == geteuid() else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        return (details.st_dev, details.st_ino)
    }

    private static func privateFileDetails(at url: URL) throws -> stat {
        let details = try ownedRegularFileDetails(at: url)
        guard isPrivateRegularFile(details),
              details.st_size >= 0,
              details.st_size <= maximumBytes else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        return details
    }

    private static func ownedRegularFileDetails(at url: URL) throws -> stat {
        var details = stat()
        guard lstat(url.path, &details) == 0, isOwnedRegularFile(details) else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        return details
    }

    private static func isOwnedRegularFile(_ details: stat) -> Bool {
        (details.st_mode & S_IFMT) == S_IFREG
            && details.st_uid == geteuid()
            && details.st_nlink == 1
    }

    private static func isPrivateRegularFile(_ details: stat) -> Bool {
        isOwnedRegularFile(details) && (details.st_mode & 0o777) == 0o600
    }

    private static func pathExists(_ url: URL) -> Bool {
        var details = stat()
        if lstat(url.path, &details) == 0 { return true }
        return errno != ENOENT
    }

    private static func fullSync(_ descriptor: Int32) throws {
        if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

enum BessieOnboardingSettingsTransaction {
    static func journalURL(for connectionsURL: URL) -> URL {
        connectionsURL.deletingLastPathComponent()
            .appendingPathComponent(".bessie-onboarding-transaction", isDirectory: true)
            .appendingPathComponent("journal.json")
    }

    static func commit(
        journal: BessieOnboardingSettingsJournal,
        journalURL: URL,
        presentationStore: BessiePresentationStore,
        connectionStore: BessieConnectionStore
    ) throws {
        try save(journal, to: journalURL)
        do {
            try connectionStore.save(journal.acceptedConnections)
            try BessieOnboardingDurableFile.syncPrivateFile(at: connectionStore.url)
            try presentationStore.save(journal.acceptedPresentation)
            try BessieOnboardingDurableFile.syncPrivateFile(at: presentationStore.url)
            try BessieOnboardingDurableFile.removePrivateFileDurably(at: journalURL)
        } catch {
            do {
                try restorePrevious(
                    journal,
                    journalURL: journalURL,
                    presentationStore: presentationStore,
                    connectionStore: connectionStore
                )
            } catch {
                BessieDiagnosticLog.append("Onboarding settings transaction rollback failed: \(String(reflecting: error))")
            }
            throw error
        }
    }

    static func recoverIfNeeded(
        journalURL: URL,
        presentationStore: BessiePresentationStore,
        connectionStore: BessieConnectionStore
    ) throws {
        var journalDetails = stat()
        guard lstat(journalURL.path, &journalDetails) == 0 else {
            if errno == ENOENT { return }
            throw BessiePresentationPersistenceError.invalidSource
        }
        let data = try BessieOnboardingDurableFile.readPrivateFile(at: journalURL)
        let journal = try JSONDecoder().decode(BessieOnboardingSettingsJournal.self, from: data)
        guard journal.schemaVersion == BessieOnboardingSettingsJournal.currentSchemaVersion else {
            throw BessiePresentationPersistenceError.invalidSource
        }
        let currentPresentation = BessieOnboardingDurableFile.isSafePrivateFile(at: presentationStore.url)
            ? try? presentationStore.loadWithNormalizationStatus().state
            : nil
        let currentConnections = BessieOnboardingDurableFile.isSafePrivateFile(at: connectionStore.url)
            ? try? connectionStore.load()
            : nil
        if currentPresentation == journal.acceptedPresentation,
           currentConnections == journal.acceptedConnections {
            try BessieOnboardingDurableFile.syncPrivateFile(at: connectionStore.url)
            try BessieOnboardingDurableFile.syncPrivateFile(at: presentationStore.url)
            try BessieOnboardingDurableFile.removePrivateFileDurably(at: journalURL)
            return
        }
        try restorePrevious(
            journal,
            journalURL: journalURL,
            presentationStore: presentationStore,
            connectionStore: connectionStore
        )
    }

    private static func save(_ journal: BessieOnboardingSettingsJournal, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try BessieOnboardingDurableFile.writeNewPrivateFile(encoder.encode(journal), to: url)
    }

    private static func restorePrevious(
        _ journal: BessieOnboardingSettingsJournal,
        journalURL: URL,
        presentationStore: BessiePresentationStore,
        connectionStore: BessieConnectionStore
    ) throws {
        if journal.previousConnectionsExists {
            try connectionStore.save(journal.previousConnections)
            try BessieOnboardingDurableFile.syncPrivateFile(at: connectionStore.url)
        } else {
            try BessieOnboardingDurableFile.removeOwnedRegularFileDurablyIfPresent(at: connectionStore.url)
        }
        if journal.previousPresentationExists {
            try presentationStore.save(journal.previousPresentation)
            try BessieOnboardingDurableFile.syncPrivateFile(at: presentationStore.url)
        } else {
            try BessieOnboardingDurableFile.removeOwnedRegularFileDurablyIfPresent(at: presentationStore.url)
        }
        try BessieOnboardingDurableFile.removePrivateFileDurably(at: journalURL)
    }
}

@MainActor
final class BessieSettingsModel: ObservableObject {
    @Published var preferences: BessiePreferences {
        didSet {
            if !publishingPersistedPreferences { persist() }
        }
    }
    @Published private(set) var lastWorkspaceIDByConnectionID: [String: String]
    @Published private(set) var workspaceScopePreference: BessieWorkspaceScopePreference?
    private let legacyLastWorkspaceID: String?
    @Published private(set) var connections: [BessieConnectionDefinition]
    @Published private(set) var selectedConnectionID: String
    @Published private(set) var defaultProjectConnectionID: String
    @Published private(set) var connectionError: String?
    @Published private(set) var connectionConfigurationLoadFailed: Bool
    @Published private(set) var runtimeSelection: HerdrRuntimeSelection
    @Published private(set) var onboarding = OnboardingState()
    @Published private(set) var runtimePersistenceError: String?
    @Published private(set) var onboardingCompletionError: String?
    @Published private(set) var presentationPersistenceError: String?
    @Published private(set) var panePresentationLedger: BessiePanePresentationLedger
    @Published private(set) var presentationDirtyRevision: UInt64?
    @Published private(set) var addConnectionRequested = false
    @Published private(set) var setupEntryGeneration = 0
    var paneDidBecomeSnoozed: ((BessiePaneIncarnation) -> Void)?
    private var completionBeforeSetupEntry = false
    private let store: BessiePresentationStore
    private let connectionStore: BessieConnectionStore
    private let runtimeStore: HerdrRuntimeSelectionStore
    private let configurationLease: BessieConfigurationLease?
    private let presentationLease: BessiePresentationLease?
    private let presentationLoadBlocker: String?
    private var publishingPersistedPreferences = false
    private lazy var paneSnoozeSupervisor = BessiePaneSnoozeSupervisor { [weak self] in
        self?.reconcilePaneSnoozes()
    }

    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        let url: URL
        if let path = environment["BESSIE_PRESENTATION_PATH"] {
            url = URL(fileURLWithPath: path)
        } else {
            url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Bessie", isDirectory: true)
                .appendingPathComponent("presentation.json")
        }
        let connectionURL = environment["BESSIE_CONNECTIONS_PATH"].map(URL.init(fileURLWithPath:))
            ?? url.deletingLastPathComponent().appendingPathComponent("connections.json")
        self.init(
            presentationURL: url,
            connectionsURL: connectionURL,
            runtimeSelectionURL: url.deletingLastPathComponent().appendingPathComponent("runtime-selection.json")
        )
    }

    init(presentationURL: URL, connectionsURL: URL, runtimeSelectionURL: URL) {
        store = BessiePresentationStore(url: presentationURL)
        connectionStore = BessieConnectionStore(url: connectionsURL)
        runtimeStore = HerdrRuntimeSelectionStore(url: runtimeSelectionURL)
        runtimeSelection = runtimeStore.load()
        var acquiredPresentationLease: BessiePresentationLease?
        var presentationLeaseFailure: Error?
        do {
            acquiredPresentationLease = try BessiePresentationLease.acquire(for: presentationURL)
        } catch {
            presentationLeaseFailure = error
        }
        presentationLease = acquiredPresentationLease
        var acquiredLease: BessieConfigurationLease?
        var leaseFailure: Error?
        do {
            acquiredLease = try BessieConfigurationLease.acquireShared(for: connectionsURL)
        } catch {
            leaseFailure = error
        }
        configurationLease = acquiredLease
        var recoveryFailure: Error?
        if presentationLeaseFailure == nil, leaseFailure == nil {
            do {
                try BessieOnboardingSettingsTransaction.recoverIfNeeded(
                    journalURL: BessieOnboardingSettingsTransaction.journalURL(for: connectionsURL),
                    presentationStore: store,
                    connectionStore: connectionStore
                )
            } catch {
                recoveryFailure = error
                BessieDiagnosticLog.append("Onboarding settings transaction recovery failed: \(String(reflecting: error))")
            }
        }
        let state: BessiePresentationState?
        let loadBlocker: String?
        let presentationDidNormalize: Bool
        do {
            if let presentationLeaseFailure { throw presentationLeaseFailure }
            if let recoveryFailure { throw recoveryFailure }
            let loaded = try store.loadWithNormalizationStatus()
            state = loaded.state
            presentationDidNormalize = loaded.didNormalize
            loadBlocker = nil
        } catch {
            state = nil
            presentationDidNormalize = false
            loadBlocker = error.localizedDescription
            BessieDiagnosticLog.append(
                "Presentation load blocked without rewrite type=\(String(describing: type(of: error)))"
            )
        }
        presentationPersistenceError = loadBlocker
        presentationLoadBlocker = loadBlocker
        presentationDirtyRevision = nil
        var loadedPanePresentationLedger = (try? BessiePanePresentationLedger(
            revision: state?.panePresentationRevision ?? 0,
            records: state?.panePresentationPreferences ?? []
        )) ?? (try! BessiePanePresentationLedger())
        if presentationDidNormalize {
            try? loadedPanePresentationLedger.recordLoadNormalization()
        }
        panePresentationLedger = loadedPanePresentationLedger
        let loadedPreferences = state?.preferences ?? BessiePreferences()
        preferences = loadedPreferences
        legacyLastWorkspaceID = state?.lastWorkspaceID
        lastWorkspaceIDByConnectionID = state?.lastWorkspaceIDByConnectionID ?? [:]
        workspaceScopePreference = state?.workspaceScope

        let loadedConnections: [BessieConnectionDefinition]
        let loadedSelectedConnectionID: String
        let loadedDefaultProjectConnectionID: String
        let connectionLoadError: String?
        do {
            if let leaseFailure { throw leaseFailure }
            if let recoveryFailure { throw recoveryFailure }
            let connectionState = try connectionStore.load()
            loadedConnections = connectionState.connections
            loadedSelectedConnectionID = connectionState.selectedConnectionID
            loadedDefaultProjectConnectionID = connectionState.defaultProjectConnectionID
            connectionLoadError = nil
            connectionConfigurationLoadFailed = false
        } catch {
            BessieDiagnosticLog.append("Connections load failed: \(String(reflecting: error))")
            loadedConnections = []
            loadedSelectedConnectionID = ""
            loadedDefaultProjectConnectionID = ""
            connectionLoadError = "Bessie couldn't load herd settings and did not start any herd. Restore or repair connections.json, then reopen Bessie. \(error.localizedDescription)"
            connectionConfigurationLoadFailed = true
        }
        connections = loadedConnections
        selectedConnectionID = loadedSelectedConnectionID
        defaultProjectConnectionID = loadedDefaultProjectConnectionID
        connectionError = connectionLoadError
        onboarding.completed = state?.firstRealTerminalCompletionVersion == BessiePresentationState.firstRealTerminalCompletionVersion
        if let artboard = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"],
           let number = Int(artboard), (9...13).contains(number) {
            onboarding.completed = false
            onboarding.step = number <= 10 ? .connect : OnboardingState.Step(rawValue: number - 9) ?? .connect
        } else if onboarding.completed { onboarding.step = .notifications }
        BessieDiagnosticLog.append("Connections selected=\(selectedConnectionID) count=\(connections.count)")
        if presentationDidNormalize { persist() }
    }

    private func persist() {
        guard presentationLoadBlocker == nil, presentationLease != nil else { return }
        do {
            try store.save(presentationState)
            presentationPersistenceError = nil
            presentationDirtyRevision = nil
        } catch {
            presentationPersistenceError = error.localizedDescription
            presentationDirtyRevision = panePresentationLedger.revision
        }
    }

    func retryPresentationPersistence() { persist() }

    @discardableResult
    func commitGhosttyCompatibility(enabled: Bool, selectedPath: String?) -> Bool {
        guard presentationLoadBlocker == nil, presentationLease != nil else {
            presentationPersistenceError = presentationLoadBlocker ?? "Bessie couldn't acquire presentation storage."
            return false
        }
        var candidate = preferences
        candidate.ghosttyCompatibilityEnabled = enabled
        candidate.ghosttyCompatibilitySelectedPath = selectedPath
        guard candidate != preferences else { return true }
        do {
            try store.save(presentationState(preferences: candidate))
            publishingPersistedPreferences = true
            preferences = candidate
            publishingPersistedPreferences = false
            presentationPersistenceError = nil
            presentationDirtyRevision = nil
            return true
        } catch {
            publishingPersistedPreferences = false
            presentationPersistenceError = error.localizedDescription
            BessieDiagnosticLog.append("Ghostty compatibility persistence failed: \(String(reflecting: error))")
            return false
        }
    }

    @discardableResult
    func setPanePinned(_ pinned: Bool, incarnation: BessiePaneIncarnation) -> Bool {
        mutatePanePresentation { try $0.setPinned(pinned, for: incarnation) }
    }

    @discardableResult
    func setPaneSnooze(
        _ preset: BessiePaneSnoozePreset,
        incarnation: BessiePaneIncarnation,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let snooze = preset.snooze(now: now, calendar: calendar)
        let changed = mutatePanePresentation { try $0.setSnooze(snooze, for: incarnation, now: now) }
        if changed { paneDidBecomeSnoozed?(incarnation) }
        return changed
    }

    @discardableResult
    func wakePane(_ incarnation: BessiePaneIncarnation, now: Date = Date()) -> Bool {
        mutatePanePresentation { try $0.wake(incarnation, now: now) }
    }

    @discardableResult
    func reconcilePaneSnoozes(now: Date = Date()) -> Bool {
        let changed = mutatePanePresentation { try $0.reconcile(now: now) }
        supervisePaneSnoozes(now: now)
        return changed
    }

    func supervisePaneSnoozes(now: Date = Date()) {
        paneSnoozeSupervisor.update(records: panePresentationLedger.records, now: now)
    }

    func snoozedPaneIncarnations(now: Date = Date()) -> Set<BessiePaneIncarnation> {
        Set(panePresentationLedger.records.compactMap { record in
            guard record.snooze?.isActive(at: now) == true else { return nil }
            return record.incarnation
        })
    }

    @discardableResult
    func removePanePresentation(_ incarnation: BessiePaneIncarnation) -> Bool {
        mutatePanePresentation { try $0.remove(incarnation) }
    }

    @discardableResult
    func reconcilePanePresentations(
        connectionID: String,
        fullSnapshotIncarnations: Set<BessiePaneIncarnation>
    ) -> Bool {
        mutatePanePresentation {
            try $0.reconcileFullSnapshot(connectionID: connectionID, incarnations: fullSnapshotIncarnations)
        }
    }

    private func mutatePanePresentation(
        _ mutation: (inout BessiePanePresentationLedger) throws -> Bool
    ) -> Bool {
        var candidate = panePresentationLedger
        do {
            guard try mutation(&candidate) else { return false }
            panePresentationLedger = candidate
            persist()
            supervisePaneSnoozes()
            return true
        } catch {
            presentationPersistenceError = error.localizedDescription
            return false
        }
    }

    /// Drive AppKit appearance so adaptive palette colors and window chrome follow
    /// the preference, not only SwiftUI's preferredColorScheme.
    static func applyAppAppearance(
        selection: BessieThemeID,
        effectiveScheme: ColorScheme,
        palette: BessiePalette
    ) {
        guard let app = NSApp else { return }
        switch selection {
        case .system:
            app.appearance = nil
        default:
            app.appearance = NSAppearance(named: effectiveScheme == .light ? .aqua : .darkAqua)
        }
        let background = NSColor(palette.window)
        for window in app.windows where window.styleMask.contains(.titled) {
            window.backgroundColor = background
            window.contentView?.needsDisplay = true
            window.contentView?.subviews.forEach { $0.needsDisplay = true }
            window.invalidateShadow()
        }
    }

    func commitThemeSelection(_ selection: BessieThemeID) {
        guard preferences.appearance != selection else { return }
        preferences.appearance = selection
    }

    var lastWorkspaceID: String? {
        lastWorkspaceID(for: selectedConnectionID)
    }

    func recordLastWorkspace(_ id: String?) {
        recordLastWorkspace(id, connectionID: selectedConnectionID)
    }

    func lastWorkspaceID(for connectionID: String) -> String? {
        lastWorkspaceIDByConnectionID[connectionID]
            ?? (connectionID == BessieConnectionDefinition.localBessie.id ? legacyLastWorkspaceID : nil)
    }

    func recordLastWorkspace(_ id: String?, connectionID: String) {
        lastWorkspaceIDByConnectionID[connectionID] = id
        persist()
    }

    func recordWorkspaceScope(_ scope: BessieWorkspaceScopePreference) {
        guard workspaceScopePreference != scope else { return }
        workspaceScopePreference = scope
        persist()
    }

    var selectedConnection: BessieConnectionDefinition {
        connections.first { $0.id == selectedConnectionID && $0.enabled }
            ?? connections.first(where: \.enabled)
            ?? BessieConnectionDefinition(
                id: BessieConnectionDefinition.localBessie.id,
                name: "Herd settings unavailable",
                kind: .local,
                enabled: false,
                connectAtLaunch: false
            )
    }

    var enabledConnections: [BessieConnectionDefinition] {
        connections.filter(\.enabled)
    }

    @discardableResult
    func selectConnection(_ id: String) -> Bool {
        guard connections.contains(where: { $0.id == id && $0.enabled }) else {
            connectionError = "Enable this herd before selecting it."
            return false
        }
        return publishConnectionCandidate(
            selectedConnectionID: id,
            defaultProjectConnectionID: defaultProjectConnectionID,
            connections: connections
        )
    }

    @discardableResult
    func selectConnectionForSetup(_ id: String) -> Bool {
        guard let index = connections.firstIndex(where: { $0.id == id }) else {
            connectionError = "That herd is no longer configured."
            return false
        }
        var candidate = connections
        candidate[index].enabled = true
        return publishConnectionCandidate(
            selectedConnectionID: id,
            defaultProjectConnectionID: defaultProjectConnectionID,
            connections: candidate
        )
    }

    @discardableResult
    func setDefaultProjectConnection(_ id: String) -> Bool {
        guard connections.contains(where: { $0.id == id && $0.enabled }) else {
            connectionError = "Enable this herd before making it the Project default."
            return false
        }
        return publishConnectionCandidate(
            selectedConnectionID: selectedConnectionID,
            defaultProjectConnectionID: id,
            connections: connections
        )
    }

    @discardableResult
    func setConnectionEnabled(connectionID: String, enabled: Bool) -> Bool {
        guard let index = connections.firstIndex(where: { $0.id == connectionID }) else { return false }
        guard connections[index].enabled != enabled else { return true }
        var candidate = connections
        candidate[index].enabled = enabled
        return publishConnectionCandidate(
            selectedConnectionID: selectedConnectionID,
            defaultProjectConnectionID: defaultProjectConnectionID,
            connections: candidate
        )
    }

    @discardableResult
    func setConnectAtLaunch(connectionID: String, enabled: Bool) -> Bool {
        guard let index = connections.firstIndex(where: { $0.id == connectionID }) else { return false }
        guard connections[index].enabled else {
            connectionError = "Enable this herd before changing its launch behavior."
            return false
        }
        guard connections[index].connectAtLaunch != enabled else { return true }
        var candidate = connections
        candidate[index].connectAtLaunch = enabled
        return publishConnectionCandidate(
            selectedConnectionID: selectedConnectionID,
            defaultProjectConnectionID: defaultProjectConnectionID,
            connections: candidate
        )
    }

    @discardableResult
    func addConnection(name: String, sshHost: String, session: String?) -> Bool {
        do {
            let connection = try BessieConnectionDefinition(
                name: name,
                kind: .ssh,
                sshHost: sshHost,
                session: session,
                connectAtLaunch: false
            ).validated()
            return publishConnectionCandidate(
                selectedConnectionID: connection.id,
                defaultProjectConnectionID: connection.id,
                connections: connections + [connection]
            )
        } catch {
            connectionError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func removeConnection(_ id: String) -> Bool {
        guard id != BessieConnectionDefinition.localBessie.id,
              connections.contains(where: { $0.id == id })
        else { return false }
        return publishConnectionCandidate(
            selectedConnectionID: selectedConnectionID,
            defaultProjectConnectionID: defaultProjectConnectionID,
            connections: connections.filter { $0.id != id }
        )
    }

    func registerOnboardingConnection(_ connection: BessieConnectionDefinition) throws {
        let connection = try connection.validated()
        guard connection.id != BessieConnectionDefinition.localBessie.id else { return }
        var candidate = connections
        if let index = candidate.firstIndex(where: { $0.id == connection.id }) { candidate[index] = connection }
        else { candidate.append(connection) }
        guard publishConnectionCandidate(
            selectedConnectionID: connection.id,
            defaultProjectConnectionID: connection.id,
            connections: candidate
        ) else {
            throw BessieConnectionPersistenceError.saveFailed(connectionError ?? "Unknown persistence failure.")
        }
    }

    func clearConnectionError() { connectionError = nil }

    func requestAddConnection() { addConnectionRequested = true }

    func consumeAddConnectionRequest() { addConnectionRequested = false }

    func runSetupAgain() {
        completionBeforeSetupEntry = onboarding.completed
        onboarding.runAgain()
        setupEntryGeneration += 1
        persist()
    }

    func beginIsolatedOnboarding() {
        onboarding = OnboardingState()
        onboardingCompletionError = nil
        connectionError = nil
    }

    var canCancelSetupBeforeMaterialization: Bool { completionBeforeSetupEntry }

    func cancelSetupAgainBeforeMaterialization() {
        guard completionBeforeSetupEntry else { return }
        onboarding = OnboardingState(step: .notifications, completed: true)
        completionBeforeSetupEntry = false
        persist()
    }

    func goBackInSetup() {
        onboarding.goBack()
        onboardingCompletionError = nil
        persist()
    }

    func advanceSetup(runtimeReady: Bool, sessionReady: Bool, workspaceReady: Bool, terminalControllerReady: Bool) {
        onboarding.advance(runtimeReady: runtimeReady, sessionReady: sessionReady, workspaceReady: workspaceReady,
                           terminalControllerReady: terminalControllerReady)
        persist()
    }

    func terminalBecameReady() {
        if onboarding.step == .notifications { onboardingCompletionError = nil }
    }

    @discardableResult
    func finishSetup(
        connected: Bool,
        hasWorkspace: Bool,
        terminalControllerReady: Bool,
        notificationPolicy: BessieNotifications? = nil,
        connection: BessieConnectionDefinition? = nil
    ) -> Bool {
        guard presentationPersistenceError == nil else {
            onboardingCompletionError = presentationPersistenceError
            return false
        }
        guard connected, hasWorkspace, terminalControllerReady else {
            onboardingCompletionError = "Connect to Herdr, open a workspace, and wait for the terminal before finishing."
            return false
        }
        if connection != nil, connectionConfigurationLoadFailed {
            onboardingCompletionError =
                "Repair or restore connections.json before finishing setup. Bessie has left the unreadable file untouched."
            return false
        }
        let previous = onboarding
        let previousCompletionBeforeSetupEntry = completionBeforeSetupEntry
        let previousConnectionState = BessieConnectionState(
            selectedConnectionID: selectedConnectionID,
            defaultProjectConnectionID: defaultProjectConnectionID,
            connections: connections
        )
        let connectionCandidate: BessieConnectionState?
        do {
            if let connection {
                let accepted = try connection.validated()
                var definitions = connections
                if let index = definitions.firstIndex(where: { $0.id == accepted.id }) {
                    definitions[index] = accepted
                } else {
                    definitions.append(accepted)
                }
                connectionCandidate = try BessieConnectionState.validated(
                    selectedConnectionID: accepted.id,
                    defaultProjectConnectionID: accepted.id,
                    connections: definitions
                )
            } else {
                connectionCandidate = nil
            }
        } catch {
            onboardingCompletionError = "Bessie couldn't save the accepted herd. \(error.localizedDescription)"
            return false
        }
        onboarding = OnboardingState(step: .notifications, completed: true)
        completionBeforeSetupEntry = false
        // The current run's notification choice commits atomically with
        // completion: a persistence failure leaves both the in-memory
        // preferences and the durable presentation state untouched.
        var candidate = preferences
        if let notificationPolicy { candidate.notifications = notificationPolicy }
        do {
            let acceptedPresentation = presentationState(preferences: candidate)
            if let connectionCandidate {
                let journal = BessieOnboardingSettingsJournal(
                    previousPresentationExists: FileManager.default.fileExists(atPath: store.url.path),
                    previousPresentation: presentationState(preferences: preferences),
                    previousConnectionsExists: FileManager.default.fileExists(atPath: connectionStore.url.path),
                    previousConnections: previousConnectionState,
                    acceptedPresentation: acceptedPresentation,
                    acceptedConnections: connectionCandidate
                )
                try BessieOnboardingSettingsTransaction.commit(
                    journal: journal,
                    journalURL: BessieOnboardingSettingsTransaction.journalURL(for: connectionStore.url),
                    presentationStore: store,
                    connectionStore: connectionStore
                )
            } else {
                try store.save(acceptedPresentation)
            }
            if let connectionCandidate {
                connections = connectionCandidate.connections
                selectedConnectionID = connectionCandidate.selectedConnectionID
                defaultProjectConnectionID = connectionCandidate.defaultProjectConnectionID
                connectionError = nil
            }
            publishingPersistedPreferences = true
            preferences = candidate
            publishingPersistedPreferences = false
            onboardingCompletionError = nil
            return true
        } catch {
            onboarding = previous
            completionBeforeSetupEntry = previousCompletionBeforeSetupEntry
            onboardingCompletionError = "Bessie couldn't save setup completion. \(error.localizedDescription)"
            BessieDiagnosticLog.append("Onboarding completion persistence failed: \(String(reflecting: error))")
            return false
        }
    }

    func reportOnboardingFocusFailure() {
        onboardingCompletionError = "Bessie couldn't focus the ready terminal. Try Finish again."
    }

    func clearOnboardingCompletionError() {
        onboardingCompletionError = nil
    }

    private var presentationState: BessiePresentationState {
        presentationState(preferences: preferences)
    }

    private func presentationState(preferences: BessiePreferences) -> BessiePresentationState {
        BessiePresentationState(
            lastWorkspaceID: lastWorkspaceIDByConnectionID[BessieConnectionDefinition.localBessie.id] ?? legacyLastWorkspaceID,
            lastWorkspaceIDByConnectionID: lastWorkspaceIDByConnectionID,
            preferences: preferences,
            // A re-entered setup run is transient: the prior durable completion
            // survives on disk until the replacement setup actually succeeds.
            firstRealTerminalCompletionVersion: onboarding.completed || completionBeforeSetupEntry
                ? BessiePresentationState.firstRealTerminalCompletionVersion : nil,
            panePresentationRevision: panePresentationLedger.revision == 0 ? nil : panePresentationLedger.revision,
            panePresentationPreferences: panePresentationLedger.records.isEmpty ? nil : panePresentationLedger.records,
            workspaceScope: workspaceScopePreference
        )
    }

    @discardableResult
    private func publishConnectionCandidate(
        selectedConnectionID: String,
        defaultProjectConnectionID: String,
        connections: [BessieConnectionDefinition]
    ) -> Bool {
        guard !connectionConfigurationLoadFailed else {
            connectionError = "Repair or restore connections.json before changing herd settings. Bessie has left the unreadable file untouched."
            return false
        }
        do {
            let candidate = try BessieConnectionState.validated(
                selectedConnectionID: selectedConnectionID,
                defaultProjectConnectionID: defaultProjectConnectionID,
                connections: connections
            )
            try connectionStore.save(candidate)
            self.connections = candidate.connections
            self.selectedConnectionID = candidate.selectedConnectionID
            self.defaultProjectConnectionID = candidate.defaultProjectConnectionID
            connectionError = nil
            return true
        } catch let error as BessieConnectionStateError {
            connectionError = error.localizedDescription
        } catch {
            connectionError = "Bessie couldn't save herd settings. \(error.localizedDescription)"
        }
        return false
    }

}

@MainActor
final class BessiePaneSnoozeSupervisor {
    private let reconcile: () -> Void
    private var deadlineTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    init(reconcile: @escaping () -> Void) {
        self.reconcile = reconcile
    }

    deinit {
        deadlineTask?.cancel()
        watchdogTask?.cancel()
    }

    func update(records: [BessiePanePresentationPreference], now: Date = Date()) {
        deadlineTask?.cancel()
        watchdogTask?.cancel()
        let schedule = BessiePaneSnoozeSchedule(records: records, now: now)
        if let deadline = schedule.nextDeadline {
            let seconds = min(
                max(0, deadline.timeIntervalSince(now)),
                Double(UInt64.max) / 1_000_000_000
            )
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            deadlineTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                self?.reconcile()
            }
        }
        if schedule.needsWatchdog {
            watchdogTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.reconcile()
                }
            }
        }
    }
}

private enum BessieConnectionPersistenceError: LocalizedError {
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let detail): detail
        }
    }
}

@MainActor
enum BessieAppIconController {
    static func apply(_ icon: BessieAppIcon) {
        let resource = icon == .dark ? "BessieIconDark" : "BessieIconLight"
        guard let url = BessieResources.url(forResource: resource, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return }
        NSApplication.shared.applicationIconImage = image
        BessieDiagnosticLog.append("App icon=\(icon.rawValue)")
    }
}

struct BessieSettingsView: View {
    @EnvironmentObject private var model: BessieSettingsModel
    @EnvironmentObject private var themeCoordinator: BessieThemeCoordinator
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    @EnvironmentObject private var fleet: ConnectionFleetViewModel
    @EnvironmentObject private var updates: BessieUpdateCoordinator
    @State private var showAddConnection = false
    @State private var connectionName = ""
    @State private var sshHost = ""
    @State private var herdrSession = ""
    @State private var connectionPendingDisable: BessieConnectionDefinition?
    @State private var connectionPendingRemoval: BessieConnectionDefinition?
    let embedded: Bool
    let runtimeDiagnostic: RuntimeDiagnosticSnapshot?

    init(embedded: Bool = false, runtimeDiagnostic: RuntimeDiagnosticSnapshot? = nil) {
        self.embedded = embedded
        self.runtimeDiagnostic = runtimeDiagnostic
    }

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 0) {
                    BessieTopBar(title: "Settings") {
                        Button("Reset to defaults") { themeCoordinator.resetPreferencesToDefaults() }
                            .buttonStyle(BessieQuietButtonStyle())
                    }
                    settingsScroll
                }
            } else {
                settingsScroll
                    .padding(9)
                    .bessieSurface(base: BessieDesign.background)
                .frame(width: 720, height: 620)
            }
        }
        .navigationTitle("Bessie settings")
        .task { notifications.refreshAuthorization() }
        .onAppear {
            if model.addConnectionRequested { prepareAddConnection() }
        }
        .onChange(of: model.addConnectionRequested) { _, requested in
            if requested { prepareAddConnection() }
        }
        .sheet(isPresented: $showAddConnection) { addConnectionSheet }
        .confirmationDialog(
            "Disable this herd?",
            isPresented: Binding(
                get: { connectionPendingDisable != nil },
                set: { if !$0 { connectionPendingDisable = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let connectionPendingDisable {
                Button("Disable \(connectionPendingDisable.name)", role: .destructive) {
                    model.setConnectionEnabled(connectionID: connectionPendingDisable.id, enabled: false)
                    self.connectionPendingDisable = nil
                }
                .foregroundStyle(BessieDesign.destructive)
            }
            Button("Cancel", role: .cancel) { connectionPendingDisable = nil }
        } message: {
            Text("Bessie will stop using this herd. Projects targeting it cannot launch until you re-enable or retarget them, and the active or default herd may change. Herdr, panes, and their processes keep running.")
        }
        .confirmationDialog(
            "Remove SSH connection?",
            isPresented: Binding(
                get: { connectionPendingRemoval != nil },
                set: { if !$0 { connectionPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let connectionPendingRemoval {
                Button("Remove \(connectionPendingRemoval.name)", role: .destructive) {
                    model.removeConnection(connectionPendingRemoval.id)
                    self.connectionPendingRemoval = nil
                }
                .foregroundStyle(BessieDesign.destructive)
            }
            Button("Cancel", role: .cancel) { connectionPendingRemoval = nil }
        } message: {
            Text("This disconnects Bessie only. Remote Herdr and its session keep running.")
        }
    }

    private var settingsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BessieSettingsSectionLabel(icon: .play, title: "General")

                BessieGeneralSettingsControls()

                BessieSettingsSectionLabel(icon: .cloud, title: "Updates")
                    .padding(.top, 16)

                BessieUpdateSettingsControls()

                BessieSettingsSectionLabel(icon: .hardDrives, title: "Herds") {
                    Button { prepareAddConnection() } label: { BessieIconView(icon: .plus, size: 13) }
                        .buttonStyle(BessieSettingsIconButtonStyle())
                        .help("Add a herd")
                        .accessibilityLabel("Add a herd")
                }
                .padding(.top, BessieSettingsLayout.sectionSpacing)

                VStack(spacing: 0) {
                    ForEach(model.connections) { connection in
                        connectionRow(connection)
                        if connection.id != model.connections.last?.id {
                            Divider().overlay(BessieDesign.border)
                        }
                    }
                }
                .background(BessieDesign.panel)
                .overlay { RoundedRectangle(cornerRadius: BessieDesign.controlRadius).stroke(BessieDesign.border) }
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))

                Text(model.connectionError ?? "Choose Start at launch for herds that should connect when Bessie opens. Others start when you select them.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(BessieDesign.faint)
                    .padding(.top, 7)

                BessieSettingsSectionLabel(icon: .terminalWindow, title: "Terminal")
                    .padding(.top, BessieSettingsLayout.sectionSpacing)

                BessieTerminalSettingsControls()

                BessieSettingsSectionLabel(icon: .bell, title: "Notifications")
                    .padding(.top, BessieSettingsLayout.sectionSpacing)

                BessieNotificationSettingsControls(target: activeNotificationTarget)

                BessieSettingsSectionLabel(icon: .listBullets, title: "Menu bar")
                    .padding(.top, BessieSettingsLayout.sectionSpacing)

                BessieMenuBarSettingsControls()

                BessieSettingsSectionLabel(icon: .paintBrush, title: "Appearance")
                    .padding(.top, BessieSettingsLayout.sectionSpacing)

                BessieAppearanceSettingsControls()

                BessieSettingsSectionLabel(icon: .wrench, title: "Advanced & diagnostics")
                    .padding(.top, BessieSettingsLayout.sectionSpacing)

                VStack(spacing: 0) {
                    BessieDiagnosticRow(
                        label: "Bessie",
                        value: "\(appVersion) · libghostty 1.3.2"
                    )
                }
                .background(BessieDesign.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                        .stroke(BessieDesign.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))

                if let error = model.presentationPersistenceError {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(BessieDesign.strong)
                        .padding(.top, 10)
                }

                HStack(spacing: 8) {
                    Button("Run setup again") { model.runSetupAgain() }
                        .buttonStyle(BessieSecondaryButtonStyle())
                    Button("Copy diagnostics") { copyDiagnostics() }
                        .buttonStyle(BessieQuietButtonStyle())
                }
                .padding(.top, 12)


            }
            .padding(.horizontal, BessieSettingsLayout.horizontalPadding)
            .padding(.top, BessieSettingsLayout.topPadding)
            .padding(.bottom, BessieSettingsLayout.bottomPadding)
            .frame(maxWidth: BessieSettingsLayout.maximumWidth, alignment: .leading)
        }
        .background(Color.clear)
    }

    private var activeNotificationTarget: RoutedPaneTarget? {
        guard let model = fleet.activeModel,
              let projection = model.projection,
              let pane = projection.focusedPane,
              let target = BessieSurfaceProjection(projection: projection).openTarget(paneID: pane.id)
        else { return nil }
        return RoutedPaneTarget(
            connectionID: model.activeConnection.id,
            workspaceID: target.workspaceID,
            tabID: target.tabID,
            paneID: target.paneID
        )
    }

    private func copyDiagnostics() {
        let runtime = runtimeDiagnostic?.observedProtocol.map(String.init) ?? "unknown"
        let text = "Bessie \(appVersion)\nHerdr protocol \(runtime)\nlibghostty 1.3.2\nConnections \(model.connections.count)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    private func connectionRow(_ connection: BessieConnectionDefinition) -> some View {
        let health = fleet.connectionHealth.first { $0.connectionID == connection.id }
        let selected = model.selectedConnectionID == connection.id
        let isDefault = model.defaultProjectConnectionID == connection.id
        let detail: String = {
            guard connection.enabled else {
                return connection.connectAtLaunch
                    ? "disabled · start-at-launch retained"
                    : "disabled"
            }
            if connection.kind == .local {
                let phase = health?.isUsable == true ? "healthy" : (health?.phase.lowercased() ?? "not started")
                return "included runtime · \(phase)"
            }
            return "ssh · \(health?.detail ?? health?.phase ?? "not started")"
        }()
        return HStack(spacing: 10) {
            Circle().fill(health?.isUsable == true ? BessieDesign.strong : BessieDesign.subtle).frame(width: 6, height: 6)
                .accessibilityLabel(health?.isUsable == true ? "Healthy" : "Unavailable")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(ConnectionDisplayLabel(connection: connection).short)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(BessieDesign.strong)
                    if selected { Text("active").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(BessieDesign.strong) }
                    if isDefault { Text("Project default").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(BessieDesign.subtle) }
                }
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.faint)
                    .lineLimit(1)
            }
            Spacer()
            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { connection.enabled },
                    set: { enabled in
                        if enabled {
                            model.setConnectionEnabled(connectionID: connection.id, enabled: true)
                        } else if model.enabledConnections.count == 1 {
                            model.setConnectionEnabled(connectionID: connection.id, enabled: false)
                        } else {
                            connectionPendingDisable = connection
                        }
                    }
                )
            )
            .toggleStyle(BessieSettingsSwitchStyle())
            .labelsHidden()
            .help(connection.enabled ? "Disable this herd" : "Enable this herd")
            .accessibilityLabel("Enable \(connection.name)")
            .accessibilityValue(connection.enabled ? "Enabled" : "Disabled")
            Text("Use")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(connection.enabled ? BessieDesign.strong : BessieDesign.faint)
                .accessibilityHidden(true)
            Toggle(
                "Start at launch",
                isOn: Binding(
                    get: { connection.connectAtLaunch },
                    set: { model.setConnectAtLaunch(connectionID: connection.id, enabled: $0) }
                )
            )
            .toggleStyle(BessieSettingsSwitchStyle())
            .labelsHidden()
            .disabled(!connection.enabled)
            .help(connection.enabled
                ? "Start this herd when Bessie opens"
                : "Enable this herd to use its retained start-at-launch setting")
            .accessibilityLabel("Start \(connection.name) at launch")
            .accessibilityValue(connection.enabled
                ? (connection.connectAtLaunch ? "On" : "Off")
                : "Unavailable while disabled")
            Text("Launch")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(connection.connectAtLaunch ? BessieDesign.strong : BessieDesign.faint)
                .accessibilityHidden(true)
            if connection.enabled, health?.canRetry == true {
                Button(health?.phase == "Not started" ? "Connect" : "Retry") {
                    if health?.phase == "Not started" {
                        model.selectConnection(connection.id)
                        _ = fleet.activate(connectionID: connection.id)
                    } else {
                        fleet.retry(connectionID: connection.id)
                    }
                }
                .buttonStyle(BessieSecondaryButtonStyle())
            }
            if connection.enabled, !selected {
                Button("Set active") { model.selectConnection(connection.id) }
                    .buttonStyle(BessieQuietButtonStyle())
            }
            if connection.enabled, !isDefault {
                Button("Project default") { model.setDefaultProjectConnection(connection.id) }
                    .buttonStyle(BessieQuietButtonStyle())
                    .accessibilityLabel("Make \(connection.name) the default Project herd")
            }
            if connection.kind == .ssh {
                Button { connectionPendingRemoval = connection } label: {
                    BessieIconView(icon: .dotsThree, size: 16)
                }
                .buttonStyle(BessieSettingsIconButtonStyle())
                .accessibilityLabel("More options for \(connection.name)")
                .accessibilityHint("Opens removal options")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }

    private var addConnectionSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            BessieSectionLabel("NEW SSH CONNECTION")
                .padding(.bottom, 18)
            connectionField("Name", placeholder: "Studio Mac", text: $connectionName)
            connectionField("SSH host", placeholder: "studio-mac", text: $sshHost)
                .padding(.top, 14)
            connectionField("Herdr session", placeholder: "default", text: $herdrSession)
                .padding(.top, 14)
            Text("Use a Host alias from ~/.ssh/config; OpenSSH handles the destination, user, key, and agent. The Herdr session is optional. Bessie Project files store launch folders and layout, never passwords or secrets.")
                .font(.system(size: 10.5))
                .lineSpacing(2)
                .foregroundStyle(BessieDesign.subtle)
                .padding(.top, 12)
            if let error = model.connectionError {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(BessieDesign.strong)
                    .padding(.top, 10)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { showAddConnection = false }
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Add and connect") {
                    if model.addConnection(name: connectionName, sshHost: sshHost, session: herdrSession) {
                        showAddConnection = false
                    }
                }
                .buttonStyle(BessiePrimaryButtonStyle())
            }
            .padding(.top, 22)
        }
        .padding(28)
        .frame(width: 460)
        .background(BessieDesign.background)
        .preferredColorScheme(model.preferences.appearance.preferredColorScheme)
    }

    private func prepareAddConnection() {
        model.consumeAddConnectionRequest()
        connectionName = ""
        sshHost = ""
        herdrSession = ""
        model.clearConnectionError()
        showAddConnection = true
    }

    private func connectionField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BessieDesign.subtle)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .tint(BessieDesign.insertionPoint)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(BessieDesign.inset)
                .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
        }
    }

}

struct BessieGeneralSettingsControls: View {
    @EnvironmentObject private var model: BessieSettingsModel

    var body: some View {
        BessieSettingRow(label: "On startup", hint: "What Bessie opens when it launches.") {
            BessieMiniSegments(selection: $model.preferences.startupBehavior, values: BessieStartupBehavior.allCases) { $0.title }
        }
    }
}

struct BessieUpdateSettingsPresentation: Equatable {
    static let maximumStatusLength = 240

    let currentVersion: String
    let currentBuild: String
    let targetVersion: String?
    let targetBuild: String?
    let status: String?
    let canCheckForUpdates: Bool

    init(
        state: BessieUpdateState,
        canCheckForUpdates: Bool,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        currentVersion = infoDictionary["CFBundleShortVersionString"] as? String ?? "development"
        currentBuild = infoDictionary["CFBundleVersion"] as? String ?? "unknown"
        let target: BessieUpdateVersion? = switch state.phase {
        case let .readyToRestart(version), let .installing(version): version
        case .ineligible, .idle, .checking, .failed: nil
        }
        targetVersion = target?.shortVersion
        targetBuild = target?.buildVersion
        status = state.status.map { String($0.prefix(Self.maximumStatusLength)) }
        self.canCheckForUpdates = canCheckForUpdates
    }
}

struct BessieUpdateSettingsControls: View {
    @EnvironmentObject private var updates: BessieUpdateCoordinator

    private var presentation: BessieUpdateSettingsPresentation {
        BessieUpdateSettingsPresentation(
            state: updates.state,
            canCheckForUpdates: updates.canCheckForUpdates
        )
    }

    var body: some View {
        Group {
            BessieSettingRow(
                label: "Automatic checks",
                hint: "Use Sparkle’s normal schedule to look for signed Bessie updates."
            ) {
                Toggle("", isOn: Binding(
                    get: { updates.state.preferences.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }
                ))
                .labelsHidden()
                .accessibilityLabel("Automatically check for updates")
                .toggleStyle(BessieSettingsSwitchStyle())
            }
            BessieSettingRow(
                label: "Automatic downloads",
                hint: automaticDownloadHint
            ) {
                Toggle("", isOn: Binding(
                    get: { updates.state.preferences.automaticallyDownloadsAndInstallsUpdates },
                    set: { updates.setAutomaticallyDownloadsAndInstallsUpdates($0) }
                ))
                .labelsHidden()
                .accessibilityLabel("Automatically download and install updates")
                .toggleStyle(BessieSettingsSwitchStyle())
                .disabled(!updates.state.preferences.allowsAutomaticUpdates)
            }
            BessieSettingRow(label: "Current version") {
                Text("\(presentation.currentVersion) (\(presentation.currentBuild))")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.subtle)
            }
            if let targetVersion = presentation.targetVersion {
                BessieSettingRow(label: "Target version") {
                    Text("\(targetVersion) (\(presentation.targetBuild ?? "unknown"))")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(BessieDesign.subtle)
                }
            }
            BessieSettingRow(label: "Check now", hint: "Sparkle shows progress and any manual-check errors.") {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .buttonStyle(BessieSecondaryButtonStyle())
                    .disabled(!presentation.canCheckForUpdates)
            }
            if let status = presentation.status {
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(BessieDesign.subtle)
                    .lineLimit(3)
                    .frame(maxWidth: BessieSettingsLayout.labelColumnWidth * 2, alignment: .leading)
                    .padding(.top, 8)
                    .accessibilityIdentifier("update-status")
            }
        }
    }

    private var automaticDownloadHint: String {
        updates.state.preferences.allowsAutomaticUpdates
            ? "Download verified updates in the background and install them when Bessie quits."
            : "Automatic updates are unavailable in this build."
    }
}

struct BessieTerminalSettingsControls: View {
    @EnvironmentObject private var model: BessieSettingsModel
    @EnvironmentObject private var themeCoordinator: BessieThemeCoordinator

    var body: some View {
        Group {
            BessieSettingRow(label: "Font size", hint: "Applies to every pane.") {
                BessieSettingsStepper(value: $model.preferences.terminalFontSize, range: 10...24, rangeLabel: "10–24", label: "Terminal font size")
            }
            BessieSettingRow(label: "Pane spacing", hint: "The gap between tiled panes.") {
                BessieSettingsStepper(value: $model.preferences.paneGap, range: 0...16, rangeLabel: "0–16", label: "Pane spacing")
            }
            BessieSettingRow(
                label: "Ghostty compatibility",
                hint: "Apply compatible settings from a Ghostty configuration. Bessie only uses supported presentation settings."
            ) {
                Toggle("", isOn: compatibilityBinding)
                    .labelsHidden()
                    .accessibilityLabel("Ghostty compatibility")
                    .toggleStyle(BessieSettingsSwitchStyle())
            }
            BessieSettingRow(label: "Ghostty configuration", hint: selectedConfigurationLabel) {
                HStack(spacing: 8) {
                    Button("Choose…") { chooseConfiguration() }
                        .buttonStyle(BessieSecondaryButtonStyle())
                    if model.preferences.ghosttyCompatibilityEnabled {
                        Button("Reload") { themeCoordinator.reloadCompatibilityConfiguration() }
                            .buttonStyle(BessieQuietButtonStyle())
                    }
                }
            }
            if let message = themeCoordinator.compatibilityError {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(BessieDesign.strong)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .accessibilityIdentifier("ghostty-compatibility-error")
            } else if let summary = themeCoordinator.compatibilitySummary {
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(BessieDesign.subtle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .accessibilityIdentifier("ghostty-compatibility-summary")
            }
        }
    }

    private var compatibilityBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.ghosttyCompatibilityEnabled },
            set: { themeCoordinator.setCompatibilityEnabled($0) }
        )
    }

    private var selectedConfigurationLabel: String {
        guard let path = model.preferences.ghosttyCompatibilitySelectedPath else {
            return "Choose a config before enabling. The file is read-only and is never passed to Ghostty."
        }
        return "Selected: \(URL(fileURLWithPath: path).lastPathComponent). Changes apply only when you choose Reload."
    }

    private func chooseConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "Choose Ghostty Configuration"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        themeCoordinator.selectCompatibilityConfiguration(url)
    }
}

struct BessieAppearanceSettingsControls: View {
    @EnvironmentObject private var model: BessieSettingsModel
    @EnvironmentObject private var themeCoordinator: BessieThemeCoordinator

    var body: some View {
        Group {
            BessieSettingRow(label: "Theme", hint: "System follows your Mac appearance.") {
                Picker("Theme", selection: themeCoordinator.binding()) {
                    ForEach(BessieThemeRegistry.selectableIDs, id: \.self) { id in
                        HStack(spacing: 7) {
                            BessieThemeSwatches(id: id)
                            Text(id.title)
                            Spacer()
                            Text(id.schemeLabel)
                                .foregroundStyle(BessieDesign.subtle)
                        }
                        .tag(id)
                        .accessibilityLabel("\(id.title), \(id.schemeLabel)")
                    }
                }
                .pickerStyle(.menu)
                .tint(BessieDesign.controlTint)
                .frame(width: 220)
                .accessibilityLabel("Theme")
            }
            BessieSettingRow(label: "Density", hint: "Adjusts chrome, rows, and card spacing.") {
                BessieMiniSegments(selection: $model.preferences.density, values: BessieDensity.allCases) { $0.title }
            }
            BessieSettingRow(label: "App icon", hint: "Used in the Dock and app switcher.") {
                BessieMiniSegments(selection: $model.preferences.appIcon, values: BessieAppIcon.allCases) { $0.title }
            }
            BessieSettingRow(label: "Cowprint texture") {
                Toggle("", isOn: $model.preferences.cowprintEnabled)
                    .labelsHidden()
                    .accessibilityLabel("Cowprint texture")
                    .toggleStyle(BessieSettingsSwitchStyle())
            }
        }
    }
}

struct BessieMenuBarSettingsControls: View {
    @EnvironmentObject private var model: BessieSettingsModel

    var body: some View {
        Group {
            BessieSettingRow(label: "Show in the menu bar", hint: "The menu bar is how Bessie reaches you when it is not focused.") {
                Toggle("", isOn: $model.preferences.menuBarVisible).labelsHidden().toggleStyle(BessieSettingsSwitchStyle())
            }
            BessieSettingRow(label: "Badge shows", hint: "The number beside the cow.") {
                BessieMiniSegments(selection: $model.preferences.menuBarBadgePolicy, values: BessieMenuBarBadgePolicy.allCases) { $0.title }
            }
            BessieSettingRow(label: "Clicking a row") {
                BessieMiniSegments(selection: $model.preferences.menuBarRowClickBehavior, values: BessieMenuBarRowClickBehavior.allCases) { $0.title }
            }
        }
    }
}

struct BessieNotificationSettingsControls: View {
    @EnvironmentObject private var model: BessieSettingsModel
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    let target: RoutedPaneTarget?
    var showsPolicy = true

    var body: some View {
        Group {
            if showsPolicy {
                BessieSettingRow(label: "Notify me", hint: "Only when the pane isn't active.") {
                    BessieMiniSegments(selection: $model.preferences.notifications, values: BessieNotifications.allCases) { $0.title }
                }
            }
            BessieSettingRow(label: "Permission") { permissionControl }
            BessieSettingRow(
                label: "Test notification",
                hint: "Uses synthetic content and never includes terminal output, connection details, or secrets."
            ) {
                Button("Send test notification") {
                    Task { await notifications.sendTestNotification(target: target) }
                }
                .buttonStyle(BessieSecondaryButtonStyle())
                .disabled(notifications.testNotificationStatus == .sending)
            }
            if let message = statusMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(BessieDesign.strong)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var permissionControl: some View {
        switch notifications.authorizationStatus {
        case .notDetermined:
            Button("Allow notifications") { notifications.requestAuthorization() }
                .buttonStyle(BessieSecondaryButtonStyle())
        case .denied:
            Button("Open Bessie Notification Settings") { notifications.openNotificationSettings() }
                .buttonStyle(BessieSecondaryButtonStyle())
        case .authorized, .provisional, .ephemeral:
            Text("Allowed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
        @unknown default:
            Text("Unavailable")
                .font(.system(size: 11))
                .foregroundStyle(BessieDesign.subtle)
        }
    }

    private var statusMessage: String? {
        switch notifications.testNotificationStatus {
        case .idle: notifications.authorizationError ?? notifications.operationError
        case .sending: "Sending test notification…"
        case .delivered: "Authorized and sent to Notification Center. If no banner appeared, check Bessie's alert style in System Settings."
        case .denied: "Permission denied. Open Bessie Notification Settings to allow alerts, sounds, and banners."
        case .failed(let message): message
        }
    }
}

enum BessieSettingsLayout {
    static let maximumWidth: CGFloat = 780
    static let topPadding: CGFloat = 26
    static let horizontalPadding: CGFloat = 40
    static let bottomPadding: CGFloat = 70
    static let sectionSpacing: CGFloat = 30
    static let labelColumnWidth: CGFloat = 252
    static let columnGap: CGFloat = 22
    static let rowVerticalPadding: CGFloat = 17
    static let switchWidth: CGFloat = 38
    static let switchHeight: CGFloat = 22
}

private struct BessieSettingsSectionLabel<Trailing: View>: View {
    let icon: BessieIcon
    let title: String
    @ViewBuilder let trailing: Trailing

    init(icon: BessieIcon, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 7) {
            BessieIconView(icon: icon, size: 14)
            Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced))
            Spacer()
            trailing
        }
        .foregroundStyle(BessieDesign.subtle)
        .frame(height: 24)
    }
}

private extension BessieSettingsSectionLabel where Trailing == EmptyView {
    init(icon: BessieIcon, title: String) { self.init(icon: icon, title: title) { EmptyView() } }
}

private struct BessieSettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(BessieDesign.subtle)
            .frame(width: 24, height: 24)
            .background(configuration.isPressed ? BessieDesign.selected : BessieSemanticColor.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct BessieMiniSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let values: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                Button(title(value)) { selection = value }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: selection == value ? .medium : .regular))
                    .foregroundStyle(selection == value ? BessieDesign.strong : BessieDesign.subtle)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(selection == value ? BessieDesign.selected : BessieSemanticColor.clear)
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .background(BessieDesign.inset)
        .overlay { RoundedRectangle(cornerRadius: 5).stroke(BessieDesign.border) }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct BessieSettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? BessieDesign.controlTint : BessieDesign.inset)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(configuration.isOn ? BessieDesign.background : BessieDesign.subtle)
                        .frame(width: 16, height: 16).padding(3)
                }
                .overlay { Capsule().stroke(BessieDesign.border) }
                .frame(width: BessieSettingsLayout.switchWidth, height: BessieSettingsLayout.switchHeight)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct BessieSettingsStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let rangeLabel: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                stepButton(icon: .minus, delta: -1, disabled: value <= range.lowerBound)
                Text("\(Int(value)) pt")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 64, minHeight: 28)
                    .background(BessieDesign.inset)
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(BessieDesign.border) }
                stepButton(icon: .plus, delta: 1, disabled: value >= range.upperBound)
            }
            Text(rangeLabel).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(BessieDesign.faint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value)) points")
    }

    private func stepButton(icon: BessieIcon, delta: Double, disabled: Bool) -> some View {
        Button { value = min(range.upperBound, max(range.lowerBound, value + delta)) } label: {
            BessieIconView(icon: icon, size: 12)
        }
        .buttonStyle(BessieSettingsIconButtonStyle())
        .disabled(disabled)
        .accessibilityLabel(delta < 0 ? "Decrease \(label)" : "Increase \(label)")
    }
}

private struct BessieSettingRow<Control: View>: View {
    let label: String
    let hint: String?
    @ViewBuilder let control: Control
    init(label: String, hint: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.hint = hint
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BessieDesign.strong)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .lineSpacing(2)
                        .foregroundStyle(BessieDesign.subtle)
                        .frame(maxWidth: BessieSettingsLayout.labelColumnWidth, alignment: .leading)
                }
            }
            .frame(width: BessieSettingsLayout.labelColumnWidth, alignment: .leading)
            Spacer().frame(width: BessieSettingsLayout.columnGap)
            control
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, BessieSettingsLayout.rowVerticalPadding)
        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
    }
}

private struct BessieDiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(BessieDesign.subtle)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
    }
}

private extension BessieStartupBehavior {
    var title: String { switch self { case .lastWorkspace: "Reopen last workspace"; case .workspaceChooser: "Show workspaces" } }
}

extension BessieThemeID {
    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Bessie Dark"
        case .light: "Bessie Light"
        case .catppuccinLatte: "Catppuccin Latte"
        case .catppuccinFrappe: "Catppuccin Frappé"
        case .catppuccinMacchiato: "Catppuccin Macchiato"
        case .catppuccinMocha: "Catppuccin Mocha"
        }
    }

    var schemeLabel: String {
        if self == .system { return "Adaptive" }
        return BessieThemeRegistry.preferredColorScheme(for: self) == .light ? "Light" : "Dark"
    }
}

private struct BessieThemeSwatches: View {
    let id: BessieThemeID

    var body: some View {
        let preview = BessieThemeRegistry.definition(for: id, systemScheme: .dark).preview
        HStack(spacing: 0) {
            ForEach(Array(preview.enumerated()), id: \.offset) { _, color in
                Rectangle().fill(color).frame(width: 8, height: 12)
            }
        }
        .overlay { Rectangle().stroke(BessieDesign.borderStrong, lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
}

private extension BessieDensity {
    var title: String { switch self { case .comfortable: "Comfortable"; case .compact: "Compact" } }
}

private extension BessieAppIcon {
    var title: String { switch self { case .dark: "Dark"; case .light: "Light" } }
}

extension BessieNotifications {
    var title: String {
        switch self {
        case .off: "Off"
        case .blockedOnly: "When work needs me"
        case .blockedAndDone: "Needs me, Done, and Idle"
        }
    }
}

private extension BessieMenuBarBadgePolicy {
    var title: String { switch self { case .needsYou: "Needs you"; case .needsYouAndUnknown: "Needs you + Unknown"; case .nothing: "Nothing" } }
}

private extension BessieMenuBarRowClickBehavior {
    var title: String { switch self { case .focusPane: "Focus pane"; case .openBessie: "Open Bessie" } }
}

struct BessieWindowSnapshotProbe: NSViewRepresentable {
    final class Coordinator { var captured = false }
    let role: String

    init(role: String = "main") {
        self.role = role
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let preview = ProcessInfo.processInfo.environment["BESSIE_DESIGN_PREVIEW"]?.lowercased()
        let capturesSheet = preview == "new-process"
            || preview == "command-palette"
            || preview == "project-launch-review"
            || preview == "menu-bar"
        let captureRole = preview == "menu-bar" ? "menu-bar" : "sheet"
        guard ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_PATH"] != nil,
              ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_TRIGGER"] == nil,
              (capturesSheet ? role == captureRole : role == "main")
        else { return view }
        let delay = Double(ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_DELAY"] ?? "3") ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !context.coordinator.captured else { return }
            context.coordinator.captured = true
            BessieWindowSnapshot.capture(window: view.window)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
enum BessieWindowSnapshot {
    static func captureWhenReady(
        registry: TerminalControllerRegistry,
        paneIDs: Set<String>,
        remainingAttempts: Int = 60,
        consecutiveReadyChecks: Int = 0
    ) {
        let visible = paneIDs.compactMap { registry.controllers[$0] }
        let ready = visible.count >= 2 && visible.allSatisfy { controller in
            if case .ready = controller.status { return true }
            return false
        }
        if ready, consecutiveReadyChecks >= 3 {
            capture()
        } else if remainingAttempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                captureWhenReady(
                    registry: registry,
                    paneIDs: paneIDs,
                    remainingAttempts: remainingAttempts - 1,
                    consecutiveReadyChecks: ready ? consecutiveReadyChecks + 1 : 0
                )
            }
        }
    }

    static func capture(window requestedWindow: NSWindow? = nil, path requestedPath: String? = nil) {
        guard let path = requestedPath ?? ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_PATH"],
              let window = requestedWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
              let content = window.contentView,
              content.bounds.width > 0,
              content.bounds.height > 0
        else { return }

        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        var bitmap: NSBitmapImageRep?
        if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "08",
           let requested = ProcessInfo.processInfo.environment["BESSIE_CAPTURE_FRAME"]?.split(separator: "x"),
           requested.count == 2, let width = Int(requested[0]), let height = Int(requested[1]),
           let scrollView = largestScrollView(in: content),
           let document = scrollView.documentView,
           let documentBitmap = document.bitmapImageRepForCachingDisplay(in: document.bounds),
           let windowImage = captureWindowImage(windowNumber: window.windowNumber) {
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                document.cacheDisplay(in: document.bounds, to: documentBitmap)
            }
            guard let stitched = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: stitched) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor(BessieDesign.background.currentColor).setFill()
                NSRect(x: 0, y: 0, width: width, height: height).fill()
                let windowWidth = min(windowImage.width, width)
                let windowHeight = min(windowImage.height, height)
                NSBitmapImageRep(cgImage: windowImage).draw(in: NSRect(
                    x: 0, y: height - windowHeight, width: windowWidth, height: windowHeight
                ))

                let scrollFrame = scrollView.convert(scrollView.bounds, to: content)
                let titlebarHeight = max(0, windowHeight - Int(content.bounds.height))
                let documentTop = CGFloat(titlebarHeight) + 72
                let documentWidth = min(CGFloat(documentBitmap.pixelsWide), scrollFrame.width)
                let documentHeight = min(CGFloat(documentBitmap.pixelsHigh), CGFloat(height) - documentTop)
                let documentRect = NSRect(
                    x: scrollFrame.minX,
                    y: CGFloat(height) - documentTop - documentHeight,
                    width: documentWidth,
                    height: documentHeight
                )
                NSColor(BessieDesign.background.currentColor).setFill()
                documentRect.fill()
                documentBitmap.draw(in: documentRect, from: NSRect(
                    x: 0,
                    y: CGFloat(documentBitmap.pixelsHigh) - documentHeight,
                    width: documentWidth,
                    height: documentHeight
                ), operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            }
            NSGraphicsContext.restoreGraphicsState()
            guard let bitmapData = stitched.bitmapData else { return }
            for y in 0..<height {
                let row = bitmapData.advanced(by: y * stitched.bytesPerRow)
                for x in 0..<width { row[x * 4 + 3] = 255 }
            }
            bitmap = stitched
        } else if let image = captureWindowImage(windowNumber: window.windowNumber),
           image.width >= Int(content.bounds.width.rounded(.down)),
           image.height >= Int(content.bounds.height.rounded(.down)) {
            bitmap = NSBitmapImageRep(cgImage: image)
        } else if let cached = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.displayIfNeeded()
            content.cacheDisplay(in: content.bounds, to: cached)
            bitmap = cached
        } else {
            bitmap = nil
        }
        if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "15",
           let requested = ProcessInfo.processInfo.environment["BESSIE_CAPTURE_FRAME"]?.split(separator: "x"),
           requested.count == 2, let width = Int(requested[0]), let height = Int(requested[1]),
           let source = bitmap,
           let composed = NSBitmapImageRep(
               bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
           ), let context = NSGraphicsContext(bitmapImageRep: composed) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor(BessieDesign.desk.currentColor).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            let sourceWidth = min(source.pixelsWide, width - 28)
            let sourceHeight = min(source.pixelsHigh, height - 32)
            source.draw(in: NSRect(
                x: width - sourceWidth - 14,
                y: height - sourceHeight - 32,
                width: sourceWidth,
                height: sourceHeight
            ))
            NSGraphicsContext.restoreGraphicsState()
            bitmap = composed
        } else if let requested = ProcessInfo.processInfo.environment["BESSIE_CAPTURE_FRAME"]?.split(separator: "x"),
           requested.count == 2, let width = Int(requested[0]), let height = Int(requested[1]),
           let source = bitmap,
           let normalized = NSBitmapImageRep(
               bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
           ), let context = NSGraphicsContext(bitmapImageRep: normalized) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor(BessieDesign.background.currentColor).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()
            if let bitmapData = normalized.bitmapData {
                for y in 0..<height {
                    let row = bitmapData.advanced(by: y * normalized.bytesPerRow)
                    for x in 0..<width { row[x * 4 + 3] = 255 }
                }
            }
            bitmap = normalized
        }
        guard let png = bitmap?.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url, options: .atomic)
        BessieDiagnosticLog.append("Window snapshot path=\(path) width=\(Int(content.bounds.width)) height=\(Int(content.bounds.height))")
    }

    private static func largestScrollView(in view: NSView) -> NSScrollView? {
        var scrollViews: [NSScrollView] = []
        func visit(_ candidate: NSView) {
            if let scrollView = candidate as? NSScrollView, scrollView.documentView != nil {
                scrollViews.append(scrollView)
            }
            candidate.subviews.forEach(visit)
        }
        visit(view)
        return scrollViews.max {
            ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0)
        }
    }

    private static func captureWindowImage(windowNumber: Int) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        return capture(
            .null,
            CGWindowListOption.optionIncludingWindow.rawValue,
            UInt32(windowNumber),
            (CGWindowImageOption.boundsIgnoreFraming.union(.bestResolution)).rawValue
        )?.takeRetainedValue()
    }

}
