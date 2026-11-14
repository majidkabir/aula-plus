import Foundation

struct Album: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let date: Date?
    let coverURL: URL?
    let count: Int?
    /// Set for a child's own album ("Billeder af …"): every photo the child is tagged in.
    var childId: Int? = nil

    /// The album with every photo `child` is tagged in. Negative id: never clashes with a real album.
    static func tagged(_ child: Child) -> Album {
        Album(id: -child.id, title: String(localized: "Billeder af \(child.firstName)"), date: nil,
              coverURL: nil, count: nil, childId: child.id)
    }
}

/// A person tagged in a photo (`id` is their institution profile id).
struct MediaTag: Codable, Hashable {
    let id: Int
    let name: String
}

struct Media: Codable, Identifiable, Hashable {
    let id: Int
    let thumbURL: URL?
    let fullURL: URL?
    let isVideo: Bool
    let title: String?
    var tags: [MediaTag]? = nil
    var description: String? = nil
    /// Aula's `currentUserCanEditTags`: whether this user may tag people in the photo.
    var canEditTags: Bool? = nil
    /// A mid-size version for finding faces (large/medium thumbnail, else the full photo).
    var scanURL: URL? = nil
    /// When the photo was put on Aula.
    var date: Date? = nil

    var tagList: [MediaTag] { tags ?? [] }
    func isTagged(_ childId: Int) -> Bool { tagList.contains { $0.id == childId } }
}

struct AulaNotification: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let module: String?
    let childName: String?
    let date: Date?
    let postId: Int?
    let threadId: String?
    let albumId: Int?
    var eventType: String? = nil
    /// Raw `notificationId` + owner profile: what `deleteNotifications` needs.
    var notificationId: String? = nil
    var institutionProfileId: Int? = nil
    var mediaId: Int? = nil
    var relatedChildId: Int? = nil

    var isGallery: Bool {
        (module ?? "").lowercased() == "gallery"
            || ["NewMedia", "MediaAddedToAlbum", "TaggedInMedia", "AlbumShared"].contains(eventType ?? "")
    }
    var isTaggedInMedia: Bool { eventType == "TaggedInMedia" }
    /// A new photo in an album (not a tag).
    var isNewMedia: Bool { eventType == "NewMedia" || eventType == "MediaAddedToAlbum" }

    /// `TaggedInMedia` carries no mediaId; Aula's web app reads it from the notificationId
    /// (`<area>:<x>-<mediaId>…`). Same rule here.
    static func mediaId(fromNotificationId id: String?) -> Int? {
        guard let id, let part = id.split(separator: ":").dropFirst().first else { return nil }
        let pieces = part.split(separator: "-")
        guard pieces.count > 1 else { return nil }
        return Int(pieces[1])
    }
}

struct Comment: Codable, Identifiable, Hashable {
    let id: Int
    let author: String
    let html: String
    let date: Date?
}

struct ImportantDate: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let allDay: Bool
}

private struct AlbumDTO: Decodable {
    struct Thumb: Decodable { let url: String? ; init(from d: Decoder) throws {
        if let s = try? d.singleValueContainer().decode(String.self) { url = s; return }
        struct U: Decodable { let url: String? }
        url = (try? U(from: d))?.url
    } }
    let id: FlexInt
    let title: String?
    let creationDate: String?
    let thumbnailsUrls: Lossy<Thumb>?
    let size: Int?
    let totalSize: Int?
}

private struct AlbumsDTO: Decodable {
    let albums: Lossy<AlbumDTO>?
    init(from decoder: Decoder) throws {
        if let list = try? Lossy<AlbumDTO>(from: decoder) { albums = list; return }
        struct Wrapped: Decodable { let albums: Lossy<AlbumDTO>? }
        albums = try Wrapped(from: decoder).albums
    }
}

struct MediaDTO: Decodable {
    struct File: Decodable { let url: String?; let created: String? }
    struct Tag: Decodable {
        struct Profile: Decodable { let name: String?; let fullName: String? }
        let id: FlexInt?
        let institutionProfileId: FlexInt?
        let name: String?
        let fullName: String?
        let profile: Profile?
    }
    let id: FlexInt
    let tags: Lossy<Tag>?
    let description: String?
    let currentUserCanEditTags: Bool?
    let title: String?
    let mediaType: String?
    let file: File?
    let thumbnailUrl: String?
    let smallThumbnailUrl: String?
    let mediumThumbnailUrl: String?
    let largeThumbnailUrl: String?
}

