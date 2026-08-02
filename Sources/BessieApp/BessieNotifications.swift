import AppKit
import BessieCore
import Foundation
import UserNotifications

@MainActor
final class BessieNotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var authorizationError: String?
    @Published private(set) var pendingTarget: RoutedPaneTarget?

    private let center: UNUserNotificationCenter
    private var planners: [String: BessieNotificationPlanner] = [:]

    override init() {
        center = .current()
        super.init()
        center.delegate = self
        refreshAuthorization()
    }

    func refreshAuthorization() {
        Task {
            updateAuthorizationStatus(await center.notificationSettings().authorizationStatus)
        }
    }

    func requestAuthorization() {
        Task {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                updateAuthorizationStatus(await center.notificationSettings().authorizationStatus)
            } catch {
                authorizationStatus = await center.notificationSettings().authorizationStatus
                authorizationError = "Bessie couldn't request notification permission. \(error.localizedDescription)"
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
                    authorizationError = "Bessie couldn't deliver a notification. \(error.localizedDescription)"
                    BessieDiagnosticLog.append("Notification delivery failed: \(String(reflecting: error))")
                }
            }
        }
    }

    func consumePendingTarget(_ target: RoutedPaneTarget) {
        guard pendingTarget == target else { return }
        pendingTarget = nil
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
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let routed = BessieNotificationDeepLink(userInfo: response.notification.request.content.userInfo)?.target
        completionHandler()
        guard let routed else { return }
        Task { @MainActor [weak self] in
            self?.pendingTarget = routed
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateAuthorizationStatus(_ status: UNAuthorizationStatus) {
        authorizationStatus = status
        if status == .denied {
            authorizationError = "Notifications are blocked in System Settings."
            BessieDiagnosticLog.append("Notification authorization denied")
        } else {
            authorizationError = nil
        }
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
