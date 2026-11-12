import Foundation

struct Album: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let date: Date?
    let coverURL: URL?
    let count: Int?
}

struct Media: Codable, Identifiable, Hashable {
    let id: Int
    let thumbURL: URL?
    let fullURL: URL?
    let isVideo: Bool
    let title: String?
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

private struct MediaDTO: Decodable {
    struct File: Decodable { let url: String? }
    let id: FlexInt
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
    init(from decoder: Decoder) throws {
        if let list = try? Lossy<MediaDTO>(from: decoder) { results = list; return }
        struct Wrapped: Decodable { let results: Lossy<MediaDTO>? }
        results = try Wrapped(from: decoder).results
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
        return (dto.albums?.items ?? []).map { a in
            let cover: String? = a.thumbnailsUrls?.items.compactMap(\.url).first
            return Album(id: a.id.value, title: a.title?.nilIfEmpty ?? String(localized: "Album"),
                         date: AulaDate.parse(a.creationDate),
                         coverURL: cover.flatMap { URL(string: $0) },
                         count: a.size ?? a.totalSize)
        }
    }

    func media(albumId: Int, institutionProfileIds: [Int]) async throws -> [Media] {
        var q: [URLQueryItem] = [
            .init(name: "albumId", value: String(albumId)),
            .init(name: "index", value: "0"),
            .init(name: "limit", value: "500"),
            .init(name: "sortOn", value: "uploadedAt"),
            .init(name: "orderDirection", value: "desc"),
            .init(name: "filterBy", value: "all"),
        ]
        q += institutionProfileIds.map { .init(name: "filterInstProfileIds[]", value: String($0)) }
        let dto: MediaListDTO = try await call("gallery.getMedia", query: q)
        return (dto.results?.items ?? []).map { m in
            let thumbs: [String?] = [m.mediumThumbnailUrl, m.thumbnailUrl, m.smallThumbnailUrl, m.largeThumbnailUrl, m.file?.url]
            let fulls: [String?] = [m.file?.url, m.largeThumbnailUrl, m.mediumThumbnailUrl]
            let thumb: String? = thumbs.compactMap { $0 }.first
            let full: String? = fulls.compactMap { $0 }.first
            return Media(id: m.id.value,
                         thumbURL: thumb.flatMap { URL(string: $0) },
                         fullURL: full.flatMap { URL(string: $0) },
                         isVideo: (m.mediaType ?? "").lowercased().contains("video"),
                         title: m.title?.nilIfEmpty)
        }
    }

    func notifications(limit: Int = 50) async throws -> [AulaNotification] {
        let list: Lossy<NotificationDTO> = try await call("notifications.getNotificationsForActiveProfile", query: [
            .init(name: "offset", value: "0"),
            .init(name: "limit", value: String(limit)),
        ])
        return list.items.map { n in
            let titles: [String?] = [n.title, n.heading, n.postTitle, n.threadSubject,
                                     n.messageText.map { HTML.plainText($0) }, n.notificationEventType]
            let title: String = titles.compactMap { $0?.nilIfEmpty }.first ?? String(localized: "Notifikation")
            let id: String = (n.id ?? n.notificationId)?.value ?? UUID().uuidString
            return AulaNotification(id: id, title: title,
                                    module: n.module ?? n.notificationArea,
                                    childName: n.relatedChildName?.nilIfEmpty,
                                    date: AulaDate.parse(n.createdAt ?? n.triggered),
                                    postId: n.postId?.value,
                                    threadId: n.threadId?.value.nilIfEmpty,
                                    albumId: n.albumId?.value)
        }
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
