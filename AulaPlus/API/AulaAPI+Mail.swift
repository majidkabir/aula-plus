import Foundation

/// Folders, mute, leave, search and auto-reply: the same calls aula.dk makes.
extension AulaAPI {
    func folders() async throws -> [MailFolder] {
        let list: Lossy<FolderDTO> = try await call("messaging.getFolders", query: [
            .init(name: "includeDeletedFolders", value: "false"),
        ])
        return list.items.compactMap { f in
            guard let id = f.id?.value else { return nil }
            return MailFolder(id: id, name: f.name ?? "", type: f.type)
        }
    }

    func createFolder(name: String) async throws {
        let _: Ignored = try await call("messaging.createFolder", body: ["folderName": name, "commonInboxId": NSNull()])
    }

    func renameFolder(_ id: Int, to name: String) async throws {
        let _: Ignored = try await call("messaging.updateFolder", body: ["folderName": name, "folderId": id])
    }

    func deleteFolder(_ id: Int) async throws {
        let _: Ignored = try await call("messaging.deleteFolder", body: ["folderId": id])
    }

    /// `folderId` nil moves the thread back to the inbox.
    func moveThread(_ threadId: String, to folderId: Int?) async throws {
        let folder: Any = folderId.map { $0 as Any } ?? NSNull()
        let _: Ignored = try await call("messaging.moveThreadsToFolder", body: [
            "folderId": folder,
            "threadIds": [Int(threadId) ?? 0],
            "subscriptionIds": [Int](),
            "commonInboxId": NSNull(),
        ])
    }

    func setMuted(subscriptionId: Int, muted: Bool) async throws {
        let _: Ignored = try await call("messaging.setThreadsMuted", body: [
            "muted": muted,
            "subscriptionIds": [subscriptionId],
            "commonInboxId": NSNull(),
            "otpInboxId": NSNull(),
        ])
    }

    func leaveThread(_ threadId: String) async throws {
        let _: Ignored = try await call("messaging.leaveThread", body: [
            "threadId": Int(threadId) ?? 0,
            "otpInboxId": NSNull(),
        ])
    }

    /// Full-text search in all messages on Aula.
    func searchMessages(_ text: String, childIds: [Int], institutionCodes: [String]) async throws -> [ThreadSummary] {
        let dto: MessageSearchDTO = try await call("search.findMessage", body: [
            "text": text,
            "typeahead": false,
            "exactTerm": true,
            "activeChildrenInstitutionProfileIds": childIds,
            "institutionCodes": institutionCodes,
            "limit": 40,
            "offset": 0,
            "commonInboxID": NSNull(),
            "folderId": NSNull(),
            "filterBy": "all",
            "sortBy": "date",
            "sortDirection": "desc",
        ])
        var seen = Set<String>()
        return (dto.results?.items ?? []).compactMap { r -> ThreadSummary? in
            guard let id = (r.thread?.id ?? r.threadId)?.value, seen.insert(id).inserted else { return nil }
            return ThreadSummary(
                id: id,
                subject: r.thread?.subject?.nilIfEmpty ?? String(localized: "(Intet emne)"),
                preview: HTML.plainText(r.searchMessage?.text?.html ?? ""),
                sender: r.searchMessage?.senderDisplayName?.nilIfEmpty ?? r.creator?.fullName ?? "",
                date: AulaDate.parse(r.searchMessage?.sendDateTime),
                isRead: r.read ?? true,
                isSensitive: (r.sensitivityLevel ?? 1) > 1,
                regarding: (r.regardingChildren?.items ?? []).map(\.best).filter { !$0.isEmpty },
                isMarked: r.marked ?? false,
                isMuted: r.muted ?? false,
                subscriptionId: r.subscriptionId?.value,
                folderId: r.folderId?.value)
        }
    }

    func autoReply() async throws -> AutoReply? {
        // No auto-reply: Aula sends `data: null`, which decodes as an empty object.
        let dto: AutoReplyDTO = try await call("messaging.getAutoReply")
        guard let text = dto.replyText?.html ?? dto.replyText?.text else { return nil }
        return AutoReply(id: dto.id?.value, text: HTML.plainText(text),
                         start: AulaDate.parse(dto.startDateTime), end: AulaDate.parse(dto.endDateTime))
    }

    func setAutoReply(text: String, start: Date, end: Date?) async throws {
        let endValue: Any = end.map { Self.aulaDateTime($0) as Any } ?? NSNull()
        let _: Ignored = try await call("messaging.setAutoReply", body: [
            "replyText": text,
            "startDateTime": Self.aulaDateTime(start),
            "endDateTime": endValue,
        ])
    }

    func deleteAutoReply(id: Int) async throws {
        let _: Ignored = try await call("messaging.deleteAutoReply", body: ["autoReplyId": id])
    }

    /// "2026-11-14T08:00:00.0000+01:00", the format aula.dk sends.
    static func aulaDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AulaDate.copenhagen
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'.0000'xxx"
        return f.string(from: d)
    }
}

private struct FolderDTO: Decodable {
    let id: FlexInt?
    let name: String?
    let type: String?
}

private struct MessageSearchDTO: Decodable {
    struct Result: Decodable {
        struct Thread: Decodable { let id: FlexString?; let subject: String? }
        struct Msg: Decodable {
            let text: HTMLField?
            let sendDateTime: String?
            let senderDisplayName: String?
        }
        struct Creator: Decodable { let fullName: String? }
        let thread: Thread?
        let threadId: FlexString?
        let searchMessage: Msg?
        let creator: Creator?
        let read: Bool?
        let marked: Bool?
        let muted: Bool?
        let sensitivityLevel: Int?
        let subscriptionId: FlexInt?
        let folderId: FlexInt?
        let regardingChildren: Lossy<PersonDTO>?
    }
    let results: Lossy<Result>?
}

private struct AutoReplyDTO: Decodable {
    struct Text: Decodable {
        let html: String?
        let text: String?
        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) { html = s; text = s; return }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            html = try c.decodeIfPresent(String.self, forKey: .html)
            text = try c.decodeIfPresent(String.self, forKey: .text)
        }
        private enum CodingKeys: String, CodingKey { case html, text }
    }
    let id: FlexInt?
    let replyText: Text?
    let startDateTime: String?
    let endDateTime: String?
}
