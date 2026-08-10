import Combine
import Foundation
import Sparkle

struct BessieUpdateVersion: Equatable, Sendable {
    let shortVersion: String
    let buildVersion: String
}

enum BessieUpdateCheckKind: Equatable, Sendable {
    case background
    case manual
}

enum BessieUpdateFailureContext: Equatable, Sendable {
    case startup
    case background
    case manual
}

enum BessieUpdatePhase: Equatable, Sendable {
    case ineligible
    case idle
    case checking(BessieUpdateCheckKind)
    case readyToRestart(BessieUpdateVersion)
    case installing(BessieUpdateVersion)
    case failed(BessieUpdateFailureContext)
}

struct BessieUpdatePreferences: Equatable, Sendable {
    var automaticallyChecksForUpdates: Bool
    var automaticallyDownloadsAndInstallsUpdates: Bool
    var allowsAutomaticUpdates: Bool

    static let unavailable = BessieUpdatePreferences(
        automaticallyChecksForUpdates: false,
        automaticallyDownloadsAndInstallsUpdates: false,
        allowsAutomaticUpdates: false
    )
}

struct BessieUpdateState: Equatable, Sendable {
    var phase: BessieUpdatePhase
    var preferences: BessieUpdatePreferences
    var status: String?
}

struct BessieUpdateLaunchContext: Equatable, Sendable {
    private static let productionBundleIdentifier = "dev.bessie.app"
    private static let testModeKey = "BESSIE_UPDATE_TEST_MODE"
    private static let testFeedURLKey = "BESSIE_UPDATE_TEST_FEED_URL"

    let isEligible: Bool
    let feedURLOverride: String?

    init(bundleURL: URL, bundleIdentifier: String?, environment: [String: String]) {
        let testFeedURL = Self.validTestFeedURL(environment: environment)
        let usesUpdateTestContract = environment[Self.testModeKey] == "1" && testFeedURL != nil
        isEligible = usesUpdateTestContract || (
            bundleURL.pathExtension == "app"
                && bundleIdentifier == Self.productionBundleIdentifier
        )
        feedURLOverride = usesUpdateTestContract ? testFeedURL : nil
    }

    static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BessieUpdateLaunchContext {
        BessieUpdateLaunchContext(
            bundleURL: bundle.bundleURL,
            bundleIdentifier: bundle.bundleIdentifier,
            environment: environment
        )
    }

    static let eligibleForCoordinatorTests = BessieUpdateLaunchContext(
        bundleURL: URL(fileURLWithPath: "/tmp/BessieUpdateCoordinatorTests.xctest"),
        bundleIdentifier: nil,
        environment: [
            testModeKey: "1",
            testFeedURLKey: "http://127.0.0.1:1/appcast.xml",
        ]
    )

    private static func validTestFeedURL(environment: [String: String]) -> String? {
        guard environment[testModeKey] == "1",
              let value = environment[testFeedURLKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              url.user == nil,
              url.password == nil,
              scheme == "https" || (
                  scheme == "http" && ["127.0.0.1", "::1", "localhost"].contains(host)
              )
        else { return nil }
        return value
    }
}

@MainActor
protocol BessieUpdaterAdapterDelegate: AnyObject {
    func updaterDidBeginCheck(_ kind: BessieUpdateCheckKind)
    func updaterDidFindUpdate(_ version: BessieUpdateVersion)
    func updaterDidNotFindUpdate(_ kind: BessieUpdateCheckKind)
    func updaterDidAbort(_ error: Error, checkKind: BessieUpdateCheckKind)
    func updaterDidFinishCycle(_ kind: BessieUpdateCheckKind, error: Error?)
    func updaterAvailabilityDidChange()
    func updaterPreferencesDidChange()
    func updaterWillInstallOnQuit(
        _ version: BessieUpdateVersion,
        immediateInstallationHandler: @escaping () -> Void
    ) -> Bool
}

@MainActor
protocol BessieUpdaterAdapter: AnyObject {
    var delegate: BessieUpdaterAdapterDelegate? { get set }
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var allowsAutomaticUpdates: Bool { get }

    func start() throws
    func checkForUpdates()
}

@MainActor
final class BessieUpdateCoordinator: ObservableObject, BessieUpdaterAdapterDelegate {
    typealias AdapterFactory = @MainActor (String?) -> BessieUpdaterAdapter

