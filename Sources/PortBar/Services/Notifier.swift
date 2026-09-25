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

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ notice: AgentEventCenter.Notice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.userInfo = ["pid": Int(notice.agent.pid), "startSec": notice.agent.startSec]
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
        let info = response.notification.request.content.userInfo
        guard let pid = info["pid"] as? Int, let startSec = info["startSec"] as? UInt64 else { return }
        await MainActor.run { onOpen(AgentController.Member(pid: Int32(pid), startSec: startSec)) }
    }
}