private struct MediaListDTO: Decodable {
    let results: Lossy<MediaDTO>?
    let total: Int?
    init(from decoder: Decoder) throws {
        if let list = try? Lossy<MediaDTO>(from: decoder) { results = list; total = nil; return }
        struct Wrapped: Decodable { let results: Lossy<MediaDTO>?; let mediaCount: Int?; let totalSize: Int? }
        let w = try Wrapped(from: decoder)
        results = w.results
        total = w.mediaCount ?? w.totalSize
    }
}

private struct NotificationDTO: Decodable {
    let id: FlexString?
    let notificationId: FlexString?
    let notificationEventType: String?
    let title: String?
    let heading: String?
    let postTitle: String?
    let messageText: String?
    let threadSubject: String?
    let module: String?
    let notificationArea: String?
    let relatedChildName: String?
    let createdAt: String?
    let triggered: String?
    let postId: FlexInt?
    let threadId: FlexString?
    let albumId: FlexInt?
    let mediaId: FlexInt?
    let institutionProfileId: FlexInt?
    let relatedChildInstitutionProfileId: FlexInt?
}

private struct CommentDTO: Decodable {
    struct Owner: Decodable { let name: String? }
    let id: FlexInt
    let text: HTMLField?
    let creatorName: String?
    let owner: Owner?
    let createdAt: String?
}

private struct CommentsDTO: Decodable {
    let comments: Lossy<CommentDTO>?
    init(from decoder: Decoder) throws {
        if let list = try? Lossy<CommentDTO>(from: decoder) { comments = list; return }
        struct Wrapped: Decodable { let comments: Lossy<CommentDTO>? }
        comments = try Wrapped(from: decoder).comments
    }
}

private struct ImportantDateDTO: Decodable {
    let id: FlexString?
    let title: String?
    let startDateTime: String?
    let startDate: String?
    let allDay: Bool?
}

extension AulaAPI {
    func albums(institutionProfileIds: [Int], index: Int = 0, limit: Int = 30) async throws -> [Album] {
        var q: [URLQueryItem] = [
            .init(name: "index", value: String(index)),
            .init(name: "limit", value: String(limit)),
            .init(name: "sortOn", value: "createdAt"),
            .init(name: "orderDirection", value: "desc"),
            .init(name: "filterBy", value: "all"),
        ]
        q += institutionProfileIds.map { .init(name: "filterInstProfileIds[]", value: String($0)) }
        let dto: AlbumsDTO = try await call("gallery.getAlbums", query: q)
        var seenAlbums = Set<Int>()
        let albums = (dto.albums?.items ?? []).filter { seenAlbums.insert($0.id.value).inserted }
        return albums.map { a in
            let cover: String? = a.thumbnailsUrls?.items.compactMap(\.url).first
            return Album(id: a.id.value, title: a.title?.nilIfEmpty ?? String(localized: "Album"),
                         date: AulaDate.parse(a.creationDate),
                         coverURL: cover.flatMap { URL(string: $0) },
                         count: a.size ?? a.totalSize)
        }
    }

    typealias MediaProgress = @MainActor ([Media], Int?) -> Void

    /// All photos in an album, newest first. A small first page comes back fast; `progress`
    /// gets the list so far after every page so the screen can show it straight away.
    func media(albumId: Int, institutionProfileIds: [Int], progress: MediaProgress? = nil) async throws -> [Media] {
        try await pages(progress: progress) { index, limit in
            var q: [URLQueryItem] = [
                .init(name: "albumId", value: String(albumId)),
                .init(name: "index", value: String(index)),
                .init(name: "limit", value: String(limit)),
                .init(name: "sortOn", value: "uploadedAt"),
                .init(name: "orderDirection", value: "desc"),
                .init(name: "filterBy", value: "all"),
            ]
            q += institutionProfileIds.map { .init(name: "filterInstProfileIds[]", value: String($0)) }
            return q
        }
    }