    @Published private(set) var state: BessieUpdateState
    @Published private(set) var canCheckForUpdates = false

    private let adapter: BessieUpdaterAdapter?
    private var didAttemptStart = false
    private var didStart = false
    private var activeCycleReportedNoUpdate = false
    private var immediateInstallationHandler: (() -> Void)?

    convenience init(launchContext: BessieUpdateLaunchContext = .current()) {
        self.init(launchContext: launchContext) { feedURLOverride in
            SparkleUpdaterAdapter(feedURLOverride: feedURLOverride)
        }
    }

    init(launchContext: BessieUpdateLaunchContext, adapterFactory: AdapterFactory) {
        guard launchContext.isEligible else {
            adapter = nil
            state = BessieUpdateState(
                phase: .ineligible,
                preferences: .unavailable,
                status: nil
            )
            return
        }

        let adapter = adapterFactory(launchContext.feedURLOverride)
        self.adapter = adapter
        state = BessieUpdateState(
            phase: .idle,
            preferences: Self.preferences(from: adapter),
            status: nil
        )
        adapter.delegate = self
    }

    var canRestartToUpdate: Bool {
        guard immediateInstallationHandler != nil,
              case .readyToRestart = state.phase
        else { return false }
        return true
    }

    @discardableResult
    func start() -> Bool {
        guard let adapter else { return false }
        if didAttemptStart { return didStart }
        didAttemptStart = true
        do {
            try adapter.start()
            didStart = true
            refreshPreferences()
            refreshAvailability()
            return true
        } catch {
            didStart = false
            fail(.startup)
            return false
        }
    }

    @discardableResult
    func checkForUpdates() -> Bool {
        guard let adapter else { return false }
        refreshAvailability()
        guard canCheckForUpdates else { return false }
        state.phase = .checking(.manual)
        state.status = nil
        refreshAvailability()
        adapter.checkForUpdates()
        return true
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let adapter else { return }
        adapter.automaticallyChecksForUpdates = enabled
        refreshPreferences()
    }

    func setAutomaticallyDownloadsAndInstallsUpdates(_ enabled: Bool) {
        guard let adapter else { return }
        adapter.automaticallyDownloadsUpdates = enabled
        refreshPreferences()
    }

    @discardableResult
    func restartToUpdate() -> Bool {
        guard let handler = immediateInstallationHandler,
              case let .readyToRestart(version) = state.phase
        else { return false }

        immediateInstallationHandler = nil
        state.phase = .installing(version)
        state.status = "Installing Bessie \(version.shortVersion)…"
        handler()
        return true
    }

    func updaterDidBeginCheck(_ kind: BessieUpdateCheckKind) {
        guard !canRestartToUpdate else { return }
        activeCycleReportedNoUpdate = false
        state.phase = .checking(kind)
        state.status = nil
        refreshAvailability()
    }

    func updaterDidFindUpdate(_ version: BessieUpdateVersion) {
        guard !canRestartToUpdate else { return }
        activeCycleReportedNoUpdate = false
        state.phase = .idle
        state.status = "Preparing Bessie \(version.shortVersion)…"
        refreshAvailability()
    }

    func updaterDidNotFindUpdate(_ kind: BessieUpdateCheckKind) {
        guard !canRestartToUpdate else { return }
        activeCycleReportedNoUpdate = true
        state.phase = .idle
        state.status = kind == .manual ? "Bessie is up to date." : nil
        refreshAvailability()
    }

    func updaterDidAbort(_ error: Error, checkKind: BessieUpdateCheckKind) {
        guard !activeCycleReportedNoUpdate else { return }
        immediateInstallationHandler = nil
        fail(checkKind.failureContext)
    }

    func updaterDidFinishCycle(_ kind: BessieUpdateCheckKind, error: Error?) {
        if activeCycleReportedNoUpdate {
            activeCycleReportedNoUpdate = false
            state.phase = .idle
            return
        }
        if error != nil {
            immediateInstallationHandler = nil
            fail(kind.failureContext)
            return
        }

        switch state.phase {
        case .readyToRestart, .installing, .failed, .ineligible:
            break
        case .checking, .idle:
            state.phase = .idle
            state.status = nil
        }
        refreshAvailability()
    }

