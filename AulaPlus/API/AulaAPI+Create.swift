import Foundation

// Creating things in Aula: events, albums, photo uploads and booking meeting times.
// Request shapes are read from aula.dk's own web app; they are not tested against
// a live account, so the UI always shows Aula's error text when a call is rejected.

/// One bookable time in a meeting (school-home talk, parent meeting …).
struct MeetingSlot: Codable, Hashable, Identifiable {
    var id: String { "\(slotId)-\(index)" }
    let slotId: Int
    let index: Int
    let start: Date
    let end: Date
    /// Who has booked it (institution profile id), when someone has.
    let bookedFor: Int?
    let blocked: Bool
}

/// The guardian's own profile at one institution — the "owner" of what is created there.
struct OwnerProfile: Hashable {
    let institutionProfileId: Int
    let institutionCode: String
    let institutionName: String
}

enum NewEventType: String, CaseIterable, Identifiable {
    case event, other
    var id: String { rawValue }
    var label: String { self == .event ? String(localized: "Begivenhed") : String(localized: "Andet") }
}

struct NewEvent {
    var title = ""
    var type: NewEventType = .event
    var start: Date
    var end: Date
    var allDay = false
    var location = ""
    var description = ""
    var invitees: [Recipient] = []
    var responseRequired = true
    var responseDeadline: Date? = nil
    var isPrivate = false
}

extension AulaAPI {
    /// My guardian profiles, one per institution, from aula.dk's profile context.
    func ownerProfiles() async throws -> [OwnerProfile] {
        let ctx: OwnerContextDTO = try await call("profiles.getProfileContext", query: [.init(name: "portalrole", value: "guardian")])
        return (ctx.institutions?.items ?? []).compactMap { i in
            guard let id = i.institutionProfileId?.value, let code = i.institutionCode?.value else { return nil }
            return OwnerProfile(institutionProfileId: id, institutionCode: code, institutionName: i.name ?? code)
        }
    }

    /// Uploads one photo the way aula.dk does: ask for an upload form, then post the file to Aula's storage.
    /// Returns the new media id.
    @discardableResult
    func uploadPhoto(_ jpeg: Data, name: String = "billede.jpg", owner: Int, institutionCode: String?,
                     tags: [Int] = [], albumId: Int? = nil) async throws -> Int {
        let uploadId = UUID().uuidString.lowercased()
        let created: UploadCreatedDTO = try await call("files.createAttachments", body: [
            "media": [[
                "file": [String: Any](),
                "name": name,
                "mediaType": "image",
                "rotationDegree": 0,
                "title": NSNull(),
                "description": NSNull(),
                "tags": tags,
                "albumId": albumId.map { $0 as Any } ?? NSNull(),
                "sensitivityLevel": NSNull(),
                "allowsComments": true,
                "uploadId": uploadId,
            ] as [String: Any]],
            "files": [Any](),
            "links": [Any](),
            "existingMedia": [Any](),
            "attachedSecureDocumentIds": NSNull(),
            "ownerInstitutionProfileId": owner,
            "institutionCode": institutionCode.map { $0 as Any } ?? NSNull(),
        ])
        guard let media = created.media?.items.first(where: { $0.uploadId == uploadId }) ?? created.media?.items.first,
              let mediaId = media.id?.value, let form = media.fileUploadInformation,
              let action = form["action"], let url = URL(string: action) else {
            throw AulaError.decoding("files.createAttachments")
        }
        let boundary = "AulaPlus-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        for (k, v) in form where k != "action" { field(k.replacingOccurrences(of: "_", with: "-"), v) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.upload(for: req, from: body)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AulaError.http(status) }
        return mediaId
    }

    /// "Opret begivenhed" as a parent.
    func createEvent(_ e: NewEvent, owner: OwnerProfile) async throws {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AulaDate.copenhagen
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSZ"
        var start = e.start, end = e.end
        if e.allDay {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = AulaDate.copenhagen
            start = cal.startOfDay(for: e.start)
            end = cal.date(bySettingHour: 23, minute: 59, second: 0, of: e.end) ?? e.end
        }
        let people = e.invitees.filter { !$0.type.lowercased().contains("group") }
        let groups = e.invitees.filter { $0.type.lowercased().contains("group") }
        var html = Self.htmlFromPlainText(e.description)
        if !e.location.trimmingCharacters(in: .whitespaces).isEmpty {
            html = "<p>\(String(localized: "Sted")): \(e.location.htmlEscaped)</p>" + html
        }
        let _: Ignored = try await call("calendar.createSimpleEvent", body: [
            "eventId": NSNull(),
            "institutionCode": owner.institutionCode,
            "creatorInstProfileId": owner.institutionProfileId,
            "title": e.title,
            "type": e.type.rawValue,
            "startDateTime": f.string(from: start),
            "endDateTime": f.string(from: end),
            "allDay": e.allDay,
            "isPrivate": e.isPrivate,
            "private": e.isPrivate,
            "additionalResourceText": e.location,
            "description": html,
            "inviteeIds": people.map(\.id),
            "invitedGroupIds": groups.map(\.id),
            "inviteeGroups": groups.map { ["groupId": $0.id, "portalRoles": ["guardian", "child", "employee"]] as [String: Any] },
            "invitedOtpInboxIds": [Int](),
            "coOrganizerIds": [Int](),
            "resourceIds": [Int](),
            "additionalLocationIds": [Int](),
            "additionalResourceIds": [Int](),
            "primaryResourceId": NSNull(),
            "responseRequired": e.responseRequired && !(people.isEmpty && groups.isEmpty),
            "responseDeadline": e.responseDeadline.map { f.string(from: $0) as Any } ?? NSNull(),
            "maximumNumberOfParticipants": NSNull(),
            "doRequestNumberOfParticipants": false,
            "addToInstitutionCalendar": false,
            "hideInOwnCalendar": false,
            "attachmentIds": [Int](),
            "pattern": "never",
            "occurenceLimit": 0,
            "weekdayMask": NSNull(),
            "maxDate": NSNull(),
            "interval": 0,
            "isEditEvent": false,
        ])
    }

