import Foundation
import UserNotifications

/// Turns a Hub's word of unread replies into a notification that names the bot and shows what it
/// said, fetched from the Hub itself. Nothing but the topic and the conversation passes through Apple.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let lock = NSLock()
    /// Delivered once: with the reply, or as it came when time runs out.
    private var pending: (content: UNMutableNotificationContent, deliver: (UNNotificationContent) -> Void)?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else { return contentHandler(request.content) }
        guard let route = PushTopic.route(userInfo: request.content.userInfo), let hubs = AppGroup.hubs else { return contentHandler(content) }
        // One stack per conversation in Notification Center.
        content.threadIdentifier = route.conversation.uuidString
        lock.withLock { pending = (content, contentHandler) }
        Task { @MainActor in
            let reply = await ReplyNotification.content(for: route, hubs: hubs)
            self.finish(with: reply)
        }
    }

    /// Out of time, the notification shows as it came: "New reply".
    override func serviceExtensionTimeWillExpire() { finish(with: nil) }

    private func finish(with reply: ReplyNotification.Content?) {
        lock.withLock {
            guard let pending else { return }
            self.pending = nil
            if let reply {
                pending.content.title = reply.title
                pending.content.body = reply.body
            }
            pending.deliver(pending.content)
        }
    }
}
