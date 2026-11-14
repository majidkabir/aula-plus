import Foundation

/// Aula's own notification settings (what Aula sends by push and e-mail), as on aula.dk.
struct AulaNotificationSettings: Equatable {
    struct Switch: Equatable, Identifiable {
        let id: String       // comeGoType or widget id
        let title: String
        var on: Bool
    }
    var instant: Bool
    /// "HHmm", used when `instant` is off (a daily summary).
    var scheduledTime: String?
    var days: [Bool]         // Monday…Sunday
    var push: Bool
    var pushAvailable: Bool
    var email: Bool
    var emailAvailable: Bool
    var fromEmployees: Bool
    var fromGuardians: Bool
    var fromChildren: Bool
    var calendar: Bool
    var gallery: Bool
    var posts: Bool
    var substitute: Bool
    var lessonNote: Bool
    var comeGo: [Switch]
    var widgets: [Switch]
}

/// A calendar feed (iCal link) Aula keeps up to date, for the phone's own calendar.
struct CalendarFeed: Equatable, Identifiable {
    let id: Int
    let oneWeek: URL?
    let oneYear: URL?
}

extension AulaAPI {
    func notificationSettings() async throws -> AulaNotificationSettings {
        let d: NotificationSettingsDTO = try await call("Notifications.getNotificationSettingsForActiveProfile")
        let days = [d.monday, d.tuesday, d.wednesday, d.thursday, d.friday, d.saturday, d.sunday].map { $0 ?? false }
        return AulaNotificationSettings(
            instant: d.instant ?? true,
            scheduledTime: d.scheduledTime,
            days: days,
            push: !(d.appDisabled ?? false), pushAvailable: d.appAvailable ?? true,
            email: !(d.emailDisabled ?? true), emailAvailable: d.emailAvailable ?? false,
            fromEmployees: d.notifyMessagesFromEmployees ?? true,
            fromGuardians: d.notifyMessagesFromGuardians ?? true,
            fromChildren: d.notifyMessagesFromChildren ?? true,
            calendar: d.notifyCalendar ?? true,
            gallery: d.notifyGallery ?? true,
            posts: d.notifyPosts ?? true,
            substitute: d.notifyAssignedAsSubstituteTeacher ?? false,
            lessonNote: d.notifyLessonNoteChanged ?? false,
            comeGo: (d.comeGoNotificationSettings?.items ?? []).compactMap { c in
                guard let type = c.comeGoType else { return nil }
                return .init(id: type, title: Self.comeGoTitle(type), on: c.activated ?? false)
            },
            widgets: (d.widgetNotificationSettingDtos?.items ?? []).compactMap { w in
                guard let id = w.widgetId?.value else { return nil }
                return .init(id: String(id), title: w.title ?? "Widget", on: w.isActive ?? false)
            })
    }

    func saveNotificationSettings(_ s: AulaNotificationSettings) async throws {
        let names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        var body: [String: Any] = [
            "scheduledTime": s.instant ? NSNull() as Any : (s.scheduledTime ?? "0800") as Any,
            "notifyMessages": s.fromEmployees || s.fromGuardians || s.fromChildren,
            "notifyMessagesFromEmployees": s.fromEmployees,
            "notifyMessagesFromGuardians": s.fromGuardians,
            "notifyMessagesFromChildren": s.fromChildren,
            "notifyCalendar": s.calendar,
            "notifyAssignedAsSubstituteTeacher": s.substitute,
            "notifyLessonNoteChanged": s.lessonNote,
            "notifyGallery": s.gallery,
            "notifyPosts": s.posts,
            "widgetSettings": s.widgets.map { ["widgetId": Int($0.id) ?? 0, "title": $0.title, "isActive": $0.on] as [String: Any] },
            "comeGoNotificationSettings": s.comeGo.map { ["comeGoType": $0.id, "activated": $0.on] as [String: Any] },
            "appDisabled": !s.push,
            "emailDisabled": !s.email,
            "instant": s.instant,
        ]
        for (i, n) in names.enumerated() { body[n] = s.instant ? false : s.days[i] }
        let _: Ignored = try await call("Notifications.setNotificationSettingsForActiveProfile", body: body)
    }

    static func comeGoTitle(_ type: String) -> String {
        switch type {
        case "VacationRegistrationRequest": return String(localized: "Ferieanmodninger")
        case "PickupActivity": return String(localized: "Afhentning")
        default: return type
        }
    }

    // MARK: Calendar feed

    func calendarFeedPolicyAccepted() async throws -> Bool {
        let d: PolicyDTO = try await call("CalendarFeed.getPolicyAnswer")
        return d.policyAccepted ?? false
    }

    func calendarFeeds() async throws -> [CalendarFeed] {
        let list: Lossy<FeedDTO> = try await call("CalendarFeed.getFeedConfigurations")
        return list.items.compactMap(\.model)
    }

    /// Accepts Aula's terms for calendar feeds and creates one with every event type a guardian can get.
    func createCalendarFeed(institutionProfileId: Int) async throws {
        let _: Ignored = try await call("CalendarFeed.setPolicyAnswer", body: ["policyAccepted": true])
        let types: TypesDTO = try await call("calendarFeed.getEventTypesRelevantForPortalRole",
                                             query: [.init(name: "PortalRole", value: "guardian")])
        let filters = types.eventTypes ?? ["event", "holiday", "excursion", "other", "school_home_meeting", "parental_meeting"]
        let _: Ignored = try await call("CalendarFeed.createFeedConfiguration", body: [
            "institutionProfileId": institutionProfileId,
            "filters": filters,
        ])
    }

    func deleteCalendarFeed(_ id: Int) async throws {
        let _: Ignored = try await call("CalendarFeed.removeFeedConfiguration", body: ["calendarFeedConfigurationId": id])
    }
}

private struct NotificationSettingsDTO: Decodable {
    struct ComeGo: Decodable { let comeGoType: String?; let activated: Bool? }
    struct Widget: Decodable { let title: String?; let widgetId: FlexInt?; let isActive: Bool? }
    let scheduledTime: String?
    let instant: Bool?
    let monday, tuesday, wednesday, thursday, friday, saturday, sunday: Bool?
    let notifyMessagesFromEmployees, notifyMessagesFromChildren, notifyMessagesFromGuardians: Bool?
    let notifyCalendar, notifyGallery, notifyPosts: Bool?
    let notifyAssignedAsSubstituteTeacher, notifyLessonNoteChanged: Bool?
    let emailDisabled, emailAvailable, appDisabled, appAvailable: Bool?
    let comeGoNotificationSettings: Lossy<ComeGo>?
    let widgetNotificationSettingDtos: Lossy<Widget>?
}

private struct PolicyDTO: Decodable { let policyAccepted: Bool? }
private struct TypesDTO: Decodable { let eventTypes: [String]? }

private struct FeedDTO: Decodable {
    struct Config: Decodable {
        let id: FlexInt?
        let oneWeekFeed: String?
        let oneYearFeed: String?
    }
    let id: FlexInt?
    let oneWeekFeed: String?
    let oneYearFeed: String?
    /// Some answers nest the feed inside a profile.
    let calendarFeedConfiguration: Config?

    var model: CalendarFeed? {
        let c = calendarFeedConfiguration
        guard let id = (c?.id ?? id)?.value else { return nil }
        return CalendarFeed(id: id,
                            oneWeek: (c?.oneWeekFeed ?? oneWeekFeed).flatMap(URL.init(string:)),
                            oneYear: (c?.oneYearFeed ?? oneYearFeed).flatMap(URL.init(string:)))
    }
}
