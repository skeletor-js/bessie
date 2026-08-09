import Foundation
import XCTest
@testable import BessieApp

@MainActor
final class BessieUpdateCoordinatorTests: XCTestCase {
    func testEligibleCoordinatorStartsOneRetainedAdapterExactlyOnce() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeCoordinator(factory: factory)

        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertEqual(coordinator.state.phase, .idle)
        XCTAssertTrue(coordinator.start())
        XCTAssertTrue(coordinator.start())

        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertEqual(factory.adapter.startCount, 1)
    }

    func testInitiallyUnavailableAdapterNeverPublishesOrPerformsAFalseEnabledCheck() {
        let factory = RecordingUpdaterFactory()
        factory.adapter.canCheckForUpdates = false
        let coordinator = makeCoordinator(factory: factory)

        XCTAssertFalse(coordinator.canCheckForUpdates)
        XCTAssertTrue(coordinator.start())
        XCTAssertFalse(coordinator.canCheckForUpdates)
        XCTAssertFalse(coordinator.checkForUpdates())
        XCTAssertEqual(factory.adapter.checkCount, 0)
    }

    func testSparkleAvailabilityTransitionsRefreshPublishedCoordinatorAvailability() {
        let factory = RecordingUpdaterFactory()
        factory.adapter.canCheckForUpdates = false
        let coordinator = makeStartedCoordinator(factory: factory)
        XCTAssertFalse(coordinator.canCheckForUpdates)

        factory.adapter.sendAvailabilityChanged(true)
        XCTAssertTrue(coordinator.canCheckForUpdates)

        factory.adapter.sendAvailabilityChanged(false)
        XCTAssertFalse(coordinator.canCheckForUpdates)
        XCTAssertFalse(coordinator.checkForUpdates())
        XCTAssertEqual(factory.adapter.checkCount, 0)
    }

    func testManualCheckRevalidatesLiveAvailabilityBeforeInvokingSparkle() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)
        XCTAssertTrue(coordinator.canCheckForUpdates)

        factory.adapter.canCheckForUpdates = false

        XCTAssertFalse(coordinator.checkForUpdates())
        XCTAssertFalse(coordinator.canCheckForUpdates)
        XCTAssertEqual(factory.adapter.checkCount, 0)
        XCTAssertEqual(coordinator.state.phase, .idle)
    }

    func testIneligibleDevelopmentAndTestExecutablesNeverCreateAnUpdater() {
        let development = BessieUpdateLaunchContext(
            bundleURL: URL(fileURLWithPath: "/tmp/bessie/.build/debug/BessieApp"),
            bundleIdentifier: nil,
            environment: [:]
        )
        let testExecutable = BessieUpdateLaunchContext(
            bundleURL: URL(fileURLWithPath: "/tmp/bessie/.build/debug/BessiePackageTests.xctest"),
            bundleIdentifier: "dev.bessie.tests",
            environment: [:]
        )

        for context in [development, testExecutable] {
            let factory = RecordingUpdaterFactory()
            let coordinator = BessieUpdateCoordinator(
                launchContext: context,
                adapterFactory: factory.make
            )

            XCTAssertEqual(coordinator.state.phase, .ineligible)
            XCTAssertFalse(coordinator.start())
            XCTAssertFalse(coordinator.checkForUpdates())
            XCTAssertEqual(factory.makeCount, 0)
        }
    }

    func testOnlyPackagedProductionAppOrExplicitUpdateTestContractIsEligible() {
        let packaged = BessieUpdateLaunchContext(
            bundleURL: URL(fileURLWithPath: "/Applications/Bessie.app"),
            bundleIdentifier: "dev.bessie.app",
            environment: [:]
        )
        let wrongIdentity = BessieUpdateLaunchContext(
            bundleURL: URL(fileURLWithPath: "/Applications/Bessie.app"),
            bundleIdentifier: "dev.bessie.app.verify",
            environment: [:]
        )
        let incompleteTestContract = BessieUpdateLaunchContext(
            bundleURL: URL(fileURLWithPath: "/tmp/BessieUpdateTests.xctest"),
            bundleIdentifier: nil,
            environment: ["BESSIE_UPDATE_TEST_MODE": "1"]
        )
        let explicitTestContract = BessieUpdateLaunchContext(
            bundleURL: URL(fileURLWithPath: "/tmp/BessieUpdateTests.xctest"),
            bundleIdentifier: nil,
            environment: [
                "BESSIE_UPDATE_TEST_MODE": "1",
                "BESSIE_UPDATE_TEST_FEED_URL": "http://127.0.0.1:8765/appcast.xml",
            ]
        )

        XCTAssertTrue(packaged.isEligible)
        XCTAssertNil(packaged.feedURLOverride)
        XCTAssertFalse(wrongIdentity.isEligible)
        XCTAssertFalse(incompleteTestContract.isEligible)
        XCTAssertTrue(explicitTestContract.isEligible)
        XCTAssertEqual(explicitTestContract.feedURLOverride, "http://127.0.0.1:8765/appcast.xml")
    }

    func testFeedOverrideIsUnavailableOutsideExplicitUpdateTestContract() {
        let environment = ["BESSIE_UPDATE_TEST_FEED_URL": "https://attacker.invalid/appcast.xml"]
        let packaged = BessieUpdateLaunchContext(
            bundleURL: URL(fileURLWithPath: "/Applications/Bessie.app"),
            bundleIdentifier: "dev.bessie.app",
            environment: environment
        )

        XCTAssertTrue(packaged.isEligible)
        XCTAssertNil(packaged.feedURLOverride)
    }

    func testUpdateTestContractRejectsRemoteHTTPAndCredentialBearingFeeds() {
        for feedURL in [
            "http://example.com/appcast.xml",
            "https://user:password@example.com/appcast.xml",
            "not a URL",
        ] {
            let context = BessieUpdateLaunchContext(
                bundleURL: URL(fileURLWithPath: "/tmp/BessieUpdateTests.xctest"),
                bundleIdentifier: nil,
                environment: [
                    "BESSIE_UPDATE_TEST_MODE": "1",
                    "BESSIE_UPDATE_TEST_FEED_URL": feedURL,
                ]
            )
            XCTAssertFalse(context.isEligible, feedURL)
            XCTAssertNil(context.feedURLOverride, feedURL)
        }
    }

    func testStartupFailureIsSanitizedAndDoesNotRetryOrCheck() {
        let factory = RecordingUpdaterFactory()
        factory.adapter.startError = NSError(
            domain: "secret.example",
            code: 73,
            userInfo: [NSLocalizedDescriptionKey: "token=abc123 /Users/jordan/private-feed.xml"]
        )
        let coordinator = makeCoordinator(factory: factory)

        XCTAssertFalse(coordinator.start())
        XCTAssertFalse(coordinator.start())
        XCTAssertFalse(coordinator.checkForUpdates())
        XCTAssertEqual(factory.adapter.startCount, 1)
        assertSanitized(coordinator.state.status)
        XCTAssertEqual(coordinator.state.phase.failureContext, .startup)
    }

    func testManualCheckWorksWhenAutomaticChecksAreDisabledAndUsesSparklePreferences() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeCoordinator(factory: factory)
        XCTAssertTrue(coordinator.start())

        coordinator.setAutomaticallyChecksForUpdates(false)
        coordinator.setAutomaticallyDownloadsAndInstallsUpdates(false)

        XCTAssertFalse(coordinator.state.preferences.automaticallyChecksForUpdates)
        XCTAssertFalse(coordinator.state.preferences.automaticallyDownloadsAndInstallsUpdates)
        XCTAssertTrue(coordinator.state.preferences.allowsAutomaticUpdates)
        XCTAssertTrue(coordinator.checkForUpdates())
        XCTAssertEqual(factory.adapter.checkCount, 1)
        XCTAssertEqual(coordinator.state.phase, .checking(.manual))
    }

    func testSparkleOriginatedPreferenceChangesRefreshPublishedValueState() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)

        factory.adapter.automaticallyChecksForUpdates = false
        factory.adapter.automaticallyDownloadsUpdates = false
        factory.adapter.allowsAutomaticUpdates = false
        factory.adapter.sendPreferencesChanged()

        XCTAssertEqual(coordinator.state.preferences, BessieUpdatePreferences(
            automaticallyChecksForUpdates: false,
            automaticallyDownloadsAndInstallsUpdates: false,
            allowsAutomaticUpdates: false
        ))
    }

    func testTransitionOrderingDoesNotExposeRestartBeforeInstallOnQuitCallback() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)
        let version = BessieUpdateVersion(shortVersion: "1.2.0", buildVersion: "120")

        factory.adapter.sendCheckStarted(.background)
        XCTAssertEqual(coordinator.state.phase, .checking(.background))
        factory.adapter.sendFound(version)
        XCTAssertEqual(coordinator.state.phase, .idle)
        XCTAssertFalse(coordinator.canRestartToUpdate)

        var installs = 0
        XCTAssertTrue(factory.adapter.sendWillInstall(version) { installs += 1 })
        XCTAssertEqual(coordinator.state.phase, .readyToRestart(version))
        XCTAssertTrue(coordinator.canRestartToUpdate)

        factory.adapter.sendFinished(.background, error: nil)
        XCTAssertEqual(coordinator.state.phase, .readyToRestart(version))
        XCTAssertTrue(coordinator.canRestartToUpdate)
        XCTAssertEqual(installs, 0)
    }

    func testFinishedFoundUpdateWithoutInstallOnQuitReadinessClearsTransientStatus() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)
        let version = BessieUpdateVersion(shortVersion: "1.2.0", buildVersion: "120")

        factory.adapter.sendCheckStarted(.manual)
        factory.adapter.sendFound(version)
        XCTAssertNotNil(coordinator.state.status)
        factory.adapter.sendFinished(.manual, error: nil)

        XCTAssertEqual(coordinator.state.phase, .idle)
        XCTAssertNil(coordinator.state.status)
        XCTAssertFalse(coordinator.canRestartToUpdate)
    }

    func testDuplicateInstallCallbacksReplaceRatherThanMultiplyOneShotHandler() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)
        let first = BessieUpdateVersion(shortVersion: "1.2.0", buildVersion: "120")
        let second = BessieUpdateVersion(shortVersion: "1.2.1", buildVersion: "121")
        var firstInstalls = 0
        var secondInstalls = 0

        XCTAssertTrue(factory.adapter.sendWillInstall(first) { firstInstalls += 1 })
        XCTAssertTrue(factory.adapter.sendWillInstall(second) { secondInstalls += 1 })
        XCTAssertEqual(coordinator.state.phase, .readyToRestart(second))

        XCTAssertTrue(coordinator.restartToUpdate())
        XCTAssertFalse(coordinator.restartToUpdate())
        XCTAssertEqual(firstInstalls, 0)
        XCTAssertEqual(secondInstalls, 1)
        XCTAssertEqual(coordinator.state.phase, .installing(second))
        XCTAssertFalse(coordinator.canRestartToUpdate)
    }

    func testAdapterDeclinesInstallOwnershipWhenNoCoordinatorCanRetainHandler() {
        let factory = RecordingUpdaterFactory()
        var coordinator: BessieUpdateCoordinator? = makeStartedCoordinator(factory: factory)
        weak let weakCoordinator = coordinator
        coordinator = nil
        XCTAssertNil(weakCoordinator)

        let version = BessieUpdateVersion(shortVersion: "1.2.0", buildVersion: "120")
        var installs = 0
        XCTAssertFalse(factory.adapter.sendWillInstall(version) { installs += 1 })
        XCTAssertEqual(installs, 0)
    }

    func testAuthorizationCancellationStaysConsumedUntilAnIndependentFutureCycleSuppliesANewHandler() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)
        let version = BessieUpdateVersion(shortVersion: "1.2.0", buildVersion: "120")
        var firstAttempts = 0
        var retryAttempts = 0
        let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)

        XCTAssertTrue(factory.adapter.sendWillInstall(version) { firstAttempts += 1 })
        XCTAssertTrue(coordinator.restartToUpdate())
        factory.adapter.sendAbort(cancellation, kind: .background)
        factory.adapter.sendFinished(.background, error: cancellation)

        XCTAssertFalse(coordinator.canRestartToUpdate)
        XCTAssertFalse(coordinator.restartToUpdate())
        XCTAssertEqual(firstAttempts, 1)

        factory.adapter.sendCheckStarted(.background)
        XCTAssertTrue(factory.adapter.sendWillInstall(version) { retryAttempts += 1 })
        XCTAssertTrue(coordinator.restartToUpdate())
        XCTAssertEqual(retryAttempts, 1)
    }

    func testDefinitiveCycleErrorClearsUninvokedReadyHandler() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)
        let version = BessieUpdateVersion(shortVersion: "1.2.0", buildVersion: "120")
        var installs = 0
        XCTAssertTrue(factory.adapter.sendWillInstall(version) { installs += 1 })

        factory.adapter.sendFinished(
            .background,
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        )

        XCTAssertFalse(coordinator.canRestartToUpdate)
        XCTAssertFalse(coordinator.restartToUpdate())
        XCTAssertEqual(installs, 0)
        XCTAssertEqual(coordinator.state.phase.failureContext, .background)
    }

    func testBackgroundNoUpdateIsQuietWhileManualNoUpdateHasSanitizedStatus() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)
        let expectedNoUpdateError = NSError(domain: "SUSparkleErrorDomain", code: 1001)

        factory.adapter.sendCheckStarted(.background)
        factory.adapter.sendNoUpdate(.background)
        factory.adapter.sendAbort(expectedNoUpdateError, kind: .background)
        factory.adapter.sendFinished(.background, error: expectedNoUpdateError)
        XCTAssertEqual(coordinator.state.phase, .idle)
        XCTAssertNil(coordinator.state.status)

        XCTAssertTrue(coordinator.checkForUpdates())
        factory.adapter.sendNoUpdate(.manual)
        factory.adapter.sendAbort(expectedNoUpdateError, kind: .manual)
        factory.adapter.sendFinished(.manual, error: expectedNoUpdateError)
        XCTAssertEqual(coordinator.state.phase, .idle)
        XCTAssertEqual(coordinator.state.status, "Bessie is up to date.")
    }

    func testBackgroundAndManualFailuresAreDistinctAndNeverExposeSensitiveErrorText() {
        let factory = RecordingUpdaterFactory()
        let coordinator = makeStartedCoordinator(factory: factory)
        let sensitiveError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorUserAuthenticationRequired,
            userInfo: [
                NSURLErrorKey: URL(string: "https://user:secret@example.com/private/appcast.xml")!,
                NSLocalizedDescriptionKey: "Authorization secret in /Users/jordan/Library/Feeds/appcast.xml",
            ]
        )

        factory.adapter.sendAbort(sensitiveError, kind: .background)
        XCTAssertEqual(coordinator.state.phase.failureContext, .background)
        assertSanitized(coordinator.state.status)

        factory.adapter.sendCheckStarted(.manual)
        factory.adapter.sendAbort(sensitiveError, kind: .manual)
        XCTAssertEqual(coordinator.state.phase.failureContext, .manual)
        assertSanitized(coordinator.state.status)
    }

    private func makeCoordinator(factory: RecordingUpdaterFactory) -> BessieUpdateCoordinator {
        BessieUpdateCoordinator(
            launchContext: .eligibleForCoordinatorTests,
            adapterFactory: factory.make
        )
    }

    private func makeStartedCoordinator(factory: RecordingUpdaterFactory) -> BessieUpdateCoordinator {
        let coordinator = makeCoordinator(factory: factory)
        XCTAssertTrue(coordinator.start())
        return coordinator
    }

    private func assertSanitized(_ status: String?, file: StaticString = #filePath, line: UInt = #line) {
        let status = status ?? ""
        XCTAssertFalse(status.isEmpty, file: file, line: line)
        for sensitive in ["abc123", "secret", "jordan", "appcast.xml", "example.com", "/Users/"] {
            XCTAssertFalse(status.localizedCaseInsensitiveContains(sensitive), status, file: file, line: line)
        }
    }
}

