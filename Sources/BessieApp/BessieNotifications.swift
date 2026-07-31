import AppKit
import BessieCore
import Foundation
import UserNotifications

@MainActor
final class BessieNotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingTarget: PaneOpenTarget?

    private let center: UNUserNotificationCenter
    private var planner = BessieNotificationPlanner()

    override init() {
        center = .current()
        super.init()
        center.delegate = self
        refreshAuthorization()
    }

    func refreshAuthorization() {
        Task {
            authorizationStatus = await center.notificationSettings().authorizationStatus
        }
    }

    func requestAuthorization() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            authorizationStatus = await center.notificationSettings().authorizationStatus
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func reconcile(
        panes: [BessieNotificationPane],
        policy: BessieNotifications,
        activePaneID: String?
    ) {
        let events = planner.events(for: panes, policy: policy, activePaneID: activePaneID)
        guard authorizationStatus.allowsDelivery else { return }

        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            content.userInfo = [
                "workspace_id": event.target.workspaceID,
                "tab_id": event.target.tabID,
                "pane_id": event.target.paneID,
            ]
            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
            center.add(request)
        }
    }

    func consumePendingTarget() {
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
        let target = Self.target(from: response.notification.request.content.userInfo)
        completionHandler()
        guard let target else { return }
        Task { @MainActor [weak self] in
            self?.pendingTarget = target
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated private static func target(from info: [AnyHashable: Any]) -> PaneOpenTarget? {
        guard let workspaceID = info["workspace_id"] as? String,
              let tabID = info["tab_id"] as? String,
              let paneID = info["pane_id"] as? String
        else { return nil }
        return PaneOpenTarget(workspaceID: workspaceID, tabID: tabID, paneID: paneID)
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
