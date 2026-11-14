import Foundation

// Request shapes for these calls come from the decompiled official app
// (eisbaw/aulalibre). They are not all verified against a live account,
// so the UI shows Aula's error text when a call is rejected.

enum RSVP: String, Codable, CaseIterable {
    case accepted, declined, tentative, waiting

    var label: String {
        switch self {
        case .accepted: return String(localized: "Deltager")
        case .declined: return String(localized: "Deltager ikke")
        case .tentative: return String(localized: "Måske")
        case .waiting: return String(localized: "Ikke svaret")
        }
    }
}

struct EventDetail: Codable, Hashable {
    struct Invitee: Codable, Hashable {
        let institutionProfileId: Int?
        let name: String
        let response: RSVP?
    }
    let id: Int
    let title: String
    let html: String
    let start: Date?
    let end: Date?
    let allDay: Bool
    let location: String?
    let creator: String?
    let responseRequired: Bool
    let responseDeadline: Date?
    let deadlineExceeded: Bool
    let myResponse: RSVP?
    let invitees: [Invitee]
    let attachments: [Attachment]
    var type: String? = nil
    var slots: [MeetingSlot] = []
}

struct Recipient: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let detail: String?
    let type: String
}

private struct EventDetailDTO: Decodable {
    struct Profile: Decodable { let institutionProfileId: FlexInt?; let fullName: String?; let firstName: String?; let lastName: String? }
    struct Invitee: Decodable { let instProfile: Profile?; let responseType: String? }
    struct Creator: Decodable { let name: String? }
    struct Resource: Decodable { let name: String? }
    let id: FlexInt
    let title: String?
    let description: HTMLField?
    let startDateTime: String?
    let endDateTime: String?
    let allDay: Bool?
    let primaryResource: Resource?
    let primaryResourceText: String?
    let creator: Creator?
    let responseRequired: Bool?
    let responseDeadline: String?
    let isDeadlineExceeded: Bool?
    let responseStatus: String?
    let invitees: Lossy<Invitee>?
    let attachments: Lossy<AttachmentDTO>?
    let type: String?
    let timeSlot: TimeSlotDTO?
}

/// Accepts whatever startNewThread answers (an id, an object, or nothing)
/// so a successful send is never reported as a failure.
struct CreatedThread: Decodable {
    let id: String?
    private enum K: String, CodingKey { case id, threadId }
    init(from decoder: Decoder) throws {
        if let v = try? FlexString(from: decoder), !v.value.isEmpty { id = v.value; return }
        let c = try? decoder.container(keyedBy: K.self)
        let a = try? c?.decode(FlexString.self, forKey: .threadId)
        let b = try? c?.decode(FlexString.self, forKey: .id)
        id = (a ?? b)?.value
    }
}

private struct RecipientsDTO: Decodable {
    struct Item: Decodable {
        let docId: FlexString?
        let docType: String?
        let name: String?
        let institutionName: String?
        let description: String?
    }
    let results: Lossy<Item>?
}

extension AulaAPI {
    func eventDetail(id: String) async throws -> EventDetail {
        let d: EventDetailDTO = try await call("calendar.getEventById", query: [.init(name: "eventId", value: id)])
        let invitees: [EventDetail.Invitee] = (d.invitees?.items ?? []).map { i in
            let p = i.instProfile
            let parts: [String] = [p?.firstName, p?.lastName].compactMap { $0 }
            let name: String = p?.fullName ?? parts.joined(separator: " ")
            return .init(institutionProfileId: p?.institutionProfileId?.value, name: name,
                         response: i.responseType.flatMap { RSVP(rawValue: $0.lowercased()) })
        }
        return EventDetail(id: d.id.value,
                           title: d.title?.nilIfEmpty ?? String(localized: "Begivenhed"),
                           html: d.description?.html ?? "",
                           start: AulaDate.parse(d.startDateTime),
                           end: AulaDate.parse(d.endDateTime),
                           allDay: d.allDay ?? false,
                           location: d.primaryResource?.name ?? d.primaryResourceText?.nilIfEmpty,
                           creator: d.creator?.name,
                           responseRequired: d.responseRequired ?? false,
                           responseDeadline: AulaDate.parse(d.responseDeadline),
                           deadlineExceeded: d.isDeadlineExceeded ?? false,
                           myResponse: d.responseStatus.flatMap { RSVP(rawValue: $0.lowercased()) },
                           invitees: invitees,
                           attachments: d.attachments?.items.map(\.model) ?? [],
                           type: d.type, slots: d.timeSlot?.slots ?? [])
    }

    func respond(eventId: Int, as profileId: Int, response: RSVP) async throws {
        let _: Ignored = try await call("calendar.respondToSimpleEvent", body: [
            "eventId": eventId,
            "institutionProfileId": profileId,
            "invitedInstProfileId": profileId,
            "responseType": response.rawValue,
            "occurrenceDateTime": NSNull(),
        ])
    }

    func findRecipients(_ text: String) async throws -> [Recipient] {
        let dto: RecipientsDTO = try await call("search.findRecipients", query: [
            .init(name: "Text", value: text),
            .init(name: "Limit", value: "30"),
            .init(name: "TypeAhead", value: "true"),
        ])
        return (dto.results?.items ?? []).compactMap { r in
            guard let id = r.docId.flatMap({ Int($0.value) }) else { return nil }
            let detail: [String?] = [r.description?.nilIfEmpty, r.institutionName?.nilIfEmpty]
            return Recipient(id: id, name: r.name ?? String(localized: "Ukendt"),
                             detail: detail.compactMap { $0 }.first,
                             type: r.docType ?? "Profile")
        }
    }

    /// Starts a new thread. Returns the new thread id when Aula sends one.
    @discardableResult
    func startThread(subject: String, text: String, recipients: [Recipient], sensitive: Bool, attachmentIds: [Int] = []) async throws -> String? {
        let recips: [[String: Any]] = recipients.map { r in
            ["id": r.id,
             "mailBoxOwnerType": r.type.lowercased().contains("group") ? "Group" : "InstitutionProfile",
             "profileId": r.id,
             "otpInboxId": NSNull()]
        }
        let created: CreatedThread = try await call("messaging.startNewThread", body: [
            "subject": subject,
            "message": ["text": Self.htmlFromPlainText(text), "attachmentIds": attachmentIds] as [String: Any],
            "recipients": recips,
            "bccRecipients": [[String: Any]](),
            "sensitive": sensitive,
            "creator": NSNull(),
        ])
        return created.id
    }

    func setMarked(threadId: String, marked: Bool) async throws {
        let _: Ignored = try await call("messaging.setThreadsMarked", body: [
            "marked": marked,
            "threadIds": [Int(threadId) ?? 0],
            "subscriptionIds": NSNull(),
            "commonInboxId": NSNull(),
        ])
    }

    func deleteThread(_ threadId: String) async throws {
        let _: Ignored = try await call("messaging.deleteThreads", body: [
            "threadIds": [Int(threadId) ?? 0],
            "subscriptionIds": NSNull(),
            "commonInboxId": NSNull(),
        ])
    }

    func addComment(postId: Int, text: String, asProfile profileId: Int) async throws {
        let _: Ignored = try await call("comments.addComment", body: [
            "commentableItem": ["type": "post", "id": postId],
            "content": text,
            "creatorInstProfileId": profileId,
        ])
    }
}
