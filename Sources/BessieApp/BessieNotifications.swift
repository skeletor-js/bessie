import AppKit
import BessieCore
import Foundation
import UserNotifications

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
    private(set) var attentionFallback: PendingNotificationRoute?

    mutating func enqueue(_ route: PendingNotificationRoute) {
        attentionFallback = nil
        pending = route
    }

    mutating func consume(_ route: PendingNotificationRoute) {
        guard pending?.id == route.id else { return }
        pending = nil
    }

    mutating func fallBackToAttention(_ route: PendingNotificationRoute) {
        guard pending?.id == route.id else { return }
        pending = nil
        attentionFallback = route
    }

    mutating func consumeAttentionFallback(_ route: PendingNotificationRoute) {
        guard attentionFallback?.id == route.id else { return }
        attentionFallback = nil
    }
}

@MainActor
final class BessieNotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var authorizationLoaded = false
    @Published private(set) var authorizationError: String?
    @Published private(set) var operationError: String?
    @Published private var routes = NotificationRouteQueue()

    private let center: UNUserNotificationCenter
    private var planners: [String: BessieNotificationPlanner] = [:]

    var pendingRoute: PendingNotificationRoute? { routes.pending }
    var attentionFallbackRoute: PendingNotificationRoute? { routes.attentionFallback }

    override init() {
        center = .current()
        super.init()
        center.delegate = self
        refreshAuthorization()
    }

    func refreshAuthorization() {
        Task {
            updateAuthorizationStatus(await center.notificationSettings().authorizationStatus)
            authorizationLoaded = true
        }
    }

    func requestAuthorization() {
        Task {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                operationError = nil
                updateAuthorizationStatus(await center.notificationSettings().authorizationStatus)
                authorizationLoaded = true
            } catch {
                updateAuthorizationStatus(await center.notificationSettings().authorizationStatus)
                authorizationLoaded = true
                operationError = "Bessie couldn't request notification permission. \(error.localizedDescription)"
                BessieDiagnosticLog.append("Notification authorization failed: \(String(reflecting: error))")
            }
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
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
                    try await center.add(request)
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

    func fallBackToAttention(for route: PendingNotificationRoute) {
        routes.fallBackToAttention(route)
    }

    func consumeAttentionFallback(_ route: PendingNotificationRoute) {
        routes.consumeAttentionFallback(route)
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
        guard let routed else { return }
        await MainActor.run { [weak self] in
            self?.routes.enqueue(PendingNotificationRoute(target: routed))
            NSApp.activate(ignoringOtherApps: true)
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