    /// Fetches `gallery.getMedia` page by page: 48 first, then 150 at a time.
    /// `totalSize` is unreliable, so it stops on a short or repeated page.
    private func pages(progress: MediaProgress?, query: (_ index: Int, _ limit: Int) -> [URLQueryItem]) async throws -> [Media] {
        var all: [Media] = []
        var seen = Set<Int>()
        var index = 0
        for page in 0..<60 {
            try Task.checkCancellation()
            let limit = page == 0 ? 48 : 150
            let dto: MediaListDTO = try await call("gallery.getMedia", query: query(index, limit))
            let raw = dto.results?.items ?? []
            let fresh = Self.uniqueMedia(raw).filter { seen.insert($0.id).inserted }
            all += fresh
            if raw.count < limit || fresh.isEmpty { break }
            index += raw.count
            if let progress { await progress(all, dto.total) }
        }
        return all
    }

    /// Every photo `childId` is tagged in, across all albums. Asks Aula for the child's own album
    /// (`userSpecificAlbum`); if that fails or comes back empty, looks through the albums instead.
    func taggedMedia(childId: Int, institutionProfileIds: [Int], progress: MediaProgress? = nil) async throws -> [Media] {
        var firstError: Error?
        do {
            let list = try await userSpecificMedia(childId: childId, progress: progress)
            if !list.isEmpty { return list }
        } catch {
            firstError = error
        }
        let scanned = try await scanAlbums(for: childId, institutionProfileIds: institutionProfileIds, progress: progress)
        if scanned.isEmpty, let firstError { throw firstError }
        return scanned
    }

    private func userSpecificMedia(childId: Int, progress: MediaProgress?) async throws -> [Media] {
        let keep: ([Media]) -> [Media] = { $0.filter { $0.isTagged(childId) || $0.tagList.isEmpty } }
        let wrapped: MediaProgress? = progress.map { p in { @MainActor list, total in p(keep(list), total) } }
        let all = try await pages(progress: wrapped) { index, limit in [
            .init(name: "userSpecificAlbum", value: "true"),
            .init(name: "filterInstProfileIds[]", value: String(childId)),
            .init(name: "index", value: String(index)),
            .init(name: "limit", value: String(limit)),
            .init(name: "filterBy", value: "all"),
        ] }
        return keep(all)
    }

    /// Photos tagged with `childId` in the newest albums, newest album first.
    private func scanAlbums(for childId: Int, institutionProfileIds: [Int], progress: MediaProgress?) async throws -> [Media] {
        let list = try await albums(institutionProfileIds: institutionProfileIds)
        func merged(_ found: [(Int, [Media])]) -> [Media] {
            var seen = Set<Int>()
            return found.sorted { $0.0 < $1.0 }.flatMap(\.1).filter { seen.insert($0.id).inserted }
        }
        // At most 3 albums at a time, so an album the user opens isn't stuck behind the scan.
        return await withTaskGroup(of: (Int, [Media]).self) { group in
            var next = 0
            func add() {
                guard next < list.count else { return }
                let (i, album) = (next, list[next])
                next += 1
                group.addTask {
                    let media = (try? await self.media(albumId: album.id, institutionProfileIds: institutionProfileIds)) ?? []
                    return (i, media.filter { $0.isTagged(childId) })
                }
            }
            for _ in 0..<3 { add() }
            var out: [(Int, [Media])] = []
            for await r in group {
                out.append(r)
                add()
                if let progress { await progress(merged(out), nil) }
            }
            return merged(out)
        }
    }

