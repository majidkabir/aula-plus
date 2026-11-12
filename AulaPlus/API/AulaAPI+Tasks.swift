import Foundation

struct SchoolTask: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subject: String?
    let due: Date?
    let weekday: String?
    let childName: String
    let isDone: Bool
}

private struct MUTaskDTO: Decodable {
    struct Hold: Decodable { let fagNavn: String?; let navn: String? }
    let id: FlexString?
    let title: String?
    let opgaveType: String?
    let afleveringsdato: String?
    let ugedag: String?
    let erFaerdig: Bool?
    let kuvertnavn: String?
    let hold: Lossy<Hold>?
}

private struct MUTasksDTO: Decodable { let opgaver: Lossy<MUTaskDTO>? }

extension AulaAPI {
    static var muTaskWidgets: [String] { ["0030", AulaConfig.Widget.muSSO] }

    /// Min Uddannelse "opgaver" (homework/tasks) for the week.
    func schoolTasks(session s: Session, week: (year: Int, week: Int)) async throws -> [SchoolTask] {
        guard let widget = Self.muTaskWidgets.first(where: s.widgetIds.contains) else { return [] }
        let token = try await widgetToken(widget)
        var q: [URLQueryItem] = [
            .init(name: "placement", value: "narrow"),
            .init(name: "sessionUUID", value: s.guardianUserId ?? ""),
            .init(name: "userProfile", value: "guardian"),
            .init(name: "currentWeekNumber", value: "\(week.year)-W\(week.week)"),
            .init(name: "isMobileApp", value: "false"),
        ]
        q += s.children.compactMap(\.userId).map { .init(name: "childFilter[]", value: $0) }
        q += Set(s.children.compactMap(\.institutionCode)).map { .init(name: "institutionFilter[]", value: $0) }
        let dto: MUTasksDTO = try await external("\(AulaConfig.minUddannelseAPI)/opgaveliste", query: q,
                                                 headers: ["Authorization": token])
        return (dto.opgaver?.items ?? []).map { t in
            let subject: String? = t.hold?.items.compactMap { $0.fagNavn ?? $0.navn }.first
            return SchoolTask(id: t.id?.value ?? UUID().uuidString,
                              title: t.title?.nilIfEmpty ?? t.opgaveType ?? String(localized: "Opgave"),
                              subject: subject,
                              due: Self.parseDotNetDate(t.afleveringsdato),
                              weekday: t.ugedag?.nilIfEmpty,
                              childName: t.kuvertnavn ?? "",
                              isDone: t.erFaerdig ?? false)
        }
    }

    /// "/Date(1771196400000-0000)/" → Date
    static func parseDotNetDate(_ s: String?) -> Date? {
        guard let s, let r = s.range(of: #"\d{10,}"#, options: .regularExpression),
              let ms = Double(s[r]) else { return AulaDate.parse(s) }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