    /// "Opret album": returns the new album id when Aula sends one.
    func createAlbum(title: String, description: String, groups: [AulaGroup], owner: OwnerProfile) async throws -> Int? {
        let created: CreatedId = try await call("gallery.createAlbum", body: [
            "title": title,
            "description": description,
            "sharedWithGroups": groups.map {
                ["id": $0.id, "groupId": $0.id, "name": $0.name, "portalRoles": ["guardian", "child", "employee"]] as [String: Any]
            },
            "creatorInstitutionProfileId": owner.institutionProfileId,
        ])
        return created.id
    }

    // MARK: Meeting times

    func bookSlot(eventId: Int, slot: MeetingSlot, for profileId: Int) async throws {
        let _: Ignored = try await call("calendar.respondToTimeSlotEvent", body: [
            "eventId": eventId, "timeSlotId": slot.slotId, "timeSlotIndex": slot.index, "concerningInstProfileId": profileId,
        ])
    }

    func moveBooking(eventId: Int, to slot: MeetingSlot, for profileId: Int) async throws {
        let _: Ignored = try await call("calendar.updateResponseToTimeSlotEvent", body: [
            "eventId": eventId, "timeSlotId": slot.slotId, "timeSlotIndex": slot.index, "concerningInstProfileId": profileId,
        ])
    }

    func cancelBooking(eventId: Int, slot: MeetingSlot, for profileId: Int) async throws {
        let _: Ignored = try await call("calendar.removeBlockingOrResponseToTimeSlot", body: [
            "eventId": eventId, "timeSlotId": slot.slotId, "timeSlotIndex": slot.index, "concerningInstitutionProfileId": profileId,
        ])
    }
}

/// Reads `timeSlot` from calendar.getEventById.
struct TimeSlotDTO: Decodable {
    struct Index: Decodable { let startTime: String?; let endTime: String? }
    struct Answer: Decodable {
        let concerningProfileId: FlexInt?
        let instProfileId: FlexInt?
        let selectedTimeSlotIndex: FlexInt?
    }
    struct Slot: Decodable {
        let id: FlexInt?
        let startDate: String?
        let endDate: String?
        let timeSlotIndexes: Lossy<Index>?
        let answers: Lossy<Answer>?
    }
    let timeSlots: Lossy<Slot>?

    private enum K: String, CodingKey { case timeSlots }
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: K.self)
        timeSlots = (try? c?.decodeIfPresent(Lossy<Slot>.self, forKey: .timeSlots)) ?? nil
    }

    var slots: [MeetingSlot] {
        (timeSlots?.items ?? []).flatMap { s -> [MeetingSlot] in
            guard let sid = s.id?.value else { return [] }
            let answers = s.answers?.items ?? []
            return (s.timeSlotIndexes?.items ?? []).enumerated().compactMap { i, x in
                guard let a = AulaDate.parse(x.startTime), let b = AulaDate.parse(x.endTime) else { return nil }
                let hit = answers.first { $0.selectedTimeSlotIndex?.value == i }
                let who = hit?.concerningProfileId?.value ?? hit?.instProfileId?.value
                return MeetingSlot(slotId: sid, index: i, start: a, end: b, bookedFor: who, blocked: hit != nil && who == nil)
            }
        }
        .sorted { $0.start < $1.start }
    }
}

private struct OwnerContextDTO: Decodable {
    struct Inst: Decodable { let institutionProfileId: FlexInt?; let institutionCode: FlexString?; let name: String? }
    let institutions: Lossy<Inst>?
}

private struct UploadCreatedDTO: Decodable {
    struct Media: Decodable {
        let id: FlexInt?
        let uploadId: String?
        let fileUploadInformation: [String: String]?
        enum CodingKeys: String, CodingKey { case id, uploadId, fileUploadInformation }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decodeIfPresent(FlexInt.self, forKey: .id)
            uploadId = try? c.decodeIfPresent(String.self, forKey: .uploadId)
            fileUploadInformation = (try? c.decodeIfPresent([String: FlexString].self, forKey: .fileUploadInformation))?.mapValues(\.value)
        }
    }
    let media: Lossy<Media>?
}

/// Accepts a bare id, {id: …} or nothing.
private struct CreatedId: Decodable {
    let id: Int?
    private enum K: String, CodingKey { case id, albumId }
    init(from decoder: Decoder) throws {
        if let v = try? FlexInt(from: decoder) { id = v.value; return }
        let c = try? decoder.container(keyedBy: K.self)
        id = (try? c?.decode(FlexInt.self, forKey: .id))?.value ?? (try? c?.decode(FlexInt.self, forKey: .albumId))?.value
    }
}

extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
