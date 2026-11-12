import Foundation
import LocalAuthentication
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase { case launching, loggedOut, loggedIn }

    private(set) var phase: Phase = .launching
    private(set) var loginNotice: String?

    /// Profile, children, widgets. Cached so the app opens offline.
    let session: Loadable<Session>

    private init() {
        session = Loadable(key: "session") { try await AulaAPI.shared.bootstrap() }
    }

    /// nil = all children.
    var selectedChildId: Int?

    enum Tab: Hashable { case today, messages, calendar, weekPlan, more }
    var selectedTab: Tab = .today
    var messagesPath: [ThreadSummary] = []
    var morePath = NavigationPath()
    var todayPath = NavigationPath()

    // MARK: App lock (Face ID / passcode)

    static let lockKey = "lock.enabled"
    var lockEnabled: Bool = UserDefaults.standard.bool(forKey: AppModel.lockKey) {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: Self.lockKey) }
    }
    private(set) var isLocked: Bool = UserDefaults.standard.bool(forKey: AppModel.lockKey)

    func lockIfNeeded() {
        if lockEnabled && phase == .loggedIn { isLocked = true }
    }

    func unlock() async {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            isLocked = false   // no passcode set on device: nothing to unlock with
            return
        }
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Lås Aula+ op"))) == true {
            isLocked = false
        }
    }

    // MARK: Deep links (notification taps)

    func openThread(id: String) {
        let known = DataStore.shared.threads.value?.first { $0.id == id }
        let thread = known ?? ThreadSummary(id: id, subject: "", preview: "", sender: "", date: nil,
                                            isRead: false, isSensitive: false, regarding: [])
        selectedTab = .messages
        messagesPath = [thread]
    }

    func openPost(id: Int) {
        selectedTab = .more
        Task {
            if let post = try? await AulaAPI.shared.post(id: id) {
                morePath = NavigationPath()
                morePath.append(post)
            }
        }
    }

    var children: [Child] { session.value?.children ?? [] }

    var visibleChildren: [Child] {
        guard let id = selectedChildId else { return children }
        return children.filter { $0.id == id }
    }

    func child(_ id: Int) -> Child? { children.first { $0.id == id } }

    func start() async {
        if Demo.isOn {
            phase = Demo.screen == "login" ? .loggedOut : .loggedIn
            switch Demo.screen {
            case "messages": selectedTab = .messages
            case "thread": selectedTab = .messages; messagesPath = [Demo.threads[0]]
            case "calendar": selectedTab = .calendar
            case "weekPlan": selectedTab = .weekPlan
            case "more": selectedTab = .more
            case "post": selectedTab = .more; morePath.append(Demo.posts[0])
            case "child": todayPath.append(Demo.noah)
            case "gallery": selectedTab = .more; morePath.append(DemoRoute.gallery)
            case "notifications": selectedTab = .more; morePath.append(DemoRoute.notifications)
            case "settings": selectedTab = .more; morePath.append(DemoRoute.settings)
            case "empty": selectedTab = .more; morePath.append(DemoRoute.empty)
            default: break
            }
            return
        }
        let hasTokens = await TokenStore.shared.hasTokens
        phase = hasTokens ? .loggedIn : .loggedOut
        if hasTokens { await session.load() }
    }

    func didLogin() async {
        loginNotice = nil
        await AulaAPI.shared.reset()
        phase = .loggedIn
        await session.refresh()
    }

    func sessionExpired() {
        guard phase == .loggedIn else { return }
        loginNotice = String(localized: "Din Aula-session er udløbet. Log ind med MitID igen.")
        phase = .loggedOut
    }

    func logout() async {
        await TokenStore.shared.clear()
        await AulaAPI.shared.reset()
        DiskCache.clear()
        DataStore.shared.reset()
        session.forget()
        WidgetSnapshot(children: [], unread: 0, latestSender: nil, latestSubject: nil, updated: .now).save()
        BackgroundRefresh.updateBadge(0, force: true)
        selectedChildId = nil
        phase = .loggedOut
    }
}
