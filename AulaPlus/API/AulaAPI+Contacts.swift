import Foundation

struct AulaGroup: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct Contact: Codable, Identifiable, Hashable {
    let id: Int              // institution profile id (usable as message recipient)
    let name: String
    let detail: String?      // class, role, or the children they're related to
    let phones: [String]
    let email: String?
    let pictureURL: URL?
}

struct SecureDocument: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String?
    let isInternal: Bool
    let updated: Date?
    let creator: String?
}

struct DocumentContent: Codable, Hashable {
    let html: String
    let attachments: [Attachment]
}

struct CommonFile: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let institution: String?
    let date: Date?
    let attachment: Attachment?
}

private struct GroupsDTO: Decodable {
    struct G: Decodable { let id: FlexInt; let name: String? }
    struct Ctx: Decodable { let groups: Lossy<G>? }
    let groups: [G]
    init(from decoder: Decoder) throws {
        if let list = try? Lossy<Ctx>(from: decoder) {
            groups = list.items.flatMap { $0.groups?.items ?? [] }
        } else {
            groups = (try Ctx(from: decoder)).groups?.items ?? []
        }
    }
}

private struct ContactDTO: Decodable {
    struct Pic: Decodable { let url: String? }
    struct Relation: Decodable { let fullName: String?; let firstName: String?; let metadata: String? }
    let id: FlexInt?
    let institutionProfileId: FlexInt?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let metadata: String?
    let role: String?
    let email: String?
    let phone: String?
    let mobilePhoneNumber: String?
    let homePhoneNumber: String?
    let workPhoneNumber: String?
    let profilePicture: Pic?
    let profilePictureUrl: String?
    let relations: Lossy<Relation>?
}

private struct SecureDocsDTO: Decodable {
    struct Doc: Decodable {
        struct Creator: Decodable { let name: String? }
        let id: FlexInt
        let title: String?
        let category: String?
        let documentType: String?
        let updatedAt: String?
        let createdAt: String?
        let creator: Creator?
    }
    let documents: Lossy<Doc>?
}

private struct DocDetailDTO: Decodable {
    let content: HTMLField?
    let description: String?
    let attachments: Lossy<AttachmentDTO>?
    let attachment: AttachmentDTO?
}

private struct CommonFilesDTO: Decodable {
    struct F: Decodable {
        struct Inst: Decodable { let name: String? }
        struct Outer: Decodable { let name: String?; let file: AttachmentDTO.FileDTO? }
        let id: FlexString?
        let title: String?
        let created: String?
        let institution: Inst?
        let file: Outer?
    }
    let commonFiles: Lossy<F>?
}

extension AulaAPI {
    func groups(childIds: [Int]) async throws -> [AulaGroup] {
        let q = childIds.map { URLQueryItem(name: "childInstitutionProfileIds[]", value: String($0)) }
        let dto: GroupsDTO = try await call("groups.getGroupsByContext", query: q)
        var seen = Set<Int>()
        return dto.groups.compactMap { g in
            guard seen.insert(g.id.value).inserted else { return nil }
            return AulaGroup(id: g.id.value, name: g.name ?? String(localized: "Gruppe"))
        }
    }

    /// filter: "child", "guardian" or "employee". Reads all pages (20 per page).
    func contacts(groupId: Int, filter: String) async throws -> [Contact] {
        var all: [Contact] = []
        for page in 1...15 {
            let list: Lossy<ContactDTO> = try await call("profiles.getContactlist", query: [
                .init(name: "groupId", value: String(groupId)),
                .init(name: "filter", value: filter),
                .init(name: "field", value: "name"),
                .init(name: "page", value: String(page)),
                .init(name: "order", value: "asc"),
            ])
            let batch: [Contact] = list.items.compactMap { c in
                guard let id = (c.institutionProfileId ?? c.id)?.value else { return nil }
                let parts: [String] = [c.firstName, c.lastName].compactMap { $0 }
                let name: String = c.fullName ?? parts.joined(separator: " ")
                let related: [String] = (c.relations?.items ?? []).compactMap { $0.fullName ?? $0.firstName }
                let detailOptions: [String?] = [
                    related.isEmpty ? nil : related.joined(separator: ", "),
                    c.metadata?.nilIfEmpty, c.role?.nilIfEmpty,
                ]
                let phoneOptions: [String?] = [c.mobilePhoneNumber, c.phone, c.homePhoneNumber, c.workPhoneNumber]
                var phones: [String] = []
                for p in phoneOptions.compactMap({ $0?.nilIfEmpty }) where !phones.contains(p) { phones.append(p) }
                let pic: String? = c.profilePicture?.url ?? c.profilePictureUrl
                return Contact(id: id, name: name, detail: detailOptions.compactMap { $0 }.first,
                               phones: phones, email: c.email?.nilIfEmpty, pictureURL: pic.flatMap { URL(string: $0) })
            }
            all += batch
            if batch.count < 20 { break }
        }
        return all
    }

    func secureDocuments(guardianProfileIds: [Int]) async throws -> [SecureDocument] {
        var out: [SecureDocument] = []
        while out.count < 500 {
            let dto: SecureDocsDTO = try await call("documents.getSecureDocuments", body: [
                "index": out.count,
                "limit": 50,
                "filterInstitutionProfileIds": guardianProfileIds,
            ])
            let batch: [SecureDocument] = (dto.documents?.items ?? []).map { d in
                SecureDocument(id: d.id.value, title: d.title?.nilIfEmpty ?? String(localized: "Dokument"),
                               category: d.category?.nilIfEmpty,
                               isInternal: (d.documentType ?? "internal").lowercased().contains("internal"),
                               updated: AulaDate.parse(d.updatedAt ?? d.createdAt),
                               creator: d.creator?.name)
            }
            out += batch
            if batch.count < 50 { break }
        }
        return out
    }

    func documentContent(_ doc: SecureDocument) async throws -> DocumentContent {
        let method = doc.isInternal ? "documents.getInternalSecureDocument" : "documents.getExternalSecureFile"
        let d: DocDetailDTO = try await call(method, query: [.init(name: "documentId", value: String(doc.id))])
        var files: [Attachment] = d.attachments?.items.map(\.model) ?? []
        if let a = d.attachment { files.append(a.model) }
        return DocumentContent(html: d.content?.html ?? d.description ?? "", attachments: files)
    }

    func commonFiles(institutionCodes: [String]) async throws -> [CommonFile] {
        guard !institutionCodes.isEmpty else { return [] }
        var q: [URLQueryItem] = [
            .init(name: "index", value: "0"),
            .init(name: "limit", value: "100"),
        ]
        q += institutionCodes.map { .init(name: "institutionCodes[]", value: $0) }
        let dto: CommonFilesDTO = try await call("commonFiles.getCommonFiles", query: q)
        return (dto.commonFiles?.items ?? []).map { f in
            let url: URL? = f.file?.file?.url.flatMap { URL(string: $0) }
            let names: [String?] = [f.file?.name, f.file?.file?.name, f.title]
            let name: String = names.compactMap { $0?.nilIfEmpty }.first ?? String(localized: "Fil")
            return CommonFile(id: f.id?.value ?? UUID().uuidString,
                              title: f.title?.nilIfEmpty ?? name,
                              institution: f.institution?.name,
                              date: AulaDate.parse(f.created),
                              attachment: url.map { Attachment(name: name, url: $0) })
        }
    }
}
