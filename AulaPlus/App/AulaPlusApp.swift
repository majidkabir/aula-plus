import SwiftUI

import BackgroundTasks
import UserNotifications

@main
struct AulaPlusApp: App {
    @State private var app = AppModel.shared
    @State private var data = DataStore.shared
    @State private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        Self.roundedNavigationTitles()
        // Photo thumbnails (AsyncImage) come back from cache instead of being downloaded again.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    }

    /// Navigation titles in the same rounded, heavy type as the rest of the app.
    private static func roundedNavigationTitles() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: rounded(34, .heavy)]
        bar.titleTextAttributes = [.font: rounded(17, .bold)]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // While locked, VoiceOver must not read the screens behind the lock.
                .accessibilityHidden(lock.isLocked)
                .task {
                    await app.start()
                    BackgroundRefresh.schedule()
                }
                .overlay {
                    if lock.isLocked {
                        LockView()
                    } else if scenePhase != .active && lock.isEnabled && app.phase == .loggedIn {
                        PrivacyCover()
                    }
                }
                // Last, so the lock screen overlay sees the app state too.
                .environment(app)
                .environment(data)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskId)) {
            await BackgroundRefresh.run()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                lock.didEnterBackground(loggedIn: app.phase == .loggedIn)
                BackgroundRefresh.schedule()
            case .active:
                lock.didBecomeActive(loggedIn: app.phase == .loggedIn)
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                ProgressView()
            case .loggedOut:
                LoginView()
            case .loggedIn:
                MainTabs()
            }
        }
        .tint(Color.brand)
        .fontDesign(.rounded)
        .animation(.snappy, value: ThemeStore.shared.theme)
    }
}

struct MainTabs: View {
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            TodayView()
                .tabItem { Label("I dag", systemImage: "sun.max") }
                .tag(AppModel.Tab.today)
            MessagesView()
                .tabItem { Label("Beskeder", systemImage: "bubble.left.and.bubble.right") }
                .badge(data.unreadCount)
                .tag(AppModel.Tab.messages)
            CalendarView()
                .tabItem { Label("Kalender", systemImage: "calendar") }
                .tag(AppModel.Tab.calendar)
            if app.showsWeekPlan {
                WeekPlanView()
                    .tabItem { Label("Ugeplan", systemImage: "list.bullet.rectangle") }
                    .tag(AppModel.Tab.weekPlan)
            } else {
                PhotosTab()
                    .tabItem { Label("Billeder", systemImage: "photo.on.rectangle.angled") }
                    .badge(data.newGalleryCount)
                    .tag(AppModel.Tab.photos)
            }
            MoreView()
                .tabItem { Label("Mere", systemImage: "ellipsis.circle") }
                .tag(AppModel.Tab.more)
        }
        .alert(String(localized: "Lås Aula+ med \(AppLock.shared.methodName)?"),
               isPresented: Binding(get: { AppLock.shared.showOffer }, set: { AppLock.shared.showOffer = $0 })) {
            Button("Slå til") { Task { await AppLock.shared.enable() } }
            Button("Ikke nu", role: .cancel) {}
        } message: {
            Text("Så kan andre, der låner din telefon, ikke læse beskeder om dine børn.")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await data.threads.load(maxAge: 60)
                await data.presence.load(maxAge: 60)
            }
        }
    }
}
