import Foundation

/// How a child leaves at the end of the day (Aula ActivityType).
enum PickupKind: Int, Codable, CaseIterable, Identifiable {
    case pickedUpBy = 0, selfDecider = 1, sendHome = 2, goHomeWith = 3

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .pickedUpBy: return String(localized: "Hentes af")
        case .selfDecider: return String(localized: "Selvbestemmer")
        case .sendHome: return String(localized: "Sendes hjem")
        case .goHomeWith: return String(localized: "Går hjem med")
        }
    }
    var needsName: Bool { self == .pickedUpBy || self == .goHomeWith }
}

/// One day of a child's planned Komme/Gå times.
struct DayPlan: Codable, Hashable, Identifiable {
    let templateId: Int?
    let childId: Int
    let date: Date
    var entry: String?
    var exit: String?
    var kind: PickupKind?
    var exitWith: String?
    var comment: String?
    var isOnVacation: Bool
    var repeats: Bool

    var id: String { "\(childId)-\(date.timeIntervalSince1970)" }
}

/// What a guardian may change for a child (from the institution's settings).
struct PresencePermissions: Codable, Hashable {
    let childId: Int
    var canReportSick: Bool
    var canAddVacation: Bool
    var canEditPickup: Bool
}

private struct TemplatesDTO: Decodable {
    struct Week: Decodable {
        struct Inst: Decodable { let id: FlexInt? }
        let institutionProfile: Inst?
        let dayTemplates: Lossy<Day>?
    }
    struct Day: Decodable {
        let id: FlexInt?
        let byDate: String?
        let entryTime: String?
        let exitTime: String?
        let exitWith: String?
        let activityType: Int?
        let comment: String?
        let isOnVacation: Bool?
        let repeatPattern: String?
    }
    let presenceWeekTemplates: Lossy<Week>?
}

private struct ConfigItemDTO: Decodable {
    struct Module: Decodable { let moduleType: String?; let permission: String? }
    struct Setting: Decodable { let presenceDashboardContext: String?; let presenceModules: Lossy<Module>? }
    struct Config: Decodable { let dashboardModuleSettings: Lossy<Setting>? }
    let uniStudentId: FlexInt?
    let childId: FlexInt?
    let presenceConfiguration: Config?
}

private struct PickupDTO: Decodable {
    struct Person: Decodable { let name: String?; let relation: String? }
    struct Suggestion: Decodable { let pickUpName: String? }
    let uniStudentId: FlexInt?
    let relatedPersons: Lossy<Person>?
    let pickupSuggestions: Lossy<Suggestion>?
}

extension AulaAPI {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AulaDate.copenhagen
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Reports children sick for today, or takes the report back.
    func setSick(childIds: [Int], sick: Bool) async throws {
        let _: Ignored = try await call("presence.updateStatusByInstitutionProfileIds", body: [
            "institutionProfileIds": childIds,
            "status": sick ? PresenceStatus.sick.rawValue : PresenceStatus.notPresent.rawValue,
        ])
    }

    /// Registers ferie/fri for a date range.
    func addVacation(childIds: [Int], from: Date, to: Date, comment: String) async throws {
        let _: Ignored = try await call("calendar.addVacation", body: [
            "childIds": childIds,
            "intervals": [["startDate": Self.dayFormatter.string(from: from),
                           "endDate": Self.dayFormatter.string(from: to)]],
            "comment": String(comment.prefix(250)),
        ])
    }