    private static func uniqueMedia(_ items: [MediaDTO]) -> [Media] {
        // Aula lists a photo once per child it's shared with; show each photo once.
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id.value).inserted }.map(\.model)
    }

    /// `childIds`/`institutionCodes` matter: without them Aula leaves out tag and child notifications.
    func notifications(childIds: [Int] = [], institutionCodes: [String] = [], limit: Int = 50) async throws -> [AulaNotification] {
        var q: [URLQueryItem] = [
            .init(name: "offset", value: "0"),
            .init(name: "limit", value: String(limit)),
        ]
        q += childIds.map { .init(name: "activeChildrenIds[]", value: String($0)) }
        q += institutionCodes.map { .init(name: "activeInstitutionCodes[]", value: $0) }
        let list: Lossy<NotificationDTO> = try await call("notifications.getNotificationsForActiveProfile", query: q)
        return list.items.map { n in
            let titles: [String?] = [n.title, n.heading, n.postTitle, n.threadSubject,
                                     n.messageText.map { HTML.plainText($0) }, Self.galleryTitle(n.notificationEventType),
                                     n.notificationEventType]
            let title: String = titles.compactMap { $0?.nilIfEmpty }.first ?? String(localized: "Notifikation")
            let id: String = (n.id ?? n.notificationId)?.value ?? UUID().uuidString
            let rawId = n.notificationId?.value.nilIfEmpty
            let mediaId = n.mediaId?.value
                ?? (n.notificationEventType == "TaggedInMedia" ? AulaNotification.mediaId(fromNotificationId: rawId) : nil)
            return AulaNotification(id: id, title: title,
                                    module: n.module ?? n.notificationArea,
                                    childName: n.relatedChildName?.nilIfEmpty,
                                    date: AulaDate.parse(n.createdAt ?? n.triggered),
                                    postId: n.postId?.value,
                                    threadId: n.threadId?.value.nilIfEmpty,
                                    albumId: n.albumId?.value,
                                    eventType: n.notificationEventType,
                                    notificationId: rawId,
                                    institutionProfileId: n.institutionProfileId?.value,
                                    mediaId: mediaId,
                                    relatedChildId: n.relatedChildInstitutionProfileId?.value)
        }
    }

    private static func galleryTitle(_ type: String?) -> String? {
        switch type {
        case "NewMedia", "MediaAddedToAlbum": return String(localized: "Nye billeder i galleriet")
        case "TaggedInMedia": return String(localized: "Dit barn er tagget på et billede")
        case "AlbumShared": return String(localized: "Nyt album delt")
        default: return nil
        }
    }

    /// Replaces the people tagged in a photo, exactly like Aula's web app:
    /// `files.updateAttachments` with the photo's full tag list (institution profile ids).
    func setTag(_ profileId: Int, on media: Media, tagged: Bool, allTagIds: [Int]) async throws {
        var item: [String: Any] = ["id": media.id, "tags": allTagIds]
        item["title"] = media.title ?? NSNull()
        item["description"] = media.description ?? NSNull()
        let _: Ignored = try await call("files.updateAttachments", body: ["media": [item]])
    }

    /// Saves ("Gem") or unsaves a post, like aula.dk.
    func setBookmarked(postId: Int, _ on: Bool) async throws {
        let _: Ignored = try await call(on ? "posts.bookmark" : "posts.unbookmark", body: ["postId": postId])
    }

    /// Birthdays of children at the given institutions in the next `days` days.
    func birthdays(institutionCodes: [String], days: Int = 14) async throws -> [Birthday] {
        guard !institutionCodes.isEmpty else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: days, to: start)!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        var q: [URLQueryItem] = [
            .init(name: "start", value: f.string(from: start) + "T00:00:00.0000Z"),
            .init(name: "end", value: f.string(from: end) + "T23:59:59.0000Z"),
        ]
        q += institutionCodes.map { .init(name: "instCodes[]", value: $0) }
        let list: Lossy<BirthdayDTO> = try await call("calendar.getBirthdayEventsForInstitutions", query: q)
        var seen = Set<Int>()
        return list.items.compactMap { b -> Birthday? in
            guard let id = b.institutionProfileId?.value, seen.insert(id).inserted,
                  let born = b.birthday.flatMap(AulaDate.parse) else { return nil }
            // Aula returns the birth date (midnight UTC); show the coming birthday.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            var parts = utc.dateComponents([.month, .day], from: born)
            parts.year = cal.component(.year, from: start)
            guard var next = cal.date(from: parts) else { return nil }
            if next < start { next = cal.date(byAdding: .year, value: 1, to: next) ?? next }
            guard next <= end else { return nil }
            return Birthday(id: id, name: b.name ?? "", date: next, group: b.mainGroupName?.nilIfEmpty,
                            institutionCode: b.institutionCode)
        }
        .sorted { $0.date < $1.date }
    }

    /// Marks notifications as seen on Aula (it deletes them, like the web app does).
    /// A notification without an owner profile is sent once per guardian profile.
    func deleteNotifications(_ list: [AulaNotification], fallbackOwners: [Int] = []) async throws {
        var items: [[String: Any]] = []
        for n in list {
            guard let id = n.notificationId ?? Optional(n.id) else { continue }
            let owners = n.institutionProfileId.map { [$0] } ?? fallbackOwners
            for owner in owners { items.append(["notificationId": id, "institutionProfileId": owner]) }
        }
        guard !items.isEmpty else { return }
        let _: Ignored = try await call("Notifications.deleteNotifications", body: ["notifications": items])
    }

    func comments(postId: Int) async throws -> [Comment] {
        let dto: CommentsDTO = try await call("comments.getComments", query: [
            .init(name: "ParentType", value: "Post"),
            .init(name: "ParentId", value: String(postId)),
            .init(name: "Limit", value: "100"),
        ])
        return (dto.comments?.items ?? []).map { c in
            Comment(id: c.id.value, author: c.owner?.name ?? c.creatorName ?? "",
                    html: c.text?.html ?? "", date: AulaDate.parse(c.createdAt))
        }
    }

    func importantDates(limit: Int = 10) async throws -> [ImportantDate] {
        let list: Lossy<ImportantDateDTO> = try await call("calendar.getImportantDates", query: [
            .init(name: "limit", value: String(limit)),
            .init(name: "includeToday", value: "true"),
        ])
        return list.items.compactMap { d in
            guard let start = AulaDate.parse(d.startDateTime ?? d.startDate) else { return nil }
            return ImportantDate(id: d.id?.value ?? UUID().uuidString, title: d.title?.nilIfEmpty ?? String(localized: "Begivenhed"),
                                 start: start, allDay: d.allDay ?? false)
        }
    }
}

