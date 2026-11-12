import BackgroundTasks
import Foundation
import UserNotifications

/// Polls Aula in the background (iOS decides when, typically every 15–60 min)
/// and posts a local notification for new messages and posts.
/// No server needed; trade-off: delivery is not instant.
enum BackgroundRefresh {
    static let taskId = "com.majidkabir.aulaplus.refresh"
    private static let seenThreadsKey = "bg.seenUnreadThreads"
    private static let seenPostsKey = "bg.seenPosts"
    static let enabledKey = "notifications.enabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func schedule() {
        guard isEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: taskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        if granted {
            await primeSeen()
            schedule()
        }
        return granted
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
        updateBadge(0, force: true)
    }

    /// Keeps the app icon badge in step with unread threads (also after reading in the app).
    static func updateBadge(_ unread: Int, force: Bool = false) {
        guard isEnabled || force else { return }
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(unread) }
    }

    /// Marks what is there now as seen so enabling doesn't spam old items.
    static func primeSeen() async {
        if let t = try? await AulaAPI.shared.threads().threads {
            UserDefaults.standard.set(t.filter { !$0.isRead }.map(\.id), forKey: seenThreadsKey)
        }
        if let s = try? await AulaAPI.shared.bootstrap(),
           let p = try? await AulaAPI.shared.posts(institutionProfileIds: s.institutionProfileIds) {
            UserDefaults.standard.set(p.map(\.id), forKey: seenPostsKey)
        }
    }

    /// Runs inside the background task.
    static func run() async {
        schedule()   // always queue the next run first
        guard isEnabled, await TokenStore.shared.hasTokens else { return }

        let defaults = UserDefaults.standard
        if let threads = try? await AulaAPI.shared.threads().threads {
            await MainActor.run { DataStore.shared.threads.replace(threads) }
            let unread = threads.filter { !$0.isRead }
            let seen = Set(defaults.stringArray(forKey: seenThreadsKey) ?? [])
            for t in unread where !seen.contains(t.id) {
                await notify(id: "thread-\(t.id)",
                             title: t.sender.isEmpty ? String(localized: "Ny besked") : t.sender,
                             body: t.subject + (t.preview.isEmpty ? "" : "\n" + t.preview),
                             info: ["threadId": t.id])
            }
            defaults.set(unread.map(\.id), forKey: seenThreadsKey)
            try? await UNUserNotificationCenter.current().setBadgeCount(unread.count)
        }

        if let s = try? await AulaAPI.shared.bootstrap(),
           let posts = try? await AulaAPI.shared.posts(institutionProfileIds: s.institutionProfileIds) {
            await MainActor.run { DataStore.shared.posts.replace(posts) }
            let seen = Set(defaults.array(forKey: seenPostsKey) as? [Int] ?? [])
            for p in posts.prefix(10) where !seen.contains(p.id) {
                await notify(id: "post-\(p.id)", title: String(localized: "Nyt opslag: \(p.title)"),
                             body: HTML.plainText(p.html), info: ["postId": p.id])
            }
            defaults.set(posts.map(\.id), forKey: seenPostsKey)
        }
    }

    private static func notify(id: String, title: String, body: String, info: [String: Any]) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(240))
        content.sound = .default
        content.userInfo = info
        content.threadIdentifier = "aula"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}

/// Routes a tapped notification to the right screen.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let threadId = info["threadId"] as? String
        let postId = info["postId"] as? Int
        await MainActor.run {
            if let threadId { AppModel.shared.openThread(id: threadId) }
            else if let postId { AppModel.shared.openPost(id: postId) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