    func dayPlans(childIds: [Int], from: Date, to: Date) async throws -> [DayPlan] {
        var q: [URLQueryItem] = [
            .init(name: "fromDate", value: Self.dayFormatter.string(from: from)),
            .init(name: "toDate", value: Self.dayFormatter.string(from: to)),
        ]
        q += childIds.map { .init(name: "filterInstitutionProfileIds[]", value: String($0)) }
        let dto: TemplatesDTO = try await call("presence.getPresenceTemplates", query: q)
        var out: [DayPlan] = []
        for week in dto.presenceWeekTemplates?.items ?? [] {
            guard let cid = week.institutionProfile?.id?.value else { continue }
            for d in week.dayTemplates?.items ?? [] {
                guard let date = AulaDate.parse(d.byDate) else { continue }
                out.append(DayPlan(templateId: d.id?.value, childId: cid, date: Calendar.week.startOfDay(for: date),
                                   entry: AulaDate.shortTime(d.entryTime), exit: AulaDate.shortTime(d.exitTime),
                                   kind: d.activityType.flatMap(PickupKind.init(rawValue:)),
                                   exitWith: d.exitWith?.nilIfEmpty, comment: d.comment?.nilIfEmpty,
                                   isOnVacation: d.isOnVacation ?? false,
                                   repeats: (d.repeatPattern ?? "never").lowercased() != "never"))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Creates or updates the planned times for one day, or every week from that day (`weekly`).
    func savePlan(_ plan: DayPlan, weekly: Bool = false) async throws {
        let entry = plan.entry ?? "08:00"
        let exit = plan.exit ?? "16:00"
        let kind = plan.kind ?? .pickedUpBy
        var activity: [String: Any] = ["activityType": kind.rawValue]
        switch kind {
        case .pickedUpBy:
            activity["pickup"] = ["entryTime": entry, "exitTime": exit, "exitWith": plan.exitWith ?? ""]
        case .goHomeWith:
            activity["goHomeWith"] = ["entryTime": entry, "exitTime": exit, "exitWith": plan.exitWith ?? ""]
        case .selfDecider:
            activity["selfDecider"] = ["entryTime": entry, "exitStartTime": exit, "exitEndTime": exit]
        case .sendHome:
            activity["sendHome"] = ["entryTime": entry, "exitTime": exit]
        }
        let comps = Calendar.week.dateComponents([.year, .month], from: plan.date)
        let endYear = (comps.month ?? 1) > 6 ? (comps.year ?? 2026) + 1 : (comps.year ?? 2026)
        var body: [String: Any] = [
            "institutionProfileId": plan.childId,
            "byDate": Self.dayFormatter.string(from: plan.date),
            "presenceActivity": activity,
            "comment": plan.comment ?? "",
            "repeatPattern": weekly ? "weekly" : "never",
            "expiresAt": "\(endYear)-06-30T00:00:00+00:00",
        ]
        if let id = plan.templateId, !plan.repeats || weekly { body["id"] = id }
        let _: Ignored = try await call("presence.updatePresenceTemplate", body: body)
    }

    func presencePermissions(childIds: [Int]) async throws -> [PresencePermissions] {
        let q = childIds.map { URLQueryItem(name: "childIds[]", value: String($0)) }
        let list: Lossy<ConfigItemDTO> = try await call("presence.getPresenceConfigurationByChildIds", query: q)
        return list.items.compactMap { item in
            guard let cid = (item.uniStudentId ?? item.childId)?.value else { return nil }
            let guardian = item.presenceConfiguration?.dashboardModuleSettings?.items
                .first { $0.presenceDashboardContext == "guardian_dashboard" }
            let modules = guardian?.presenceModules?.items ?? []
            func editable(_ type: String) -> Bool {
                modules.first { $0.moduleType == type }?.permission == "editable"
            }
            return PresencePermissions(childId: cid,
                                       canReportSick: editable("report_sick"),
                                       canAddVacation: editable("vacation"),
                                       canEditPickup: editable("pickup_times") || editable("pickup_type"))
        }
    }

    /// Names you can choose for "Hentes af" / "Går hjem med", e.g. "Majid G (Far)".
    func pickupNames(childId: Int) async throws -> [String] {
        let list: Lossy<PickupDTO> = try await call("presence.getPickupResponsibles",
                                                    query: [.init(name: "uniStudentIds[]", value: String(childId))])
        var names: [String] = []
        for item in list.items where item.uniStudentId?.value == childId || item.uniStudentId == nil {
            for p in item.relatedPersons?.items ?? [] {
                guard let n = p.name?.nilIfEmpty else { continue }
                names.append(p.relation?.nilIfEmpty.map { "\(n) (\($0))" } ?? n)
            }
            names += (item.pickupSuggestions?.items ?? []).compactMap { $0.pickUpName?.nilIfEmpty }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
