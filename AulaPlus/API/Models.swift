import Foundation

// MARK: - Domain models (Codable so they can be cached on disk)

struct Child: Codable, Identifiable, Hashable {
    let id: Int                 // institution profile id — used in API calls
    let name: String
    let institutionName: String
    let institutionCode: String?
    let userId: String?         // UniLogin — used by week-plan widgets
    let pictureURL: URL?

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

struct Session: Codable {
    let displayName: String
    let children: [Child]
    let institutionProfileIds: [Int]   // guardian's own + children's
    let guardianUserId: String?        // profileContext.data.userId (widget sessionUUID)
    let widgetIds: Set<String>
    var guardianProfileIds: [Int]? = nil  // the guardian's own institution profiles
    var widgetNames: [String: String]? = nil  // widget id → name, as Aula shows it
    var widgetLinks: [WidgetLink]? = nil       // widgets with a web address (opened in the browser)

    /// Widgets that look like a week plan, by Aula's own name for them.
    var weekPlanWidgetNames: [String] {
        let hint = #/(?i)uge|plan|lektie|opgave|easyiq|meebook|docendo|huskeliste|forløb|skoleportal/#
        return (widgetNames ?? [:]).values.filter { $0.contains(hint) }.sorted()
    }

    /// False when Aula offers no week plan at all (typical for nurseries and kindergartens).
    var hasWeekPlan: Bool {
        !widgetIds.isDisjoint(with: [AulaConfig.Widget.meebook, AulaConfig.Widget.muUgeplan, AulaConfig.Widget.muSSO])
            || !weekPlanWidgetNames.isEmpty
    }
}

/// A tool Aula shows on the parent's front page, with a link to open it.
struct WidgetLink: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let url: URL
}

enum PresenceStatus: Int, Codable {
    case notPresent = 0, sick, reportedAbsent, present, fieldTrip, sleeping,
         spareTimeActivity, physicalPlacement, checkedOut, notArrived

    var label: String {
        switch self {
        case .notPresent: return String(localized: "Ikke kommet")
        case .sick: return String(localized: "Syg")
        case .reportedAbsent: return String(localized: "Ferie/fri")
        case .present: return String(localized: "Til stede")
        case .fieldTrip: return String(localized: "På tur")
        case .sleeping: return String(localized: "Sover")
        case .spareTimeActivity: return String(localized: "Til aktivitet")
        case .physicalPlacement: return "Fysisk placering"
        case .checkedOut: return String(localized: "Gået hjem")
        case .notArrived: return String(localized: "Ikke mødt")
        }
    }

    var symbol: String {
        switch self {
        case .present, .physicalPlacement: return "checkmark.circle.fill"
        case .sick: return "cross.case.fill"
        case .reportedAbsent: return "sun.max.fill"
        case .fieldTrip: return "bus.fill"
        case .sleeping: return "moon.zzz.fill"
        case .spareTimeActivity: return "figure.run"
        case .checkedOut: return "house.fill"
        case .notPresent, .notArrived: return "circle.dashed"
        }
    }
}

struct Presence: Codable, Hashable {
    let childId: Int
    let status: PresenceStatus?
    let checkIn: String?
    let checkOut: String?
    let plannedEntry: String?
    let plannedExit: String?
    let exitWith: String?
    let comment: String?
    let location: String?

    /// Aula's "no plan" times: the institution's whole opening window.
    static func isPlaceholder(entry: String?, exit: String?) -> Bool {
        (entry == nil || entry == "05:00" || entry == "00:00") && (exit == nil || exit == "23:59")
    }

    /// Not coming today: no drop-off or pick-up planned and not checked in.
    var isDayOff: Bool {
        checkIn == nil && checkOut == nil
            && Self.isPlaceholder(entry: plannedEntry, exit: plannedExit)
            && (status == nil || status == .notArrived || status == .notPresent)
    }
}

struct Attachment: Codable, Hashable {
    let name: String
    let url: URL?
    var isLink: Bool? = nil   // web link rather than a file
}

struct ThreadSummary: Codable, Identifiable, Hashable {
    let id: String
    let subject: String
    let preview: String
    let sender: String
    let date: Date?
    var isRead: Bool
    let isSensitive: Bool
    let regarding: [String]
    var isMarked: Bool? = nil
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let sender: String
    let date: Date?
    let html: String
    let attachments: [Attachment]
}

struct ThreadPage: Codable {
    let subject: String
    let messages: [Message]       // newest first, as Aula returns them
    let moreExist: Bool
    let lastReadMessageId: String?
    let isOwnMailbox: Bool
}

struct Event: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
    let teacher: String?
    let substitute: String?
    let hasSubstitute: Bool
    let type: String?
    let childIds: [Int]

    /// True on every day the event covers (multi-day holidays too; an all-day end at midnight is exclusive).
    func occurs(on day: Date) -> Bool {
        let cal = Calendar.week
        let first = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: max(start, end.addingTimeInterval(-0.001)))
        let d = cal.startOfDay(for: day)
        return d >= first && d <= last
    }
}

