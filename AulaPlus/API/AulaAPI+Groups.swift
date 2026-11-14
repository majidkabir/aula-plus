import Foundation

/// A group in Aula (a "stue", a class, the whole institution …).
struct AulaGroup: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    var institutionCode: String? = nil
}

struct GroupMember: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let role: String?          // guardian, child, employee roles
    let detail: String?
    let pictureURL: URL?
}

/// One answer for one person in "Samtykker".
struct ConsentItem: Codable, Identifiable, Hashable {
    let id: Int               // consent id
    let profileId: Int        // institution profile id
    let profileName: String
    let text: String
    let allowed: [String]
    var answer: String?
    let editable: Bool
}

enum SearchKind: String, CaseIterable, Identifiable {
    case posts = "Post", people = "Profile", events = "Event", photos = "Media"
    var id: String { rawValue }
}

struct SearchHit: Identifiable, Hashable {
    let id: String
    let kind: SearchKind
    let title: String
    let detail: String?
    let date: Date?
    let pictureURL: URL?
    var postId: Int?
    var eventId: String?
    var media: Media?
    var contact: Contact?
}

extension AulaAPI {
    /// The groups I'm in, as aula.dk's "Mine grupper".
    func myGroups() async throws -> [AulaGroup] {
        let ctx: GroupsContextDTO = try await call("profiles.getProfileContext", query: [.init(name: "portalrole", value: "guardian")])
        var seen = Set<Int>()
        return (ctx.institutions?.items ?? []).flatMap { inst in
            (inst.groups?.items ?? []).compactMap { g -> AulaGroup? in
                guard let id = g.id?.value, seen.insert(id).inserted else { return nil }
                return AulaGroup(id: id, name: g.name ?? String(localized: "Gruppe"), institutionCode: inst.institutionCode)
            }
        }
    }

