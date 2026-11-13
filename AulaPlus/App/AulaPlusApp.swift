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