struct Post: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let html: String
    let date: Date?
    let author: String
    let isImportant: Bool
    let attachments: [Attachment]
    var canComment: Bool? = nil
}

struct WeekPlan: Codable, Hashable {
    struct Section: Codable, Hashable {
        let title: String
        let html: String
    }
    let childName: String
    let sections: [Section]
}

// MARK: - DTOs (raw Aula JSON)

struct StatusDTO: Decodable {
    let code: Int?
    let subCode: Int?
    let message: String?
}

struct StatusEnvelope: Decodable { let status: StatusDTO? }
struct Envelope<T: Decodable>: Decodable { let data: T? }

struct PictureDTO: Decodable { let url: String? }

struct ProfilesByLoginDTO: Decodable {
    let profiles: Lossy<ProfileDTO>?
}

struct ProfileDTO: Decodable {
    let displayName: String?
    let children: Lossy<ChildDTO>?
    let institutionProfiles: Lossy<IdDTO>?
}

struct IdDTO: Decodable { let id: FlexInt }

struct ChildDTO: Decodable {
    struct Inst: Decodable { let institutionName: String?; let institutionCode: FlexString? }
    let id: FlexInt
    let name: String?
    let userId: FlexString?
    let institutionCode: FlexString?
    let profilePicture: PictureDTO?
    let institutionProfile: Inst?

    func toChild(fallbackInstitution: String? = nil) -> Child {
        Child(id: id.value,
              name: name ?? String(localized: "Barn"),
              institutionName: institutionProfile?.institutionName ?? fallbackInstitution ?? "",
              institutionCode: (institutionProfile?.institutionCode ?? institutionCode)?.value,
              userId: userId?.value,
              pictureURL: profilePicture?.url.flatMap(URL.init(string:)))
    }
}

struct ProfileContextDTO: Decodable {
    struct Institution: Decodable { let name: String?; let children: Lossy<ChildDTO>? }
    struct PageConfig: Decodable { let widgetConfigurations: Lossy<WidgetConfigDTO>? }
    let userId: FlexString?
    let institutions: Lossy<Institution>?
    let pageConfiguration: PageConfig?
}

struct WidgetConfigDTO: Decodable {
    struct Widget: Decodable { let widgetId: FlexString?; let name: String?; let url: String?; let widgetType: String? }
    let widget: Widget?
    let aggregatedDisplayMode: String?
}

struct DailyOverviewDTO: Decodable {
    struct Inst: Decodable { let id: FlexInt? }
    struct Location: Decodable {
        let name: String?
        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) { name = s; return }
            struct N: Decodable { let name: String? }
            name = (try? N(from: decoder))?.name
        }
    }
    let status: Int?
    let checkInTime: String?
    let checkOutTime: String?
    let entryTime: String?
    let exitTime: String?
    let exitWith: String?
    let comment: String?
    let location: Location?
    let institutionProfile: Inst?
}

struct PersonDTO: Decodable {
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let name: String?
    var best: String {
        let candidates: [String?] = [fullName, displayName, name]
        if let hit = candidates.compactMap({ $0 }).first { return hit }
        let parts: [String] = [firstName, lastName].compactMap { $0 }
        return parts.joined(separator: " ")
    }
}

struct AttachmentDTO: Decodable {
    struct FileDTO: Decodable { let name: String?; let url: String? }
    struct MediaDTO: Decodable { let title: String?; let file: FileDTO? }
    struct LinkDTO: Decodable { let name: String?; let url: String? }
    struct DocDTO: Decodable { let title: String? }
    let name: String?
    let url: String?
    let file: FileDTO?
    let media: MediaDTO?
    let link: LinkDTO?
    let document: DocDTO?

    var model: Attachment {
        let urls: [String?] = [media?.file?.url, file?.url, url, link?.url]
        let names: [String?] = [name, file?.name, media?.file?.name, media?.title, link?.name, document?.title]
        let url: String? = urls.compactMap { $0 }.first
        let n: String = names.compactMap { $0?.nilIfEmpty }.first ?? String(localized: "Vedhæftet fil")
        let linkOnly: Bool = link?.url != nil && media?.file?.url == nil && file?.url == nil
        return Attachment(name: n, url: url.flatMap { URL(string: $0) }, isLink: linkOnly)
    }
}

struct ThreadsDTO: Decodable {
    let threads: Lossy<ThreadDTO>?
    let moreMessagesExist: Bool?
}

struct ThreadDTO: Decodable {
    struct Latest: Decodable {
        let sendDateTime: String?
        let sender: PersonDTO?
        let text: HTMLField?
    }
    let id: FlexString
    let subject: String?
    let read: Bool?
    let sensitive: Bool?
    let isSensitive: Bool?
    let marked: Bool?
    let lastMessageDate: String?
    let lastUpdatedDate: String?
    let latestMessage: Latest?
    let creator: PersonDTO?
    let regardingChildren: Lossy<PersonDTO>?

