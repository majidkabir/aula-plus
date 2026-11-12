import Foundation
import Observation

/// All cached data sources, shared between tabs.
@MainActor
@Observable
final class DataStore {
    static let shared = DataStore()

    let presence: Loadable<[Presence]>
    let threads: Loadable<[ThreadSummary]>
    let posts: Loadable<[Post]>
    let notifications: Loadable<[AulaNotification]>
    let importantDates: Loadable<[ImportantDate]>
    let albums: Loadable<[Album]>

    @ObservationIgnored private var weeks: [String: Loadable<[Event]>] = [:]
    @ObservationIgnored private var threadPages: [String: Loadable<ThreadPage>] = [:]
    @ObservationIgnored private var weekPlans: [String: Loadable<[WeekPlan]>] = [:]
    @ObservationIgnored private var albumMedia: [Int: Loadable<[Media]>] = [:]

    func media(albumId: Int) -> Loadable<[Media]> {
        if let l = albumMedia[albumId] { return l }
        let l = Loadable<[Media]>(key: "album-\(albumId)") {
            let s = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.media(albumId: albumId, institutionProfileIds: s.institutionProfileIds)
        }
        albumMedia[albumId] = l
        return l
    }

    private init() {
        presence = Loadable(key: "presence") {
            let s = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.presence(childIds: s.children.map(\.id))
        }
        threads = Loadable(key: "threads") {
            try await AulaAPI.shared.threads().threads
        }
        posts = Loadable(key: "posts") {
            let s = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.posts(institutionProfileIds: s.institutionProfileIds)
        }
        notifications = Loadable(key: "notifications") {
            _ = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.notifications()
        }
        importantDates = Loadable(key: "important-dates") {
            _ = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.importantDates()
        }
        presence.onChange = { WidgetWriter.update() }
        threads.onChange = { WidgetWriter.update() }
        albums = Loadable(key: "albums") {
            let s = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.albums(institutionProfileIds: s.institutionProfileIds)
        }
    }

    var unreadCount: Int { threads.value?.filter { !$0.isRead }.count ?? 0 }

    /// Events for the Monday-based week containing `date`.
    func events(weekOf date: Date) -> Loadable<[Event]> {
        let start = Week.start(of: date)
        let key = "events-\(Week.key(start))"
        if let l = weeks[key] { return l }
        let l = Loadable<[Event]>(key: key) {
            let s = try await AulaAPI.shared.bootstrap()
            let end = Calendar.week.date(byAdding: .day, value: 6, to: start)!
            return try await AulaAPI.shared.events(institutionProfileIds: s.children.map(\.id), from: start, to: end)
        }
        if Calendar.week.isDate(start, inSameDayAs: Week.start(of: .now)) {
            l.onChange = { WidgetWriter.update() }
        }
        weeks[key] = l
        return l
    }

    func thread(_ id: String) -> Loadable<ThreadPage> {
        if let l = threadPages[id] { return l }
        let l = Loadable<ThreadPage>(key: "thread-\(id)") {
            try await AulaAPI.shared.messages(threadId: id)
        }
        threadPages[id] = l
        return l
    }

    @ObservationIgnored private var tasks: [String: Loadable<[SchoolTask]>] = [:]

    func schoolTasks(weekOf date: Date) -> Loadable<[SchoolTask]> {
        let start = Week.start(of: date)
        let key = "tasks-\(Week.key(start))"
        if let l = tasks[key] { return l }
        let l = Loadable<[SchoolTask]>(key: key) {
            let s = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.schoolTasks(session: s, week: Week.isoWeek(start))
        }
        tasks[key] = l
        return l
    }

    func weekPlan(weekOf date: Date) -> Loadable<[WeekPlan]> {
        let start = Week.start(of: date)
        let key = "weekplan-\(Week.key(start))"
        if let l = weekPlans[key] { return l }
        let l = Loadable<[WeekPlan]>(key: key) {
            let s = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.weekPlans(session: s, week: Week.isoWeek(start))
        }
        weekPlans[key] = l
        return l
    }

    func markRead(threadId: String) {
        threads.mutate { list in
            if let i = list.firstIndex(where: { $0.id == threadId }) {
                let t = list[i]
                list[i] = ThreadSummary(id: t.id, subject: t.subject, preview: t.preview, sender: t.sender,
                                        date: t.date, isRead: true, isSensitive: t.isSensitive, regarding: t.regarding)
            }
        }
    }

    func reset() {
        presence.forget()
        threads.forget()
        posts.forget()
        notifications.forget()
        importantDates.forget()
        albums.forget()
        albumMedia = [:]
        weeks = [:]
        threadPages = [:]
        weekPlans = [:]
        tasks = [:]
    }
}

extension Calendar {
    /// Danish week rules: Monday first, ISO week numbers.
    static let week: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = AulaDate.copenhagen
        c.locale = Locale(identifier: "da_DK")
        return c
    }()
}

enum Week {
    static func start(of date: Date) -> Date {
        Calendar.week.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.week.startOfDay(for: date)
    }

    static func isoWeek(_ date: Date) -> (year: Int, week: Int) {
        let c = Calendar.week.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    static func key(_ date: Date) -> String {
        let w = isoWeek(date)
        return String(format: "%d-W%02d", w.year, w.week)
    }

    static func days(of start: Date) -> [Date] {
        (0..<7).compactMap { Calendar.week.date(byAdding: .day, value: $0, to: start) }
    }
}