@MainActor
private final class RecordingUpdaterFactory {
    let adapter = RecordingUpdaterAdapter()
    private(set) var makeCount = 0

    func make(feedURLOverride: String?) -> BessieUpdaterAdapter {
        makeCount += 1
        adapter.feedURLOverride = feedURLOverride
        return adapter
    }
}

@MainActor
private final class RecordingUpdaterAdapter: BessieUpdaterAdapter {
    weak var delegate: BessieUpdaterAdapterDelegate?
    var feedURLOverride: String?
    var startError: Error?
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = true
    var allowsAutomaticUpdates = true
    private(set) var startCount = 0
    private(set) var checkCount = 0

    func start() throws {
        startCount += 1
        if let startError { throw startError }
    }

    func checkForUpdates() {
        checkCount += 1
    }

    func sendCheckStarted(_ kind: BessieUpdateCheckKind) {
        delegate?.updaterDidBeginCheck(kind)
    }

    func sendFound(_ version: BessieUpdateVersion) {
        delegate?.updaterDidFindUpdate(version)
    }

    func sendNoUpdate(_ kind: BessieUpdateCheckKind) {
        delegate?.updaterDidNotFindUpdate(kind)
    }

    func sendAbort(_ error: Error, kind: BessieUpdateCheckKind) {
        delegate?.updaterDidAbort(error, checkKind: kind)
    }

    func sendFinished(_ kind: BessieUpdateCheckKind, error: Error?) {
        delegate?.updaterDidFinishCycle(kind, error: error)
    }

    func sendPreferencesChanged() {
        delegate?.updaterPreferencesDidChange()
    }

    func sendAvailabilityChanged(_ available: Bool) {
        canCheckForUpdates = available
        delegate?.updaterAvailabilityDidChange()
    }

    func sendWillInstall(_ version: BessieUpdateVersion, handler: @escaping () -> Void) -> Bool {
        delegate?.updaterWillInstallOnQuit(version, immediateInstallationHandler: handler) ?? false
    }
}

private extension BessieUpdatePhase {
    var failureContext: BessieUpdateFailureContext? {
        guard case let .failed(context) = self else { return nil }
        return context
    }
}
