import SwiftUI

import BackgroundTasks
import UserNotifications

@main
struct AulaPlusApp: App {
    @State private var app = AppModel.shared
    @State private var data = DataStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(data)
                .environment(\.locale, Locale(identifier: "da_DK"))
                .task {
                    await app.start()
                    BackgroundRefresh.schedule()
                }
                .overlay {
                    if app.isLocked { LockView() }
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskId)) {
            await BackgroundRefresh.run()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                app.lockIfNeeded()
                BackgroundRefresh.schedule()
            }
        }
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Aula+ er låst").font(.headline)
                Button("Lås op") { Task { await app.unlock() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .task { await app.unlock() }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .launching:
            ProgressView()
        case .loggedOut:
            LoginView()
        case .loggedIn:
            MainTabs()
        }
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
            WeekPlanView()
                .tabItem { Label("Ugeplan", systemImage: "list.bullet.rectangle") }
                .tag(AppModel.Tab.weekPlan)
            MoreView()
                .tabItem { Label("Mere", systemImage: "ellipsis.circle") }
                .tag(AppModel.Tab.more)
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
