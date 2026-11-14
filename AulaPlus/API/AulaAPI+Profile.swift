import Foundation

/// One of my own institution profiles, with the contact info Aula has for it.
struct MyProfile: Codable, Identifiable, Hashable {
    let id: Int                // institution profile id
    let profileId: Int?
    let name: String
    let institutionName: String?
    let institutionCode: String?
    var email: String
    var mobilePhone: String
    var homePhone: String
    var workPhone: String
    let pictureURL: URL?
    let canEditPicture: Bool
}

/// Someone who may pick up a child: the child's own family (from Aula) or a name the parents added.
struct PickupPerson: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let relation: String?
    /// Set for names the parents added (they can be removed again).
    let suggestionId: Int?
}

/// Opening hours for one day at one institution.
struct OpeningDay: Codable, Identifiable, Hashable {
    let institutionCode: String
    let date: Date
    let open: String?
    let close: String?
    let isClosed: Bool
    let isSpecial: Bool
    let name: String?
    var id: String { "\(institutionCode)-\(date.timeIntervalSince1970)" }
}

struct ClosedDays: Codable, Identifiable, Hashable {
    let institutionCode: String
    let start: Date
    let end: Date
    let name: String
    var id: String { "\(institutionCode)-\(start.timeIntervalSince1970)-\(name)" }
}

extension AulaAPI {
    // MARK: My profile

    func myProfiles(institutionProfileIds: [Int]) async throws -> [MyProfile] {
        let q = institutionProfileIds.map { URLQueryItem(name: "instProfileIds[]", value: String($0)) }
        let dto: MasterDataDTO = try await call("profiles.getProfileMasterData", query: q)
        return (dto.institutionProfiles?.items ?? []).compactMap { p in
            guard let id = p.id?.value ?? p.institutionProfileId?.value else { return nil }
            let name = p.fullName ?? p.name ?? [p.firstName, p.lastName].compactMap { $0 }.joined(separator: " ")
            let pic = p.profilePicture?.url ?? p.profilePictureUrl
            return MyProfile(id: id, profileId: p.profileId?.value, name: name,
                             institutionName: p.institutionName ?? p.institution?.institutionName,
                             institutionCode: p.institutionCode ?? p.institution?.institutionCode,
                             email: p.email ?? "", mobilePhone: p.mobilePhoneNumber ?? "",
                             homePhone: p.homePhoneNumber ?? "", workPhone: p.workPhoneNumber ?? "",
                             pictureURL: pic.flatMap { URL(string: $0) },
                             canEditPicture: p.currentUserCanEditProfilePicture ?? true)
        }
    }

    /// Saves phone numbers and e-mail, like "Rediger" on aula.dk's profile page.
    func saveContactInfo(_ profiles: [MyProfile]) async throws {
        let items: [[String: Any]] = profiles.map { p in
            var d: [String: Any] = [
                "institutionProfileId": p.id,
                "homePhoneNumber": p.homePhone,
                "mobilePhoneNumber": p.mobilePhone,
                "workPhoneNumber": p.workPhone,
                "email": p.email,
            ]
            d["profileId"] = p.profileId.map { $0 as Any } ?? NSNull()
            return d
        }
        let _: Ignored = try await call("profiles.updateProfileMasterData", body: [
            "institutionProfilesMasterData": items,
            "primaryInstitutionProfileId": NSNull(),
            "isChangedPrimaryInstProfile": false,
        ])
    }

