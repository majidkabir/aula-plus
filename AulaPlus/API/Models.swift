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
    var pictureURL: URL? = nil                 // my own profile picture

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
    /// Set when the attachment is a photo or video from Aula's media library: shown inline.
    var media: Media? = nil
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
    var isMuted: Bool? = nil
    /// Aula's per-user subscription to the thread (needed to mute it).
    var subscriptionId: Int? = nil
    var folderId: Int? = nil
}

/// A message folder on Aula ("Slettet post" or one the user made). The inbox has no folder.
struct MailFolder: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    let type: String?
    var isDeleted: Bool { type?.lowercased() == "deleted" }
}

/// Aula's out-of-office reply for messages.
struct AutoReply: Codable, Hashable {
    let id: Int?
    let text: String
    let start: Date?
    let end: Date?
}

/// A message written in the app but not sent yet (kept on this phone only, like aula.dk's drafts).
struct MessageDraft: Codable, Identifiable, Hashable {
    var id = UUID()
    var recipients: [Recipient]
    var subject: String
    var text: String
    var sensitive: Bool
    var savedAt: Date
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let sender: String
    let date: Date?
    let html: String
    let attachments: [Attachment]
    var deleted: Bool? = nil
}

struct ThreadPage: Codable {
    let subject: String
    let messages: [Message]       // newest first, as Aula returns them
    let moreExist: Bool
    let lastReadMessageId: String?
    let isOwnMailbox: Bool
    /// Newest real message (incl. deleted ones and auto-replies) — what aula.dk moves the read marker to.
    var readMarkerId: String? = nil
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
    /// Saved ("Gemt") on Aula.
    var isBookmarked: Bool? = nil
}

/// The overview filters on aula.dk.
enum PostFilter: String, CaseIterable, Identifiable {
    case all, unread, important, staff, parents, own, saved
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: String(localized: "Alle")
        case .unread: String(localized: "Ulæste")
        case .important: String(localized: "Vigtige")
        case .staff: String(localized: "Personale")
        case .parents: String(localized: "Forældre")
        case .own: String(localized: "Egne opslag")
        case .saved: String(localized: "Gemte")
        }
    }
    /// The query aula.dk sends for this filter.
    var query: [URLQueryItem] {
        switch self {
        case .all: []
        case .unread: [.init(name: "isUnread", value: "true")]
        case .important: [.init(name: "isImportant", value: "true")]
        case .staff: [.init(name: "creatorPortalRole", value: "employee")]
        case .parents: [.init(name: "creatorPortalRole", value: "guardian")]
        case .own: [.init(name: "ownPost", value: "true")]
        case .saved: [.init(name: "isBookmarked", value: "true")]
        }
    }
}

struct Birthday: Codable, Identifiable, Hashable {
    let id: Int          // institution profile id
    let name: String
    let date: Date       // this year's (or next year's) birthday
    let group: String?
    let institutionCode: String?
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

struct IdDTO: Decodable { let id: FlexInt; var profilePicture: PictureDTO? = nil }

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
    struct MediaInfo: Decodable { let title: String?; let file: FileDTO?; let mediaType: String? }
    struct LinkDTO: Decodable { let name: String?; let url: String? }
    struct DocDTO: Decodable { let title: String? }
    let name: String?
    let url: String?
    let file: FileDTO?
    let media: MediaInfo?
    let link: LinkDTO?
    let document: DocDTO?
    /// The same `media` object, read as a full library item (thumbnails, tags) when it is one.
    let libraryMedia: MediaDTO?

    private enum CodingKeys: String, CodingKey { case name, url, file, media, link, document }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        file = try? c.decodeIfPresent(FileDTO.self, forKey: .file)
        media = try? c.decodeIfPresent(MediaInfo.self, forKey: .media)
        link = try? c.decodeIfPresent(LinkDTO.self, forKey: .link)
        document = try? c.decodeIfPresent(DocDTO.self, forKey: .document)
        libraryMedia = try? c.decodeIfPresent(MediaDTO.self, forKey: .media)
    }

    var model: Attachment {
        let urls: [String?] = [media?.file?.url, file?.url, url, link?.url]
        let names: [String?] = [name, file?.name, media?.file?.name, media?.title, link?.name, document?.title]
        let url: String? = urls.compactMap { $0 }.first
        let n: String = names.compactMap { $0?.nilIfEmpty }.first ?? String(localized: "Vedhæftet fil")
        let linkOnly: Bool = link?.url != nil && media?.file?.url == nil && file?.url == nil
        var shown: Media? = nil
        if let m = libraryMedia?.model, m.thumbURL != nil || m.fullURL != nil {
            let type = (media?.mediaType ?? "").lowercased()
            if type.isEmpty || type.contains("image") || type.contains("video") || type.contains("media") { shown = m }
        }
        return Attachment(name: n, url: url.flatMap { URL(string: $0) }, isLink: linkOnly, media: shown)
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
    let muted: Bool?
    let subscriptionId: FlexInt?
    let folderId: FlexInt?
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
            isMarked: marked ?? false,
            isMuted: muted ?? false,
            subscriptionId: subscriptionId?.value,
            folderId: folderId?.value)
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
        // Same types aula.dk counts as messages; system lines (recipients added etc.) are skipped.
        let real = (messages?.items ?? [])
            .filter { ["Message", "MessageEdited", "MessageDeleted", "AutoReply"].contains($0.messageType ?? "Message") }
        let msgs = real.map { m in
            Message(id: m.id?.value ?? UUID().uuidString,
                    sender: m.sender?.best ?? "",
                    date: AulaDate.parse(m.sendDateTime),
                    html: m.messageType == "MessageDeleted" ? "" : m.text?.html ?? "",
                    attachments: m.messageType == "MessageDeleted" ? [] : m.attachments?.items.map(\.model) ?? [],
                    deleted: m.messageType == "MessageDeleted" ? true : nil)
        }
        return ThreadPage(subject: subject ?? "",
                          messages: msgs,
                          moreExist: moreMessagesExist ?? false,
                          lastReadMessageId: lastReadMessageId?.value,
                          isOwnMailbox: mailBoxOwner?.mailBoxOwnerType == "institutionProfile",
                          readMarkerId: real.first?.id?.value)
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
    let isBookmarked: Bool?

    var model: Post {
        Post(id: id.value,
             title: title?.nilIfEmpty ?? String(localized: "Opslag"),
             html: content?.html ?? "",
             date: AulaDate.parse(publishAt ?? timestamp),
             author: ownerProfile?.best ?? "",
             isImportant: isImportant ?? false,
             attachments: attachments?.items.map(\.model) ?? [],
             canComment: (allowComments ?? false) && (canCurrentUserComment ?? true),
             isBookmarked: isBookmarked ?? false)
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
