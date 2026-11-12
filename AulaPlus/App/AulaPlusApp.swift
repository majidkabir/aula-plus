import SwiftUI

@main
struct AulaPlusApp: App {
    @State private var app = AppModel.shared
    @State private var data = DataStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(data)
                .environment(\.locale, Locale(identifier: "da_DK"))
                .task { await app.start() }
        }
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("I dag", systemImage: "sun.max") }
            MessagesView()
                .tabItem { Label("Beskeder", systemImage: "bubble.left.and.bubble.right") }
                .badge(data.unreadCount)
            CalendarView()
                .tabItem { Label("Kalender", systemImage: "calendar") }
            WeekPlanView()
                .tabItem { Label("Ugeplan", systemImage: "list.bullet.rectangle") }
            MoreView()
                .tabItem { Label("Mere", systemImage: "ellipsis.circle") }
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