    var model: ThreadSummary {
        let senderName: String = latestMessage?.sender?.best.nilIfEmpty ?? creator?.best ?? ""
        let dateString: String? = latestMessage?.sendDateTime ?? lastMessageDate ?? lastUpdatedDate
        let regardingNames: [String] = (regardingChildren?.items ?? []).map(\.best).filter { !$0.isEmpty }
        let sensitiveFlag: Bool = sensitive ?? isSensitive ?? false
        return ThreadSummary(
            id: id.value,
            subject: subject?.nilIfEmpty ?? String(localized: "(Intet emne)"),
            preview: HTML.plainText(latestMessage?.text?.html ?? ""),
            sender: senderName,
            date: AulaDate.parse(dateString),
            isRead: read ?? true,
            isSensitive: sensitiveFlag,
            regarding: regardingNames,
            isMarked: marked ?? false)
    }
}

struct ThreadMessagesDTO: Decodable {
    struct Owner: Decodable { let mailBoxOwnerType: String? }
    struct MessageDTO: Decodable {
        let id: FlexString?
        let messageType: String?
        let sendDateTime: String?
        let sender: PersonDTO?
        let text: HTMLField?
        let attachments: Lossy<AttachmentDTO>?
    }
    let subject: String?
    let messages: Lossy<MessageDTO>?
    let moreMessagesExist: Bool?
    let lastReadMessageId: FlexString?
    let mailBoxOwner: Owner?

    var model: ThreadPage {
        let msgs = (messages?.items ?? [])
            .filter { ["Message", "MessageEdited"].contains($0.messageType ?? "Message") }
            .map { m in
                Message(id: m.id?.value ?? UUID().uuidString,
                        sender: m.sender?.best ?? "",
                        date: AulaDate.parse(m.sendDateTime),
                        html: m.text?.html ?? "",
                        attachments: m.attachments?.items.map(\.model) ?? [])
            }
        return ThreadPage(subject: subject ?? "",
                          messages: msgs,
                          moreExist: moreMessagesExist ?? false,
                          lastReadMessageId: lastReadMessageId?.value,
                          isOwnMailbox: mailBoxOwner?.mailBoxOwnerType == "institutionProfile")
    }
}

struct EventDTO: Decodable {
    struct Resource: Decodable { let name: String? }
    struct Participant: Decodable { let participantRole: String?; let teacherName: String? }
    struct Lesson: Decodable { let lessonStatus: String?; let participants: Lossy<Participant>? }
    let id: FlexString
    let title: String?
    let startDateTime: String?
    let endDateTime: String?
    let allDay: Bool?
    let type: String?
    let primaryResource: Resource?
    let lesson: Lesson?
    let belongsToProfiles: Lossy<Int>?

    var model: Event? {
        guard let start = AulaDate.parse(startDateTime) else { return nil }
        let end = AulaDate.parse(endDateTime) ?? start
        let people = lesson?.participants?.items ?? []
        let teacher = people.first { $0.participantRole == "primaryTeacher" }?.teacherName
        let sub = people.first { $0.participantRole == "substituteTeacher" }?.teacherName
        return Event(id: id.value,
                     title: title?.nilIfEmpty ?? String(localized: "Begivenhed"),
                     start: start, end: end,
                     allDay: allDay ?? false,
                     location: primaryResource?.name,
                     teacher: teacher,
                     substitute: sub,
                     hasSubstitute: lesson?.lessonStatus?.lowercased() == "substitute",
                     type: type,
                     childIds: belongsToProfiles?.items ?? [])
    }
}

struct PostsDTO: Decodable { let posts: Lossy<PostDTO>? }

struct PostDTO: Decodable {
    let id: FlexInt
    let title: String?
    let content: HTMLField?
    let timestamp: String?
    let publishAt: String?
    let ownerProfile: PersonDTO?
    let isImportant: Bool?
    let attachments: Lossy<AttachmentDTO>?
    let allowComments: Bool?
    let canCurrentUserComment: Bool?

    var model: Post {
        Post(id: id.value,
             title: title?.nilIfEmpty ?? String(localized: "Opslag"),
             html: content?.html ?? "",
             date: AulaDate.parse(publishAt ?? timestamp),
             author: ownerProfile?.best ?? "",
             isImportant: isImportant ?? false,
             attachments: attachments?.items.map(\.model) ?? [],
             canComment: (allowComments ?? false) && (canCurrentUserComment ?? true))
    }
}

// Min Uddannelse "ugebrev"
struct MUPersonDTO: Decodable {
    struct Letter: Decodable { let tilknytningNavn: String?; let indhold: String? }
    struct Inst: Decodable { let navn: String?; let ugebreve: Lossy<Letter>? }
    let navn: String?
    let institutioner: Lossy<Inst>?
}
struct MUResponseDTO: Decodable { let personer: Lossy<MUPersonDTO>? }

// Meebook week plan
struct MeebookStudentDTO: Decodable {
    struct TaskDTO: Decodable { let title: String?; let content: String?; let pill: String? }
    struct Day: Decodable { let date: String?; let tasks: Lossy<TaskDTO>? }
    let name: String?
    let weekPlan: Lossy<Day>?
}

extension String {
    var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
