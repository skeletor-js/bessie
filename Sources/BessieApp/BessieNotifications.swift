import AppKit
import BessieCore
import Foundation
import UserNotifications

@MainActor
protocol BessieNotificationDelivering: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

@MainActor
protocol BessieSystemSettingsOpening: AnyObject {
    func open(_ url: URL) -> Bool
}

@MainActor
private final class WorkspaceSystemSettingsOpener: BessieSystemSettingsOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private final class SystemNotificationDelivery: BessieNotificationDelivering {
    let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> UNAuthorizationStatus {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

enum TestNotificationStatus: Equatable {
    case idle
    case sending
    case delivered
    case denied
    case failed(String)
}

struct PendingNotificationRoute: Equatable, Identifiable {
    let id: UUID
    let target: RoutedPaneTarget

    init(id: UUID = UUID(), target: RoutedPaneTarget) {
        self.id = id
        self.target = target
    }
}

struct NotificationRouteQueue: Equatable {
    private(set) var pending: PendingNotificationRoute?

    mutating func enqueue(_ route: PendingNotificationRoute) {
        pending = route
    }

    mutating func consume(_ route: PendingNotificationRoute) {
        guard pending?.id == route.id else { return }
        pending = nil
    }
}

@MainActor
final class BessieNotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private enum NotificationCondition: Equatable {
        case blocked
        case settled
    }

    private struct PresentationFingerprint: Equatable {
        let identity: String
        let location: String
        let connectionLabel: String
    }

    private struct CurrentNotification: Equatable {
        let condition: NotificationCondition
        let target: PaneOpenTarget
        let presentationFingerprint: PresentationFingerprint
    }

    private struct TrackedNotification: Equatable {
        let identifier: String
        let token: UUID
        let condition: NotificationCondition
        let target: PaneOpenTarget
        let presentationFingerprint: PresentationFingerprint
    }

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var authorizationLoaded = false
    @Published private(set) var authorizationError: String?
    @Published private(set) var operationError: String?
    @Published private(set) var testNotificationStatus: TestNotificationStatus = .idle
    @Published private var routes = NotificationRouteQueue()

    private let center: UNUserNotificationCenter?
    private let delivery: BessieNotificationDelivering
    private let settingsOpener: BessieSystemSettingsOpening
    private let applicationBundleIdentifier: String?
    private let deliveryDelay: @MainActor () async -> Void
    private var planners: [String: BessieNotificationPlanner] = [:]
    private var suppressedIncarnations: Set<BessiePaneIncarnation> = []
    private var queuedDeliveries: [BessiePaneIncarnation: Task<Void, Never>] = [:]
    private var trackedNotifications: [BessiePaneIncarnation: TrackedNotification] = [:]
    var activationHandler: (() -> Void)?

    var pendingRoute: PendingNotificationRoute? { routes.pending }

    override convenience init() {
        self.init(
            delivery: SystemNotificationDelivery(),
            settingsOpener: WorkspaceSystemSettingsOpener(),
            applicationBundleIdentifier: Bundle.main.bundleIdentifier,
            refreshOnInit: true
        )
    }

    convenience init(delivery: BessieNotificationDelivering, refreshOnInit: Bool) {
        self.init(
            delivery: delivery,
            settingsOpener: WorkspaceSystemSettingsOpener(),
            applicationBundleIdentifier: Bundle.main.bundleIdentifier,
            refreshOnInit: refreshOnInit
        )
    }

    init(
        delivery: BessieNotificationDelivering,
        settingsOpener: BessieSystemSettingsOpening,
        applicationBundleIdentifier: String?,
        refreshOnInit: Bool,
        deliveryDelay: @escaping @MainActor () async -> Void = {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    ) {
        if let system = delivery as? SystemNotificationDelivery {
            center = system.center
        } else {
            center = nil
        }
        self.delivery = delivery
        self.settingsOpener = settingsOpener
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.deliveryDelay = deliveryDelay
        super.init()
        center?.delegate = self
        if refreshOnInit { refreshAuthorization() }
    }

    func refreshAuthorization() {
        Task {
            updateAuthorizationStatus(await delivery.authorizationStatus())
            authorizationLoaded = true
        }
    }

    func requestAuthorization() {
        Task {
            do {
                let status = try await delivery.requestAuthorization()
                operationError = nil
                updateAuthorizationStatus(status)
                authorizationLoaded = true
            } catch {
                updateAuthorizationStatus(await delivery.authorizationStatus())
                authorizationLoaded = true
                operationError = "Bessie couldn't request notification permission. \(error.localizedDescription)"
                BessieDiagnosticLog.append("Notification authorization failed: \(String(reflecting: error))")
            }
        }
    }

    func openNotificationSettings() {
        for url in Self.notificationSettingsURLs(applicationBundleIdentifier: applicationBundleIdentifier) {
            if settingsOpener.open(url) { return }
        }
    }

    static func notificationSettingsURLs(applicationBundleIdentifier: String?) -> [URL] {
        let general = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        guard let applicationBundleIdentifier,
              !applicationBundleIdentifier.isEmpty,
              var components = URLComponents(
                  string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
              )
        else { return [general] }
        components.queryItems = [URLQueryItem(name: "id", value: applicationBundleIdentifier)]
        guard let application = components.url else { return [general] }
        return [application, general]
    }

    func sendTestNotification(target: RoutedPaneTarget?) async {
        testNotificationStatus = .sending
        var status = await delivery.authorizationStatus()
        if status == .notDetermined {
            do {
                status = try await delivery.requestAuthorization()
            } catch {
                let message = "Bessie couldn't request notification permission. \(error.localizedDescription)"
                operationError = message
                testNotificationStatus = .failed(message)
                updateAuthorizationStatus(await delivery.authorizationStatus())
                authorizationLoaded = true
                BessieDiagnosticLog.append("Test notification authorization failed")
                return
            }
        }
        updateAuthorizationStatus(status)
        authorizationLoaded = true
        guard status.allowsDelivery else {
            testNotificationStatus = .denied
            operationError = status == .denied ? "Notifications are blocked in System Settings." : "Notifications aren't available."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Bessie test notification"
        content.body = "Notifications are ready. No terminal content is included."
        content.sound = .default
        content.userInfo = target.map { BessieNotificationDeepLink(target: $0).userInfo } ?? ["bessie_test": true]
        let request = UNNotificationRequest(
            identifier: "bessie.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await delivery.add(request)
            operationError = nil
            testNotificationStatus = .delivered
            BessieDiagnosticLog.append("Test notification delivered target=\(target == nil ? "none" : "active-pane")")
        } catch {
            let message = "Bessie couldn't deliver the test notification. \(error.localizedDescription)"
            operationError = message
            testNotificationStatus = .failed(message)
            BessieDiagnosticLog.append("Test notification delivery failed")
        }
    }

    func reconcile(
        connection: BessieConnectionDefinition,
        panes: [BessieNotificationPane],
        policy: BessieNotifications,
        activePaneID: String?,
        snoozedIncarnations: Set<BessiePaneIncarnation> = []
    ) {
        let connectionID = connection.id
        let connectionLabel = ConnectionDisplayLabel(connection: connection).short
        let currentIncarnations = Dictionary(uniqueKeysWithValues: panes.map {
            ($0.paneID, BessiePaneIncarnation(connectionID: connectionID, paneID: $0.paneID, terminalID: $0.terminalID))
        })
        let currentSuppressed = Set(currentIncarnations.values.filter(snoozedIncarnations.contains))
        updateSuppressions(connectionID: connectionID, current: currentSuppressed)
        let currentNotifications: [BessiePaneIncarnation: CurrentNotification] = Dictionary(
            uniqueKeysWithValues: panes.compactMap { pane -> (BessiePaneIncarnation, CurrentNotification)? in
                guard pane.paneID != activePaneID,
                      let incarnation = currentIncarnations[pane.paneID],
                      !currentSuppressed.contains(incarnation),
                      let condition = Self.notificationCondition(for: pane.state, policy: policy)
                else { return nil }
                return (
                    incarnation,
                    CurrentNotification(
                        condition: condition,
                        target: pane.target,
                        presentationFingerprint: PresentationFingerprint(
                            identity: pane.identity,
                            location: pane.location,
                            connectionLabel: connectionLabel
                        )
                    )
                )
            }
        )
        let staleIncarnations = trackedNotifications.compactMap { incarnation, tracked -> BessiePaneIncarnation? in
            guard incarnation.connectionID == connectionID else { return nil }
            let current = currentNotifications[incarnation]
            return current?.condition != tracked.condition
                || current?.target != tracked.target
                || current?.presentationFingerprint != tracked.presentationFingerprint
                ? incarnation : nil
        }
        staleIncarnations.forEach(invalidate(_:))
        var planner = planners[connectionID] ?? BessieNotificationPlanner()
        let events = planner.events(
            for: panes,
            policy: policy,
            activePaneID: activePaneID,
            suppressedPaneIDs: Set(currentSuppressed.map(\.paneID)),
            connectionLabel: connectionLabel
        )
        planners[connectionID] = planner
        guard authorizationLoaded else { return }
        guard authorizationStatus.allowsDelivery else { return }

        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            let routed = RoutedPaneTarget(
                connectionID: connectionID,
                workspaceID: event.target.workspaceID,
                tabID: event.target.tabID,
                paneID: event.target.paneID
            )
            content.userInfo = BessieNotificationDeepLink(target: routed).userInfo
            guard let incarnation = currentIncarnations[event.target.paneID],
                  incarnation.terminalID == event.terminalID,
                  let condition = Self.notificationCondition(for: event.state, policy: policy),
                  let current = currentNotifications[incarnation],
                  current.condition == condition,
                  current.target == event.target
            else { continue }
            queue(
                UNNotificationRequest(identifier: "\(connectionID):\(event.id)", content: content, trigger: nil),
                incarnation: incarnation,
                condition: condition,
                target: current.target,
                presentationFingerprint: current.presentationFingerprint
            )
        }
    }

    func reconcilePolicy(_ policy: BessieNotifications) {
        let staleIncarnations = trackedNotifications.compactMap { incarnation, tracked in
            Self.policy(policy, allows: tracked.condition) ? nil : incarnation
        }
        staleIncarnations.forEach(invalidate(_:))
    }

    func retainConnections(_ connectionIDs: Set<String>) {
        let staleIncarnations = trackedNotifications.keys.filter { !connectionIDs.contains($0.connectionID) }
        staleIncarnations.forEach(invalidate(_:))
        planners = planners.filter { connectionIDs.contains($0.key) }
        suppressedIncarnations = Set(suppressedIncarnations.filter { connectionIDs.contains($0.connectionID) })
    }

    private func updateSuppressions(connectionID: String, current: Set<BessiePaneIncarnation>) {
        let previous = Set(suppressedIncarnations.filter { $0.connectionID == connectionID })
        suppressedIncarnations.subtract(previous)
        suppressedIncarnations.formUnion(current)
        for incarnation in current.subtracting(previous) {
            invalidate(incarnation)
        }
    }

    func suppressImmediately(_ incarnation: BessiePaneIncarnation) {
        guard suppressedIncarnations.insert(incarnation).inserted else { return }
        invalidate(incarnation)
    }

    private func queue(
        _ request: UNNotificationRequest,
        incarnation: BessiePaneIncarnation,
        condition: NotificationCondition,
        target: PaneOpenTarget,
        presentationFingerprint: PresentationFingerprint
    ) {
        invalidate(incarnation)
        let token = UUID()
        trackedNotifications[incarnation] = TrackedNotification(
            identifier: request.identifier,
            token: token,
            condition: condition,
            target: target,
            presentationFingerprint: presentationFingerprint
        )
        queuedDeliveries[incarnation] = Task { [weak self] in
            guard let self else { return }
            await self.deliveryDelay()
            guard !Task.isCancelled,
                  self.trackedNotifications[incarnation]?.token == token
            else { return }
            do {
                try await self.delivery.add(request)
                guard !Task.isCancelled, self.trackedNotifications[incarnation]?.token == token else {
                    self.removeNotification(identifier: request.identifier)
                    return
                }
                self.queuedDeliveries[incarnation] = nil
                self.operationError = nil
            } catch {
                guard self.trackedNotifications[incarnation]?.token == token else { return }
                self.trackedNotifications[incarnation] = nil
                self.queuedDeliveries[incarnation] = nil
                self.operationError = "Bessie couldn't deliver a notification. \(error.localizedDescription)"
                BessieDiagnosticLog.append("Notification delivery failed: \(String(reflecting: error))")
            }
        }
    }

    private func invalidate(_ incarnation: BessiePaneIncarnation) {
        queuedDeliveries.removeValue(forKey: incarnation)?.cancel()
        guard let tracked = trackedNotifications.removeValue(forKey: incarnation) else { return }
        removeNotification(identifier: tracked.identifier)
    }

    private func removeNotification(identifier: String) {
        delivery.removePendingNotificationRequests(withIdentifiers: [identifier])
        delivery.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func notificationCondition(
        for state: AgentSemanticState,
        policy: BessieNotifications
    ) -> NotificationCondition? {
        switch (policy, state) {
        case (.blockedOnly, .blocked), (.blockedAndDone, .blocked): .blocked
        case (.blockedAndDone, .done), (.blockedAndDone, .idle): .settled
        default: nil
        }
    }

    private static func policy(_ policy: BessieNotifications, allows condition: NotificationCondition) -> Bool {
        switch (policy, condition) {
        case (.blockedOnly, .blocked), (.blockedAndDone, _): true
        default: false
        }
    }

    func consumePendingRoute(_ route: PendingNotificationRoute) {
        routes.consume(route)
    }

    func enqueueRoute(_ target: RoutedPaneTarget) {
        routes.enqueue(PendingNotificationRoute(target: target))
    }

    func clearOperationError() {
        operationError = nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let routed = BessieNotificationDeepLink(userInfo: response.notification.request.content.userInfo)?.target
        await MainActor.run { [weak self] in
            if let routed {
                self?.routes.enqueue(PendingNotificationRoute(target: routed))
            }
            self?.activationHandler?()
        }
    }

    private func updateAuthorizationStatus(_ status: UNAuthorizationStatus) {
        let error = status == .denied ? "Notifications are blocked in System Settings." : nil
        guard authorizationStatus != status || authorizationError != error else { return }
        let wasDenied = authorizationStatus == .denied
        authorizationStatus = status
        authorizationError = error
        if status == .denied, !wasDenied { BessieDiagnosticLog.append("Notification authorization denied") }
    }
}

private extension UNAuthorizationStatus {
    var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }
}