extension AulaAPI {
    func post(id: Int) async throws -> Post {
        let dto: PostDTO = try await call("posts.getById", query: [.init(name: "id", value: String(id))])
        return dto.model
    }
}

extension MediaDTO {
    var model: Media {
        let m = self
        // Small first: grids show hundreds of these, the viewer uses `fullURL`.
        let thumbs: [String?] = [m.smallThumbnailUrl, m.thumbnailUrl, m.mediumThumbnailUrl, m.largeThumbnailUrl, m.file?.url]
        let fulls: [String?] = [m.file?.url, m.largeThumbnailUrl, m.mediumThumbnailUrl]
        let thumb: String? = thumbs.compactMap { $0 }.first
        let full: String? = fulls.compactMap { $0 }.first
        var tagIds = Set<Int>()
        let tags: [MediaTag] = (m.tags?.items ?? []).compactMap { t in
            guard let id = (t.id ?? t.institutionProfileId)?.value, tagIds.insert(id).inserted else { return nil }
            let names: [String?] = [t.name, t.fullName, t.profile?.name, t.profile?.fullName]
            guard let name = names.compactMap({ $0?.nilIfEmpty }).first else { return nil }
            return MediaTag(id: id, name: name)
        }
        return Media(id: m.id.value,
                     thumbURL: thumb.flatMap { URL(string: $0) },
                     fullURL: full.flatMap { URL(string: $0) },
                     isVideo: (m.mediaType ?? "").lowercased().contains("video"),
                     title: m.title?.nilIfEmpty,
                     tags: tags,
                     description: m.description,
                     canEditTags: m.currentUserCanEditTags,
                     scanURL: ([m.largeThumbnailUrl, m.mediumThumbnailUrl, m.file?.url] as [String?])
                         .compactMap { $0 }.first.flatMap { URL(string: $0) },
                     date: AulaDate.parse(m.file?.created))
    }
}

struct BirthdayDTO: Decodable {
    let institutionProfileId: FlexInt?
    let birthday: String?
    let name: String?
    let mainGroupName: String?
    let institutionCode: String?
}
