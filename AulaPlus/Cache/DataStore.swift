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
    let birthdays: Loadable<[Birthday]>
    let albums: Loadable<[Album]>
    let vacationRequests: Loadable<[VacationRequest]>

    @ObservationIgnored private var weeks: [String: Loadable<[Event]>] = [:]
    @ObservationIgnored private var threadPages: [String: Loadable<ThreadPage>] = [:]
    @ObservationIgnored private var weekPlans: [String: Loadable<[WeekPlan]>] = [:]
    @ObservationIgnored private var albumMedia: [Int: Loadable<[Media]>] = [:]

    func media(album: Album) -> Loadable<[Media]> {
        if let l = albumMedia[album.id] { return l }
        let l: Loadable<[Media]>
        if let childId = album.childId {
            l = Loadable(key: "tagged-\(childId)", streaming: { emit in
                let s = try await AulaAPI.shared.bootstrap()
                return try await AulaAPI.shared.taggedMedia(childId: childId, institutionProfileIds: s.institutionProfileIds,
                                                            progress: emit)
            })
        } else {
            let albumId = album.id
            l = Loadable(key: "album-\(albumId)", streaming: { emit in
                let s = try await AulaAPI.shared.bootstrap()
                return try await AulaAPI.shared.media(albumId: albumId, institutionProfileIds: s.institutionProfileIds,
                                                      progress: emit)
            })
        }
        albumMedia[album.id] = l
        return l
    }

    /// Saves or unsaves a post on Aula and in the cached overview.
    func setBookmarked(_ post: Post, _ on: Bool) async throws {
        if !Demo.isOn { try await AulaAPI.shared.setBookmarked(postId: post.id, on) }
        posts.mutate { list in
            if let i = list.firstIndex(where: { $0.id == post.id }) { list[i].isBookmarked = on }
        }
    }

    /// Tags or untags `child` in a photo, on Aula and in every cached album. Returns the updated photo.
    func setTagged(_ child: Child, _ tagged: Bool, in media: Media) async throws -> Media {
        var tags = media.tagList.filter { $0.id != child.id }
        if tagged { tags.append(MediaTag(id: child.id, name: child.name)) }
        if !Demo.isOn {
            try await AulaAPI.shared.setTag(child.id, on: media, tagged: tagged, allTagIds: tags.map(\.id))
        }
        var updated = media
        updated.tags = tags
        for (key, list) in albumMedia {
            if key == -child.id {
                // The child's own album: add or drop the photo.
                list.mutate { items in
                    items.removeAll { $0.id == media.id }
                    if tagged { items.insert(updated, at: 0) }
                }
            } else {
                list.mutate { items in
                    if let i = items.firstIndex(where: { $0.id == media.id }) { items[i] = updated }
                }
            }
        }
        return updated
    }

    @ObservationIgnored private var nextPlans: [Int: Loadable<[DayPlan]>] = [:]

    /// The child's drop-off/pick-up plans for the next 10 days (to show the next drop-off on a day off).
    func upcomingPlans(childId: Int) -> Loadable<[DayPlan]> {
        let today = Calendar.week.startOfDay(for: .now)
        let key = Week.dayKey(today)
        if let l = nextPlans[childId], l.key.hasSuffix(key) { return l }
        let l = Loadable<[DayPlan]>(key: "next-plans-\(childId)-\(key)") {
            let from = Calendar.week.date(byAdding: .day, value: 1, to: today)!
            let to = Calendar.week.date(byAdding: .day, value: 10, to: today)!
            return try await AulaAPI.shared.dayPlans(childIds: [childId], from: from, to: to)
        }
        nextPlans[childId] = l
        return l
    }

    // MARK: Gallery "new" markers (from Aula's gallery notifications)

    /// Gallery notifications already seen here. Kept on the device so the "new" counts stay
    /// gone even when Aula keeps the notification (or deleting it there fails).
    private var seenNotificationIds: [String] = UserDefaults.standard.stringArray(forKey: "seenNotificationIds") ?? []

    private var galleryNotifications: [AulaNotification] {
        let seen = Set(seenNotificationIds)
        return (notifications.value ?? []).filter { $0.isGallery && !seen.contains($0.id) }
    }

    /// Notifications that make photos in `album` "new".
    func newNotifications(in album: Album) -> [AulaNotification] {
        if let childId = album.childId {
            return galleryNotifications.filter { $0.isTaggedInMedia && $0.relatedChildId == childId }
        }
        return galleryNotifications.filter { !$0.isTaggedInMedia && $0.albumId == album.id }
    }

    /// Number of new photos in `album` (one per photo, however many notifications it has).
    func newCount(in album: Album) -> Int { Self.photoCount(newNotifications(in: album)) }

    private static func photoCount(_ list: [AulaNotification]) -> Int {
        Set(list.compactMap(\.mediaId)).count + list.filter { $0.mediaId == nil }.count
    }

    /// Ids of every photo Aula still marks as new.
    var newMediaIds: Set<Int> { Set(galleryNotifications.compactMap(\.mediaId)) }

    /// Total new photos in the gallery (badge on the Gallery row).
    var newGalleryCount: Int { Self.photoCount(galleryNotifications.filter { $0.isNewMedia || $0.isTaggedInMedia }) }

    /// Clears the new markers for `album` (and for the photos shown in it), on Aula too.
    func markSeen(_ album: Album, media: [Media]) async {
        let shown = Set(media.map(\.id))
        let seen = newNotifications(in: album) + galleryNotifications.filter { $0.mediaId.map(shown.contains) ?? false }
        var ids = Set<String>()
        let unique = seen.filter { ids.insert($0.id).inserted }
        guard !unique.isEmpty else { return }
        seenNotificationIds = Array((seenNotificationIds + unique.map(\.id)).suffix(3000))
        UserDefaults.standard.set(seenNotificationIds, forKey: "seenNotificationIds")
        guard !Demo.isOn else { return }
        do {
            let owners = (try? await AulaAPI.shared.bootstrap())?.guardianProfileIds ?? []
            try await AulaAPI.shared.deleteNotifications(unique, fallbackOwners: owners)
            notifications.mutate { $0.removeAll { ids.contains($0.id) } }
        } catch {
            // Seen locally anyway; Aula may still show it as new in its own app.
        }
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
            let s = try await AulaAPI.shared.bootstrap()
            let codes = Array(Set(s.children.compactMap(\.institutionCode))).sorted()
            return try await AulaAPI.shared.notifications(childIds: s.children.map(\.id), institutionCodes: codes)
        }
        birthdays = Loadable(key: "birthdays") {
            let s = try await AulaAPI.shared.bootstrap()
            let codes = Array(Set(s.children.compactMap(\.institutionCode))).sorted()
            return try await AulaAPI.shared.birthdays(institutionCodes: codes)
        }
        importantDates = Loadable(key: "important-dates") {
            _ = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.importantDates()
        }
        vacationRequests = Loadable(key: "vacation-requests") {
            let s = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.vacationRequests(childIds: s.children.map(\.id))
        }
        albums = Loadable(key: "albums") {
            let s = try await AulaAPI.shared.bootstrap()
            return try await AulaAPI.shared.albums(institutionProfileIds: s.institutionProfileIds)
        }
        presence.onChange = { WidgetWriter.update() }
        threads.onChange = { [weak self] in
            WidgetWriter.update()
            BackgroundRefresh.updateBadge((self?.threads.value ?? []).filter { !$0.isRead }.count)
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
                                        date: t.date, isRead: true, isSensitive: t.isSensitive, regarding: t.regarding,
                                        isMarked: t.isMarked)
            }
        }
    }

    func setMarked(threadId: String, marked: Bool) {
        threads.mutate { list in
            if let i = list.firstIndex(where: { $0.id == threadId }) { list[i].isMarked = marked }
        }
    }

    func removeThread(_ threadId: String) {
        threads.mutate { $0.removeAll { $0.id == threadId } }
    }

    func reset() {
        presence.forget()
        threads.forget()
        posts.forget()
        notifications.forget()
        importantDates.forget()
        birthdays.forget()
        albums.forget()
        vacationRequests.forget()
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
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2              // Monday
        c.minimumDaysInFirstWeek = 4    // ISO 8601 week numbers
        c.timeZone = .current           // group by the phone's local day
        c.locale = .current
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

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.week.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func key(_ date: Date) -> String {
        let w = isoWeek(date)
        return String(format: "%d-W%02d", w.year, w.week)
    }

    static func days(of start: Date) -> [Date] {
        (0..<7).compactMap { Calendar.week.date(byAdding: .day, value: $0, to: start) }
    }
}