    func updaterAvailabilityDidChange() {
        refreshAvailability()
    }

    func updaterPreferencesDidChange() {
        refreshPreferences()
    }

    func updaterWillInstallOnQuit(
        _ version: BessieUpdateVersion,
        immediateInstallationHandler: @escaping () -> Void
    ) -> Bool {
        activeCycleReportedNoUpdate = false
        self.immediateInstallationHandler = immediateInstallationHandler
        state.phase = .readyToRestart(version)
        state.status = "Bessie \(version.shortVersion) (\(version.buildVersion)) is ready to install."
        refreshAvailability()
        return canRestartToUpdate
    }

    private func refreshAvailability() {
        guard let adapter, didStart else {
            canCheckForUpdates = false
            return
        }
        let phaseAllowsManualCheck = switch state.phase {
        case .idle, .failed(.background), .failed(.manual): true
        case .ineligible, .checking, .readyToRestart, .installing, .failed(.startup): false
        }
        canCheckForUpdates = adapter.canCheckForUpdates && phaseAllowsManualCheck
    }

    private func refreshPreferences() {
        guard let adapter else { return }
        state.preferences = Self.preferences(from: adapter)
    }

    private static func preferences(from adapter: BessieUpdaterAdapter) -> BessieUpdatePreferences {
        BessieUpdatePreferences(
            automaticallyChecksForUpdates: adapter.automaticallyChecksForUpdates,
            automaticallyDownloadsAndInstallsUpdates: adapter.automaticallyDownloadsUpdates,
            allowsAutomaticUpdates: adapter.allowsAutomaticUpdates
        )
    }

    private func fail(_ context: BessieUpdateFailureContext) {
        state.phase = .failed(context)
        state.status = switch context {
        case .startup:
            "Updates could not start. Restart Bessie to try again."
        case .background:
            "The automatic update check couldn’t be completed. Sparkle will retry automatically."
        case .manual:
            "The update check couldn’t be completed. Sparkle displayed the details."
        }
        refreshAvailability()
    }
}

private extension BessieUpdateCheckKind {
    var failureContext: BessieUpdateFailureContext {
        switch self {
        case .background: .background
        case .manual: .manual
        }
    }
}

@MainActor
private final class SparkleUpdaterAdapter: NSObject, BessieUpdaterAdapter, SPUUpdaterDelegate {
    weak var delegate: BessieUpdaterAdapterDelegate?

    private let feedURLOverride: String?
    private var activeCheckKind: BessieUpdateCheckKind = .background
    private var updaterController: SPUStandardUpdaterController!
    private var preferenceObservations: [NSKeyValueObservation] = []

    init(feedURLOverride: String?) {
        self.feedURLOverride = feedURLOverride
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        let updater = updaterController.updater
        preferenceObservations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.delegate?.updaterAvailabilityDidChange() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.delegate?.updaterPreferencesDidChange() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.delegate?.updaterPreferencesDidChange() }
            },
            updater.observe(\.allowsAutomaticUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.delegate?.updaterPreferencesDidChange() }
            },
        ]
    }

    var canCheckForUpdates: Bool { updaterController.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    var allowsAutomaticUpdates: Bool { updaterController.updater.allowsAutomaticUpdates }

    func start() throws {
        try updaterController.updater.start()
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURLOverride
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let kind = Self.kind(for: updateCheck)
        activeCheckKind = kind
        delegate?.updaterDidBeginCheck(kind)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        delegate?.updaterDidFindUpdate(Self.version(from: item))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        delegate?.updaterDidNotFindUpdate(activeCheckKind)
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        delegate?.updaterWillInstallOnQuit(
            Self.version(from: item),
            immediateInstallationHandler: immediateInstallHandler
        ) ?? false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        delegate?.updaterDidAbort(error, checkKind: activeCheckKind)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        let kind = Self.kind(for: updateCheck)
        delegate?.updaterDidFinishCycle(kind, error: error)
        activeCheckKind = .background
    }

    private static func kind(for updateCheck: SPUUpdateCheck) -> BessieUpdateCheckKind {
        updateCheck == .updatesInBackground ? .background : .manual
    }

    private static func version(from item: SUAppcastItem) -> BessieUpdateVersion {
        BessieUpdateVersion(
            shortVersion: item.displayVersionString,
            buildVersion: item.versionString
        )
    }
}