    /// Uploads a new profile picture: Aula hands out an upload form for its storage, then links the photo.
    func uploadProfilePicture(_ jpeg: Data, for profile: MyProfile, allProfiles: Bool) async throws {
        let uploadId = UUID().uuidString.lowercased()
        let created: CreatedAttachmentsDTO = try await call("files.createAttachments", body: [
            "media": [[
                "file": [String: Any](),
                "name": "profilbillede.jpg",
                "mediaType": "image",
                "rotationDegree": 0,
                "title": NSNull(),
                "description": NSNull(),
                "tags": [profile.id],
                "albumId": NSNull(),
                "sensitivityLevel": NSNull(),
                "allowsComments": true,
                "uploadId": uploadId,
            ] as [String: Any]],
            "files": [Any](),
            "links": [Any](),
            "existingMedia": [Any](),
            "attachedSecureDocumentIds": NSNull(),
            "ownerInstitutionProfileId": profile.id,
            "institutionCode": profile.institutionCode.map { $0 as Any } ?? NSNull(),
        ])
        guard let media = created.media?.items.first(where: { $0.uploadId == uploadId }) ?? created.media?.items.first,
              let mediaId = media.id?.value, let form = media.fileUploadInformation,
              let action = form["action"], let url = URL(string: action) else {
            throw AulaError.decoding("files.createAttachments")
        }
        // A plain form upload to Aula's storage, like the browser does.
        let boundary = "AulaPlus-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        for (k, v) in form where k != "action" { field(k.replacingOccurrences(of: "_", with: "-"), v) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"profilbillede.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.upload(for: req, from: body)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AulaError.http(status) }
        let _: Ignored = try await call("profiles.updateProfilePicture", body: [
            "institutionProfileId": profile.id,
            "mediaId": mediaId,
            "applyToAllInstitutionProfiles": allProfiles,
        ])
    }

    // MARK: Who may pick up

    func pickupPeople(childId: Int) async throws -> [PickupPerson] {
        let list: Lossy<PickupFullDTO> = try await call("presence.getPickupResponsibles",
                                                        query: [.init(name: "uniStudentIds[]", value: String(childId))])
        var out: [PickupPerson] = []
        for item in list.items where item.uniStudentId?.value == childId || item.uniStudentId == nil {
            for p in item.relatedPersons?.items ?? [] {
                guard let n = p.name?.nilIfEmpty else { continue }
                out.append(PickupPerson(id: "r-\(p.institutionProfileId?.value ?? n.hashValue)", name: n,
                                        relation: p.relation?.nilIfEmpty, suggestionId: nil))
            }
            for s in item.pickupSuggestions?.items ?? [] {
                guard let n = s.pickUpName?.nilIfEmpty else { continue }
                out.append(PickupPerson(id: "s-\(s.id?.value ?? n.hashValue)", name: n, relation: nil, suggestionId: s.id?.value))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    func addPickupPerson(_ name: String, childIds: [Int]) async throws {
        let _: Ignored = try await call("presence.savePickupNames", body: ["uniStudentIds": childIds, "pickupName": name])
    }

    func removePickupPerson(suggestionId: Int) async throws {
        let _: Ignored = try await call("presence.deletePickupResponsible", body: ["presencePickupSuggestionId": suggestionId])
    }

    // MARK: Opening hours and closed days

    func openingDays(institutionCodes: [String], from: Date, to: Date) async throws -> [OpeningDay] {
        var q: [URLQueryItem] = [
            .init(name: "startDate", value: Self.dayFormatter.string(from: from)),
            .init(name: "endDate", value: Self.dayFormatter.string(from: to)),
        ]
        q += institutionCodes.map { .init(name: "institutionCodes[]", value: $0) }
        let dto: OpeningHoursDTO = try await call("presence.getOpeningHoursByInstitutionCodes", query: q)
        return (dto.openingHoursOverviewDto?.items ?? []).flatMap { inst -> [OpeningDay] in
            guard let code = inst.institutionCode else { return [] }
            return (inst.openingHoursDto?.items ?? []).compactMap { d in
                guard let date = Self.parseDay(d.date) else { return nil }
                let type = (d.type ?? "").lowercased()
                return OpeningDay(institutionCode: code, date: date, open: AulaDate.shortTime(d.openTime),
                                  close: AulaDate.shortTime(d.closeTime), isClosed: type == "closed_day",
                                  isSpecial: type == "specific_opening_hours", name: d.name?.nilIfEmpty)
            }
        }
        .sorted { $0.date < $1.date }
    }

    func closedDays(institutionCodes: [String]) async throws -> [ClosedDays] {
        let q = institutionCodes.map { URLQueryItem(name: "institutionCodes[]", value: $0) }
        let list: Lossy<ClosedDaysDTO> = try await call("presence.getClosedDays", query: q)
        return list.items.flatMap { inst -> [ClosedDays] in
            guard let code = inst.institutionCode else { return [] }
            return (inst.closedDaysOverview?.closedDays?.items ?? []).compactMap { c in
                guard let s = Self.parseDay(c.startDate) else { return nil }
                return ClosedDays(institutionCode: code, start: s, end: Self.parseDay(c.endDate) ?? s,
                                  name: c.name?.nilIfEmpty ?? String(localized: "Lukket"))
            }
        }
        .sorted { $0.start < $1.start }
    }

    /// "2026-11-14", "14-11-2026" or a full timestamp.
    static func parseDay(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let head = String(s.prefix(10))
        if let d = dayFormatter.date(from: head) { return d }
        let parts = head.split(separator: "-")
        if parts.count == 3, parts[0].count == 2 { return dayFormatter.date(from: "\(parts[2])-\(parts[1])-\(parts[0])") }
        return AulaDate.parse(s).map { Calendar.week.startOfDay(for: $0) }
    }

    // MARK: Repeating plans

    /// Stops a weekly plan from the given day on (earlier weeks keep it).
    func deleteRepeatingPlan(templateId: Int, from day: Date) async throws {
        let _: Ignored = try await call("presence.deleteRepeatingPresenceTemplate", body: [
            "presentTemplateId": templateId,
            "deleteFromDay": Self.dayFormatter.string(from: day),
        ])
    }
}

private struct MasterDataDTO: Decodable {
    struct Pic: Decodable { let url: String? }
    struct Inst: Decodable { let institutionName: String?; let institutionCode: String? }
    struct Profile: Decodable {
        let id: FlexInt?
        let institutionProfileId: FlexInt?
        let profileId: FlexInt?
        let fullName: String?
        let name: String?
        let firstName: String?
        let lastName: String?
        let institutionName: String?
        let institutionCode: String?
        let institution: Inst?
        let email: String?
        let mobilePhoneNumber: String?
        let homePhoneNumber: String?
        let workPhoneNumber: String?
        let profilePicture: Pic?
        let profilePictureUrl: String?
        let currentUserCanEditProfilePicture: Bool?
    }
    let institutionProfiles: Lossy<Profile>?
}

private struct CreatedAttachmentsDTO: Decodable {
    struct Media: Decodable {
        let id: FlexInt?
        let uploadId: String?
        let fileUploadInformation: [String: String]?
        enum CodingKeys: String, CodingKey { case id, uploadId, fileUploadInformation }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decodeIfPresent(FlexInt.self, forKey: .id)
            uploadId = try? c.decodeIfPresent(String.self, forKey: .uploadId)
            // Values can be numbers too; keep everything as text for the form.
            if let raw = try? c.decodeIfPresent([String: FlexString].self, forKey: .fileUploadInformation) {
                fileUploadInformation = raw.mapValues(\.value)
            } else {
                fileUploadInformation = nil
            }
        }
    }
    let media: Lossy<Media>?
}

private struct PickupFullDTO: Decodable {
    struct Person: Decodable { let name: String?; let relation: String?; let institutionProfileId: FlexInt? }
    struct Suggestion: Decodable { let id: FlexInt?; let pickUpName: String? }
    let uniStudentId: FlexInt?
    let relatedPersons: Lossy<Person>?
    let pickupSuggestions: Lossy<Suggestion>?
}

private struct OpeningHoursDTO: Decodable {
    struct Day: Decodable { let date: String?; let type: String?; let openTime: String?; let closeTime: String?; let name: String? }
    struct Inst: Decodable { let institutionCode: String?; let openingHoursDto: Lossy<Day>? }
    let openingHoursOverviewDto: Lossy<Inst>?
}

private struct ClosedDaysDTO: Decodable {
    struct Day: Decodable { let startDate: String?; let endDate: String?; let name: String? }
    struct Overview: Decodable { let closedDays: Lossy<Day>? }
    let institutionCode: String?
    let closedDaysOverview: Overview?
}
