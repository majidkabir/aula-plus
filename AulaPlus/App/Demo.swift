import Foundation

/// Demo mode: `-demo YES` launches with sample data and no network.
/// Used for UI screenshots in CI (`-screen today|messages|calendar|weekPlan|more|thread|post|child`).
enum Demo {
    static let isOn = UserDefaults.standard.bool(forKey: "demo")
    static var screen: String? { UserDefaults.standard.string(forKey: "screen") }

    private static let cal = Calendar.week
    private static var today: Date { cal.startOfDay(for: .now) }
    private static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        let d = cal.date(byAdding: .day, value: day, to: today)!
        return cal.date(bySettingHour: h, minute: m, second: 0, of: d)!
    }
    private static func ago(_ minutes: Double) -> Date { Date().addingTimeInterval(-minutes * 60) }

    static let emma = Child(id: 101, name: "Emma Ghafouri", institutionName: "Valby Skole · 3.A",
                            institutionCode: "101001", userId: "emma01", pictureURL: nil)
    static let noah = Child(id: 102, name: "Noah Ghafouri", institutionName: "Børnehuset Solsikken",
                            institutionCode: "101002", userId: "noah01", pictureURL: nil)

    static let session = Session(displayName: "Majid Ghafouri", children: [emma, noah],
                                 institutionProfileIds: [11, 101, 102], guardianUserId: "g1",
                                 widgetIds: ["0029", "0030"], guardianProfileIds: [11])

    static var presence: [Presence] {[
        Presence(childId: 101, status: .present, checkIn: "07:52", checkOut: nil, plannedEntry: "08:00",
                 plannedExit: "15:30", exitWith: "Majid (Far)", comment: nil, location: "Klasselokale"),
        Presence(childId: 102, status: .sleeping, checkIn: "07:40", checkOut: nil, plannedEntry: "07:45",
                 plannedExit: "16:00", exitWith: "Sara (Mor)", comment: "Har sovet godt i dag", location: nil),
    ]}

    static var threads: [ThreadSummary] {[
        ThreadSummary(id: "1", subject: "Tur til Zoologisk Have på fredag", preview: "Husk madpakke, drikkedunk og tøj efter vejret. Vi mødes kl. 8.15 ved skolens hovedindgang.",
                      sender: "Line Hansen", date: ago(25), isRead: false, isSensitive: false, regarding: ["Emma"]),
        ThreadSummary(id: "2", subject: "Forældremøde i 3.A", preview: "Kære forældre, vi inviterer til forældremøde tirsdag d. 24. kl. 17.",
                      sender: "Thomas Berg", date: ago(190), isRead: false, isSensitive: false, regarding: ["Emma"], isMarked: true),
        ThreadSummary(id: "3", subject: "Noah har haft en god dag", preview: "Han har bygget en stor hule med de andre og spist hele sin frokost.",
                      sender: "Pernille (pædagog)", date: ago(60 * 26), isRead: true, isSensitive: false, regarding: ["Noah"]),
        ThreadSummary(id: "4", subject: "Fotografering", preview: "Der er skolefotografering mandag. Søskendebilleder kan bestilles.",
                      sender: "Kontoret", date: ago(60 * 50), isRead: true, isSensitive: false, regarding: []),
        ThreadSummary(id: "5", subject: "Helbredsoplysninger", preview: "Fortrolig besked fra sundhedsplejen.",
                      sender: "Sundhedsplejen", date: ago(60 * 24 * 4), isRead: true, isSensitive: true, regarding: ["Emma"]),
        ThreadSummary(id: "6", subject: "Glemt jakke", preview: "Der hænger en blå jakke i garderoben.",
                      sender: "Pernille (pædagog)", date: ago(60 * 24 * 9), isRead: true, isSensitive: false, regarding: ["Noah"]),
    ]}

    static var threadPage: ThreadPage {
        ThreadPage(subject: "Tur til Zoologisk Have på fredag", messages: [
            Message(id: "m3", sender: "Line Hansen", date: ago(25),
                    html: "<p>Husk madpakke, drikkedunk og tøj efter vejret.</p><p>Vi mødes kl. <b>8.15</b> ved skolens hovedindgang og er tilbage ca. 14.</p>",
                    attachments: [Attachment(name: "Program fredag.pdf", url: URL(string: "https://example.com/p.pdf"))]),
            Message(id: "m2", sender: "Majid Ghafouri", date: ago(60 * 20), html: "<p>Tak! Skal de have penge med til is?</p>", attachments: []),
            Message(id: "m1", sender: "Line Hansen", date: ago(60 * 22),
                    html: "<p>Hej alle. På fredag tager 3.A i Zoologisk Have. Mere info følger.</p>", attachments: []),
        ], moreExist: false, lastReadMessageId: "m3", isOwnMailbox: true)
    }

    static var events: [Event] {
        var out: [Event] = []
        let lessons = [("Dansk", "Lokale 12", "Line Hansen"), ("Matematik", "Lokale 12", "Thomas Berg"),
                       ("Idræt", "Hallen", "Kasper Holm"), ("Engelsk", "Lokale 8", "Anne Lund"),
                       ("Natur/teknologi", "Faglokale", "Thomas Berg")]
        let weekStart = Week.start(of: .now)
        for day in 0..<5 {
            let offset = cal.dateComponents([.day], from: today, to: weekStart).day! + day
            for (i, l) in lessons.enumerated() where (i + day) % 5 != 4 {
                let start = at(offset, 8 + i, i == 0 ? 0 : 15)
                out.append(Event(id: "l\(day)-\(i)", title: l.0, start: start, end: start.addingTimeInterval(45 * 60),
                                 allDay: false, location: l.1, teacher: l.2,
                                 substitute: i == 1 && day == 2 ? "Mads Nielsen" : nil,
                                 hasSubstitute: i == 1 && day == 2, type: "lesson", childIds: [101]))
            }
            out.append(Event(id: "s\(day)", title: "Sang og musik", start: at(offset, 10), end: at(offset, 10, 30),
                             allDay: false, location: "Stuen", teacher: nil, substitute: nil, hasSubstitute: false,
                             type: "event", childIds: [102]))
        }
        out.append(Event(id: "e1", title: "Forældremøde 3.A", start: at(1, 17), end: at(1, 19), allDay: false,
                         location: "Klasselokalet", teacher: nil, substitute: nil, hasSubstitute: false,
                         type: "event", childIds: [101]))
        return out.sorted { $0.start < $1.start }
    }

    static var posts: [Post] {[
        Post(id: 1, title: "Julefrokost i SFO'en", html: "<p>Vi holder julefrokost torsdag d. 18. Alle forældre er velkomne fra kl. 15.</p>",
             date: ago(90), author: "SFO Solstrålen", isImportant: true, attachments: [], canComment: true),
        Post(id: 2, title: "Nyt fra skolebestyrelsen", html: "<p>Referat fra seneste møde er nu tilgængeligt.</p>",
             date: ago(60 * 30), author: "Skolebestyrelsen", isImportant: false,
             attachments: [Attachment(name: "Referat.pdf", url: nil)], canComment: false),
        Post(id: 3, title: "Lus i 3.A", html: "<p>Tjek venligst jeres børns hår i weekenden.</p>",
             date: ago(60 * 24 * 3), author: "Line Hansen", isImportant: false, attachments: [], canComment: true),
    ]}

    static var importantDates: [ImportantDate] {[
        ImportantDate(id: "d1", title: "Forældremøde 3.A", start: at(1, 17), allDay: false),
        ImportantDate(id: "d2", title: "Juleferie starter", start: at(9, 0), allDay: true),
    ]}

    static var notifications: [AulaNotification] {[
        AulaNotification(id: "n1", title: "Ny besked: Tur til Zoologisk Have", module: "messages", childName: "Emma",
                         date: ago(25), postId: nil, threadId: "1", albumId: nil),
        AulaNotification(id: "n2", title: "Nyt opslag: Julefrokost i SFO'en", module: "posts", childName: nil,
                         date: ago(90), postId: 1, threadId: nil, albumId: nil),
        AulaNotification(id: "n3", title: "Nye billeder i albummet Efterårsferie", module: "gallery", childName: "Noah",
                         date: ago(60 * 30), postId: nil, threadId: nil, albumId: 1),
    ] + galleryNotices}

    /// Gallery notices: 2 new photos in "Juletræet pyntes", Emma tagged in 1.
    private static var galleryNotices: [AulaNotification] {[
        AulaNotification(id: "g1", title: "Nye billeder i galleriet", module: "gallery", childName: nil, date: ago(40),
                         postId: nil, threadId: nil, albumId: 3, eventType: "NewMedia", mediaId: 1),
        AulaNotification(id: "g2", title: "Nye billeder i galleriet", module: "gallery", childName: nil, date: ago(40),
                         postId: nil, threadId: nil, albumId: 3, eventType: "NewMedia", mediaId: 2),
        AulaNotification(id: "g3", title: "Emma er tagget på et billede", module: "gallery", childName: "Emma", date: ago(45),
                         postId: nil, threadId: nil, albumId: nil, eventType: "TaggedInMedia", mediaId: 2, relatedChildId: 101),
    ]}

    static var media: [Media] {
        (1...12).map { i in
            let tags: [MediaTag] = switch i % 4 {
            case 0: [MediaTag(id: 101, name: "Emma Ghafouri")]
            case 1: [MediaTag(id: 102, name: "Noah Ghafouri"), MediaTag(id: 900, name: "Ida Holm")]
            case 2: [MediaTag(id: 101, name: "Emma Ghafouri"), MediaTag(id: 102, name: "Noah Ghafouri")]
            default: []
            }
            return Media(id: i, thumbURL: nil, fullURL: nil, isVideo: i == 7, title: nil, tags: tags, canEditTags: true)
        }
    }

    static var albums: [Album] {[
        Album(id: 1, title: "Efterårsferie", date: ago(60 * 24 * 10), coverURL: nil, count: 24),
        Album(id: 2, title: "Motionsdag", date: ago(60 * 24 * 30), coverURL: nil, count: 41),
        Album(id: 3, title: "Juletræet pyntes", date: ago(60 * 24 * 2), coverURL: nil, count: 12),
        Album(id: 4, title: "Skovtur", date: ago(60 * 24 * 60), coverURL: nil, count: 33),
    ]}

    static var weekPlans: [WeekPlan] {[
        WeekPlan(childName: "Emma Ghafouri", sections: [
            .init(title: "3.A — Ugebrev", html: "<p>Denne uge arbejder vi med <b>brøker</b> i matematik og læser højt af <i>Ronja Røverdatter</i>.</p><p>Husk idrætstøj tirsdag og torsdag.</p>"),
            .init(title: "Dansk", html: "<p>Læs kapitel 4 og 5 til torsdag.</p>"),
        ]),
    ]}

    static var tasks: [SchoolTask] {[
        SchoolTask(id: "t1", title: "Læs kapitel 4-5", subject: "Dansk", due: at(3, 8), weekday: nil, childName: "Emma Ghafouri", isDone: false),
        SchoolTask(id: "t2", title: "Brøk-opgaver side 32", subject: "Matematik", due: at(2, 8), weekday: nil, childName: "Emma Ghafouri", isDone: true),
    ]}

    static var vacationRequests: [VacationRequest] {[
        VacationRequest(id: 1, responseId: 1, childId: 102, childName: "Noah", title: "Juleferie 2026",
                        start: at(10, 0), end: at(20, 0), deadline: at(4, 0), note: "Giv besked om Noah kommer i juleferien.",
                        isEditable: true, isMissingAnswer: true, needsTimes: true),
    ]}

    static var dayPlans: [DayPlan] {
        Week.days(of: Week.start(of: .now)).prefix(5).map { d in
            DayPlan(templateId: 1, childId: 102, date: d, entry: "07:45", exit: "16:00", kind: .pickedUpBy,
                    exitWith: "Sara (Mor)", comment: nil, isOnVacation: false, repeats: true)
        }
    }

    static var birthdays: [Birthday] {
        let cal = Calendar.current
        return [
            Birthday(id: 9001, name: "Liva Holm", date: cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: .now))!,
                     group: "Solsikken", institutionCode: "101002"),
            Birthday(id: noah.id, name: noah.name, date: cal.date(byAdding: .day, value: 5, to: cal.startOfDay(for: .now))!,
                     group: "Solsikken", institutionCode: "101002"),
        ]
    }

    /// Fixture for a Loadable cache key (prefix match for week-keyed caches).
    static func value(for key: String) -> Any? {
        switch key {
        case "session": return session
        case "presence": return presence
        case "threads": return threads
        case "posts": return posts
        case "notifications": return notifications
        case "important-dates": return importantDates
        case "albums": return albums
        case "vacation-requests": return vacationRequests
        case "birthdays": return birthdays
        case "posts-important": return posts.filter(\.isImportant)
        case "posts-staff", "posts-unread": return posts
        case "posts-parents", "posts-own", "posts-saved": return [Post]()
        default:
            if key.hasPrefix("events-") { return events }
            if key.hasPrefix("thread-") { return threadPage }
            if key.hasPrefix("weekplan-") { return weekPlans }
            if key.hasPrefix("tasks-") { return tasks }
            if key.hasPrefix("plans-") { return dayPlans }
            if key.hasPrefix("album-") || key.hasPrefix("tagged-") { return media }
            return nil
        }
    }
}

/// Screens opened inside the Today and More tabs. Everything goes through the tab's
/// navigation path: mixing `NavigationLink { View }` with value links in a path-based
/// stack makes SwiftUI push the wrong screens (e.g. the gallery again on top of an album).
enum Route: Hashable {
    case posts, gallery, importantDates, documents, contacts, vacations, notifications, settings
    case child(Child)
    case document(SecureDocument)
    case empty          // screenshot runs only
}
