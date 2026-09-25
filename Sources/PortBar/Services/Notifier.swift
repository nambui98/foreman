import Foundation
import UserNotifications

/// Delivers agent notices as macOS notifications; clicking one reports the agent back.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// Called with the agent's (pid, start time) when the user clicks a notification.
    var onOpen: (AgentController.Member) -> Void = { _ in }

    override init() {
        super.init()
        center.delegate = self
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated static func userInfo(for agent: AgentController.Member) -> [AnyHashable: Any] {
        ["pid": Int(agent.pid), "startSec": agent.startSec]
    }

    /// Values come back as NSNumber after the notification round trip.
    nonisolated static func agent(from userInfo: [AnyHashable: Any]) -> AgentController.Member? {
        guard let pid = (userInfo["pid"] as? NSNumber)?.int32Value,
              let startSec = (userInfo["startSec"] as? NSNumber)?.uint64Value else { return nil }
        return AgentController.Member(pid: pid, startSec: startSec)
    }

    func post(_ notice: AgentEventCenter.Notice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.userInfo = Self.userInfo(for: notice.agent)
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// PortBar is never "frontmost" in a useful sense, so show banners even while it is active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let agent = Self.agent(from: response.notification.request.content.userInfo) else { return }
        await MainActor.run { onOpen(agent) }
    }
}