    func groupMembers(_ groupId: Int) async throws -> [GroupMember] {
        let dto: MembershipsDTO = try await call("groups.getMemberships", query: [.init(name: "groupId", value: String(groupId))])
        var seen = Set<Int>()
        return (dto.memberships?.items ?? []).compactMap { m in
            guard let p = m.institutionProfile, let id = p.id?.value, seen.insert(id).inserted else { return nil }
            let name = p.fullName ?? [p.firstName, p.lastName].compactMap { $0 }.joined(separator: " ")
            return GroupMember(id: id, name: name, role: m.institutionRole ?? p.role,
                               detail: p.metadata?.nilIfEmpty ?? p.mainGroupName?.nilIfEmpty,
                               pictureURL: p.profilePicture?.url.flatMap { URL(string: $0) })
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func groupPosts(_ groupId: Int, limit: Int = 20) async throws -> [Post] {
        let dto: PostsDTO = try await call("posts.getAllPosts", query: [
            .init(name: "parent", value: "group"), .init(name: "groupId", value: String(groupId)),
            .init(name: "index", value: "0"), .init(name: "limit", value: String(limit)),
        ])
        return dto.posts?.items.map(\.model) ?? []
    }

    func groupAlbums(_ groupId: Int) async throws -> [Album] {
        let dto: AlbumsDTO = try await call("gallery.getAlbums", query: [
            .init(name: "groupId", value: String(groupId)), .init(name: "index", value: "0"), .init(name: "limit", value: "40"),
            .init(name: "sortOn", value: "createdAt"), .init(name: "orderDirection", value: "desc"), .init(name: "filterBy", value: "all"),
        ])
        var seen = Set<Int>()
        return (dto.albums?.items ?? []).filter { seen.insert($0.id.value).inserted }.map { a in
            Album(id: a.id.value, title: a.title?.nilIfEmpty ?? String(localized: "Album"), date: AulaDate.parse(a.creationDate),
                  coverURL: a.thumbnailsUrls?.items.compactMap(\.url).first.flatMap { URL(string: $0) }, count: a.size ?? a.totalSize)
        }
    }

    func groupEvents(_ groupId: Int, from: Date, to: Date) async throws -> [Event] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AulaDate.copenhagen
        f.dateFormat = "yyyy-MM-dd'T'00:00:00.0000xxx"
        let start = f.string(from: from)
        f.dateFormat = "yyyy-MM-dd'T'23:59:59.9990xxx"
        let end = f.string(from: to)
        let list: Lossy<EventDTO> = try await call("calendar.geteventsbygroupid", query: [
            .init(name: "groupId", value: String(groupId)), .init(name: "start", value: start), .init(name: "end", value: end),
        ])
        var seen = Set<String>()
        return list.items.compactMap(\.model).filter { seen.insert($0.id).inserted }.sorted { $0.start < $1.start }
    }

    // MARK: Search

    func search(_ text: String, kind: SearchKind, guardianIds: [Int], childIds: [Int]) async throws -> [SearchHit] {
        var q: [URLQueryItem] = [
            .init(name: "limit", value: "30"), .init(name: "offset", value: "0"),
        ]
        q += guardianIds.map { .init(name: "institutionProfileIds[]", value: String($0)) }
        q += childIds.map { .init(name: "activeChildrenInstitutionProfileIds[]", value: String($0)) }
        q += [.init(name: "text", value: text), .init(name: "docType", value: kind.rawValue), .init(name: "docTypeCount", value: "true")]
        let dto: SearchDTO = try await call("search.findGeneric", query: q)
        switch kind {
        case .photos:
            return (dto.mediaResults?.items ?? []).map { m in
                let media = m.model
                return SearchHit(id: "m\(media.id)", kind: .photos, title: media.title ?? "", detail: nil, date: media.date,
                                 pictureURL: media.thumbURL, media: media)
            }
        default:
            return (dto.results?.items ?? []).compactMap { r in
                let id = r.docId?.value ?? r.id?.value ?? UUID().uuidString
                switch kind {
                case .posts:
                    return SearchHit(id: "p\(id)", kind: .posts, title: r.title?.nilIfEmpty ?? String(localized: "Opslag"),
                                     detail: HTML.plainText(r.content?.html ?? r.description ?? "").nilIfEmpty,
                                     date: AulaDate.parse(r.timestamp ?? r.publishAt), pictureURL: nil, postId: Int(id))
                case .events:
                    return SearchHit(id: "e\(id)", kind: .events, title: r.title?.nilIfEmpty ?? String(localized: "Begivenhed"),
                                     detail: r.location?.nilIfEmpty ?? r.creatorAulaName, date: AulaDate.parse(r.startDateTime),
                                     pictureURL: nil, eventId: id)
                default:
                    let name = r.name ?? r.title ?? ""
                    let contact = Contact(id: Int(id) ?? 0, name: name, detail: r.metadata?.nilIfEmpty, phones: [], email: nil,
                                          pictureURL: r.profilePicture?.url.flatMap { URL(string: $0) }, role: r.portalRole,
                                          institutionName: r.institutionName, group: r.mainGroup?.name)
                    return SearchHit(id: "c\(id)", kind: .people, title: name, detail: r.metadata?.nilIfEmpty ?? r.institutionName,
                                     date: nil, pictureURL: contact.pictureURL, contact: contact)
                }
            }
        }
    }

    // MARK: Consents ("Samtykker")

    func consents() async throws -> [ConsentItem] {
        let list: Lossy<ConsentProfileDTO> = try await call("consents.getConsentResponses")
        return list.items.flatMap { p -> [ConsentItem] in
            guard let pid = p.institutionProfile?.id?.value else { return [] }
            let name = p.institutionProfile?.fullName ?? ""
            return (p.consentResponses?.items ?? []).compactMap { c in
                guard let cid = c.consentId?.value else { return nil }
                return ConsentItem(id: cid, profileId: pid, profileName: name, text: c.consentDescription ?? "",
                                   allowed: c.allowedAnswers ?? [], answer: c.consentResponseAnswer, editable: c.editable ?? false)
            }
        }
    }

    func saveConsents(_ items: [ConsentItem]) async throws {
        let byProfile = Dictionary(grouping: items, by: \.profileId)
        let answers: [[String: Any]] = byProfile.map { pid, list in
            ["institutionProfileId": pid,
             "institutionProfileConsentUpdates": list.compactMap { c -> [String: Any]? in
                 guard let a = c.answer else { return nil }
                 return ["consentId": c.id, "answer": a, "fromDate": NSNull(), "toDate": NSNull()]
             }]
        }
        let _: Ignored = try await call("consents.updateConsentResponses", body: ["institutionProfilesConsentAnswers": answers])
    }
}

private struct GroupsContextDTO: Decodable {
    struct Group: Decodable { let id: FlexInt?; let name: String? }
    struct Inst: Decodable { let institutionCode: String?; let groups: Lossy<Group>? }
    let institutions: Lossy<Inst>?
}

private struct MembershipsDTO: Decodable {
    struct Pic: Decodable { let url: String? }
    struct Profile: Decodable {
        let id: FlexInt?; let fullName: String?; let firstName: String?; let lastName: String?
        let role: String?; let metadata: String?; let mainGroupName: String?; let profilePicture: Pic?
    }
    struct Membership: Decodable { let institutionRole: String?; let institutionProfile: Profile? }
    let memberships: Lossy<Membership>?
}

private struct SearchDTO: Decodable {
    struct Pic: Decodable { let url: String? }
    struct Group: Decodable { let name: String? }
    struct Result: Decodable {
        let id: FlexString?; let docId: FlexString?
        let title: String?; let description: String?; let content: HTMLField?
        let timestamp: String?; let publishAt: String?
        let startDateTime: String?; let location: String?; let creatorAulaName: String?
        let name: String?; let metadata: String?; let institutionName: String?; let portalRole: String?
        let mainGroup: Group?; let profilePicture: Pic?
    }
    let results: Lossy<Result>?
    let mediaResults: Lossy<MediaDTO>?
}

private struct ConsentProfileDTO: Decodable {
    struct Profile: Decodable { let id: FlexInt?; let fullName: String? }
    struct Response: Decodable {
        let consentId: FlexInt?; let consentDescription: String?; let allowedAnswers: [String]?
        let consentResponseAnswer: String?; let editable: Bool?
    }
    let institutionProfile: Profile?
    let consentResponses: Lossy<Response>?
}
