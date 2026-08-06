import AppKit
import BessieCore
import Foundation
import UserNotifications

@MainActor
protocol BessieNotificationDelivering: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
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
    private var planners: [String: BessieNotificationPlanner] = [:]
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
        refreshOnInit: Bool
    ) {
        if let system = delivery as? SystemNotificationDelivery {
            center = system.center
        } else {
            center = nil
        }
        self.delivery = delivery
        self.settingsOpener = settingsOpener
        self.applicationBundleIdentifier = applicationBundleIdentifier
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
        activePaneID: String?
    ) {
        guard authorizationLoaded else { return }
        let connectionID = connection.id
        var planner = planners[connectionID] ?? BessieNotificationPlanner()
        let connectionLabel = ConnectionDisplayLabel(connection: connection).short
        let events = planner.events(
            for: panes,
            policy: policy,
            activePaneID: activePaneID,
            connectionLabel: connectionLabel
        )
        planners[connectionID] = planner
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
            let request = UNNotificationRequest(identifier: "\(connectionID):\(event.id)", content: content, trigger: nil)
            Task {
                do {
                    try await delivery.add(request)
                } catch {
                    operationError = "Bessie couldn't deliver a notification. \(error.localizedDescription)"
                    BessieDiagnosticLog.append("Notification delivery failed: \(String(reflecting: error))")
                }
            }
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
