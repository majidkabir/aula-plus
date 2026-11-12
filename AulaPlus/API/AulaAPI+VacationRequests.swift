import Foundation

/// The institution asking "is your child coming?" for a period (e.g. summer holiday).
struct VacationRequest: Codable, Identifiable, Hashable {
    let id: Int
    let responseId: Int
    let childId: Int
    let childName: String
    let title: String
    let start: Date
    let end: Date
    let deadline: Date?
    let note: String?
    let isEditable: Bool
    let isMissingAnswer: Bool
    let needsTimes: Bool
}

struct VacationDayAnswer: Hashable, Identifiable {
    let date: Date
    var isComing: Bool
    var entry: String
    var exit: String
    var id: Date { date }
}

private struct VacationGroupDTO: Decodable {
    struct Child: Decodable { let id: FlexInt?; let name: String? }
    struct Reg: Decodable {
        let vacationRegistrationId: FlexInt?
        let responseId: FlexInt?
        let title: String?
        let startDate: String?
        let endDate: String?
        let responseDeadline: String?
        let noteToGuardian: String?
        let isEditable: Bool?
        let isMissingAnswer: Bool?
        let isPresenceTimesRequired: Bool?
    }
    let child: Child?
    let vacationRegistrations: Lossy<Reg>?
}

extension AulaAPI {
    func vacationRequests(childIds: [Int]) async throws -> [VacationRequest] {
        let q = childIds.map { URLQueryItem(name: "childIds[]", value: String($0)) }
        let groups: Lossy<VacationGroupDTO> = try await call("presence.getVacationRegistrationsByChildren", query: q)
        var out: [VacationRequest] = []
        for g in groups.items {
            guard let cid = g.child?.id?.value else { continue }
            for r in g.vacationRegistrations?.items ?? [] {
                guard let id = r.vacationRegistrationId?.value, let rid = r.responseId?.value,
                      let start = AulaDate.parse(r.startDate), let end = AulaDate.parse(r.endDate) else { continue }
                out.append(VacationRequest(id: id, responseId: rid, childId: cid, childName: g.child?.name ?? "",
                                           title: r.title?.nilIfEmpty ?? String(localized: "Ferieanmodning"),
                                           start: start, end: end,
                                           deadline: AulaDate.parse(r.responseDeadline),
                                           note: r.noteToGuardian?.nilIfEmpty,
                                           isEditable: r.isEditable ?? true,
                                           isMissingAnswer: r.isMissingAnswer ?? false,
                                           needsTimes: r.isPresenceTimesRequired ?? false))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    func answerVacationRequest(_ req: VacationRequest, days: [VacationDayAnswer], comment: String) async throws {
        let dayList: [[String: Any]] = days.map { d in
            var item: [String: Any] = ["date": Self.dayFormatter.string(from: d.date), "isComing": d.isComing]
            item["entryTime"] = d.isComing && req.needsTimes ? d.entry : NSNull()
            item["exitTime"] = d.isComing && req.needsTimes ? d.exit : NSNull()
            return item
        }
        let _: Ignored = try await call("calendar.respondToVacationRegistrationRequest", body: [
            "childId": req.childId,
            "vacationRegistrationResponseId": req.responseId,
            "days": dayList,
            "comment": comment,
        ])
    }
}
