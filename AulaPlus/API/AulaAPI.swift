import Foundation

enum AulaError: LocalizedError {
    case http(Int)
    case rejected(method: String, code: Int, subCode: Int?)
    case stepUpRequired
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let c): return String(localized: "Aula svarede med HTTP \(c).")
        case .rejected(let m, let c, let s):
            let code = s.map { "\(c)/\($0)" } ?? "\(c)"
            return String(localized: "Aula afviste \(m) (kode \(code)).")
        case .stepUpRequired: return String(localized: "Kræver MitID-login på højeste niveau.")
        case .decoding(let m): return String(localized: "Uventet svar fra Aula: \(m)")
        }
    }
}

/// Talks to Aula's internal JSON API (`www.aula.dk/api/vNN/?method=...`).
///
/// Auth mirrors the official app: the OIDC access token is sent as an
/// `access_token` query parameter, cookies ride along, and POSTs carry the
/// `Csrfp-Token` cookie value in a `csrfp-token` header. On 401 or session
/// sub-codes (9, 23) the token is refreshed once and the call replayed.
actor AulaAPI {
    static let shared = AulaAPI()

    let session: URLSession
    private let tokens: TokenStore
    private var version: Int
    private var sessionReady = false
    private var bootstrapTask: Task<Session, Error>?

    init(tokens: TokenStore = .shared) {
        self.tokens = tokens
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "Accept": "application/json, text/plain",
            "User-Agent": "iOS",
            "App-Device-Type": "Phone",
        ]
        session = URLSession(configuration: config)
        let saved = UserDefaults.standard.integer(forKey: "aula.apiVersion")
        version = saved > 0 ? saved : AulaConfig.defaultAPIVersion
    }

    func reset() {
        sessionReady = false
        bootstrapTask = nil
        HTTPCookieStorage.shared.cookies?
            .filter { $0.domain.hasSuffix("aula.dk") }
            .forEach(HTTPCookieStorage.shared.deleteCookie)
    }

    // MARK: Session bootstrap

    /// Loads profile + context. Also establishes the server-side session that
    /// every other method requires.
    func bootstrap() async throws -> Session {
        if let t = bootstrapTask { return try await t.value }
        let t = Task { try await self.loadSession() }
        bootstrapTask = t
        do {
            let s = try await t.value
            sessionReady = true
            return s
        } catch {
            bootstrapTask = nil
            throw error
        }
    }

    private func loadSession() async throws -> Session {
        let profiles: ProfilesByLoginDTO = try await call("profiles.getProfilesByLogin", needsSession: false)
        guard let profile = profiles.profiles?.items.first else { throw AulaError.decoding("ingen profil") }
        let ctx: ProfileContextDTO = try await call("profiles.getProfileContext",
                                                    query: [.init(name: "portalrole", value: "guardian")],
                                                    needsSession: false)
        var children = profile.children?.items.map { $0.toChild() } ?? []
        // Extended-access children ("udvidet adgang") only appear in the context.
        for inst in ctx.institutions?.items ?? [] {
            for c in inst.children?.items ?? [] where !children.contains(where: { $0.id == c.id.value }) {
                children.append(c.toChild(fallbackInstitution: inst.name))
            }
        }
        let shown = (ctx.pageConfiguration?.widgetConfigurations?.items ?? [])
            .filter { ($0.aggregatedDisplayMode ?? "Shown") == "Shown" }
        let widgets = Set(shown.compactMap { $0.widget?.widgetId?.value })
        var widgetNames: [String: String] = [:]
        var widgetLinks: [WidgetLink] = []
        for w in shown {
            guard let id = w.widget?.widgetId?.value, let name = w.widget?.name?.nilIfEmpty else { continue }
            widgetNames[id] = name
            if let raw = w.widget?.url?.nilIfEmpty, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true,
               !widgetLinks.contains(where: { $0.id == id }) {
                widgetLinks.append(WidgetLink(id: id, name: name, url: url))
            }
        }
        let instIds = (profile.institutionProfiles?.items.map(\.id.value) ?? []) + children.map(\.id)
        return Session(displayName: profile.displayName ?? "",
                       children: children,
                       institutionProfileIds: Array(Set(instIds)),
                       guardianUserId: ctx.userId?.value,
                       widgetIds: widgets,
                       guardianProfileIds: profile.institutionProfiles?.items.map(\.id.value) ?? [],
                       widgetNames: widgetNames,
                       widgetLinks: widgetLinks)
    }

    // MARK: Endpoints

    func presence(childIds: [Int]) async throws -> [Presence] {
        try await withThrowingTaskGroup(of: [DailyOverviewDTO].self) { group in
            for id in childIds {
                group.addTask {
                    // A child without Komme/Gå (e.g. a school child) is rejected → no overview.
                    // Auth and network errors still propagate so the cache isn't overwritten with nothing.
                    do {
                        let list: Lossy<DailyOverviewDTO> = try await self.call(
                            "presence.getDailyOverview", query: [.init(name: "childIds[]", value: String(id))])
                        return list.items
                    } catch is AulaError {
                        return []
                    }
                }
            }
            var out: [Presence] = []
            for try await list in group {
                for d in list {
                    guard let cid = d.institutionProfile?.id?.value else { continue }
                    // No plan for the day (weekend, holiday): Aula fills in 05:00–23:59. Show no times then.
                    var entry = AulaDate.shortTime(d.entryTime)
                    var exit = AulaDate.shortTime(d.exitTime)
                    if Presence.isPlaceholder(entry: entry, exit: exit) || Calendar.week.isDateInWeekend(.now) {
                        entry = nil
                        exit = nil
                    }
                    out.append(Presence(childId: cid,
                                        status: d.status.flatMap(PresenceStatus.init(rawValue:)),
                                        checkIn: AulaDate.shortTime(d.checkInTime),
                                        checkOut: AulaDate.shortTime(d.checkOutTime),
                                        plannedEntry: entry,
                                        plannedExit: exit,
                                        exitWith: d.exitWith?.nilIfEmpty,
                                        comment: d.comment?.nilIfEmpty,
                                        location: d.location?.name?.nilIfEmpty))
                }
            }
            return out
        }
    }

    /// `folderId` nil = the inbox.
    func threads(page: Int = 0, folderId: Int? = nil) async throws -> (threads: [ThreadSummary], more: Bool) {
        var q: [URLQueryItem] = [
            .init(name: "sortOn", value: "date"),
            .init(name: "orderDirection", value: "desc"),
            .init(name: "page", value: String(page)),
        ]
        if let folderId { q.append(.init(name: "folderId", value: String(folderId))) }
        let dto: ThreadsDTO = try await call("messaging.getThreads", query: q)
        return (dto.threads?.items.map(\.model) ?? [], dto.moreMessagesExist ?? false)
    }

    func messages(threadId: String, page: Int = 0) async throws -> ThreadPage {
        let dto: ThreadMessagesDTO = try await call("messaging.getMessagesForThread", query: [
            .init(name: "threadId", value: threadId),
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: "20"),
        ])
        return dto.model
    }

    /// Moves the thread's read marker to `messageId` (own mailbox only).
    func markRead(threadId: String, messageId: String) async throws {
        let body: [String: Any] = [
            "threadId": Int(threadId) ?? threadId,
            "messageId": messageId,
            "commonInboxId": NSNull(),
            "otpInboxId": NSNull(),
        ]
        let _: Ignored = try await call("messaging.setLastReadMessage", body: body)
    }

    func events(institutionProfileIds: [Int], from: Date, to: Date) async throws -> [Event] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AulaDate.copenhagen
        f.dateFormat = "yyyy-MM-dd '00:00:00.0000'Z"
        let start = f.string(from: from)
        f.dateFormat = "yyyy-MM-dd '23:59:59.0000'Z"
        let end = f.string(from: to)
        let list: Lossy<EventDTO> = try await call("calendar.getEventsByProfileIdsAndResourceIds", body: [
            "instProfileIds": institutionProfileIds,
            "resourceIds": [Int](),
            "start": start,
            "end": end,
        ])
        // Aula duplicates a lesson once per child; merge by id.
        var seen: [String: Event] = [:]
        for e in list.items.compactMap(\.model) {
            if let prev = seen[e.id] {
                seen[e.id] = Event(id: e.id, title: e.title, start: e.start, end: e.end, allDay: e.allDay,
                                   location: e.location, teacher: e.teacher, substitute: e.substitute,
                                   hasSubstitute: e.hasSubstitute, type: e.type,
                                   childIds: Array(Set(prev.childIds + e.childIds)))
            } else { seen[e.id] = e }
        }
        return seen.values.sorted { $0.start < $1.start }
    }

    func posts(institutionProfileIds: [Int], filter: PostFilter = .all, index: Int = 0, limit: Int = 20) async throws -> [Post] {
        var q: [URLQueryItem] = [
            .init(name: "parent", value: "profile"),
            .init(name: "index", value: String(index)),
            .init(name: "limit", value: String(limit)),
        ] + filter.query
        q += institutionProfileIds.map { .init(name: "institutionProfileIds[]", value: String($0)) }
        let dto: PostsDTO = try await call("posts.getAllPosts", query: q)
        return dto.posts?.items.map(\.model) ?? []
    }

    // MARK: Week plans (third-party widgets, Bearer token from Aula)

    func weekPlans(session s: Session, week: (year: Int, week: Int)) async throws -> [WeekPlan] {
        let childFilter = s.children.compactMap(\.userId)
        let instFilter = Array(Set(s.children.compactMap(\.institutionCode)))
        let uuid = s.guardianUserId ?? ""
        if s.widgetIds.contains(AulaConfig.Widget.meebook) {
            let token = try await widgetToken(AulaConfig.Widget.meebook)
            var q: [URLQueryItem] = [
                .init(name: "currentWeekNumber", value: String(format: "%d-W%02d", week.year, week.week)),
                .init(name: "userProfile", value: "guardian"),
            ]
            q += childFilter.map { .init(name: "childFilter[]", value: $0) }
            q += instFilter.map { .init(name: "institutionFilter[]", value: $0) }
            let students: Lossy<MeebookStudentDTO> = try await external(
                "\(AulaConfig.meebookAPI)/relatedweekplan/all", query: q,
                headers: ["Authorization": token, "sessionUUID": uuid, "X-Version": "1.0"])
            return students.items.map { st in
                WeekPlan(childName: st.name ?? "", sections: (st.weekPlan?.items ?? []).compactMap { day in
                    let tasks = day.tasks?.items ?? []
                    guard !tasks.isEmpty else { return nil }
                    let html = tasks.map { t in
                        "<p><b>\(t.title ?? t.pill ?? "")</b></p>\(t.content ?? "")"
                    }.joined(separator: "<br>")
                    return .init(title: Self.weekdayTitle(day.date), html: html)
                })
            }
        }
        let mu = [AulaConfig.Widget.muUgeplan, AulaConfig.Widget.muSSO].first(where: s.widgetIds.contains)
        if let widget = mu {
            let token = try await widgetToken(widget)
            let resp: MUResponseDTO = try await external("\(AulaConfig.minUddannelseAPI)/ugebrev", query: [
                .init(name: "assuranceLevel", value: "3"),
                .init(name: "childFilter", value: childFilter.joined(separator: ",")),
                .init(name: "currentWeekNumber", value: "\(week.year)-W\(week.week)"),
                .init(name: "institutionFilter", value: instFilter.joined(separator: ",")),
                .init(name: "isMobileApp", value: "false"),
                .init(name: "placement", value: "narrow"),
                .init(name: "sessionUUID", value: uuid),
                .init(name: "userProfile", value: "guardian"),
            ], headers: ["Authorization": token])
            return (resp.personer?.items ?? []).map { p in
                let letters = (p.institutioner?.items ?? []).flatMap { $0.ugebreve?.items ?? [] }
                return WeekPlan(childName: p.navn ?? "", sections: letters.compactMap { l in
                    guard let html = l.indhold?.nilIfEmpty else { return nil }
                    return .init(title: l.tilknytningNavn ?? String(localized: "Ugebrev"), html: html)
                })
            }
        }
        return []
    }

    func widgetToken(_ id: String) async throws -> String {
        let token: String = try await call("aulaToken.getAulaToken", query: [.init(name: "widgetId", value: id)])
        return "Bearer \(token)"
    }

    private static func weekdayTitle(_ s: String?) -> String {
        guard let d = AulaDate.parse(s) else { return s ?? "" }
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return f.string(from: d).capitalized
    }

    // MARK: Transport

    struct Ignored: Decodable { init(from decoder: Decoder) throws {} }

    /// Calls an Aula API method and returns its decoded `data`.
    func call<T: Decodable>(_ method: String,
                                    query: [URLQueryItem] = [],
                                    body: [String: Any]? = nil,
                                    needsSession: Bool = true) async throws -> T {
        if needsSession && !sessionReady { _ = try await bootstrap() }

        var (data, http) = try await send(method, query: query, body: body)
        if Self.isAuthFailure(http: http, data: data) {
            try await tokens.refresh()
            if needsSession {
                sessionReady = false
                bootstrapTask = nil
                _ = try await bootstrap()
            }
            (data, http) = try await send(method, query: query, body: body)
        }

        let status = (try? JSONDecoder().decode(StatusEnvelope.self, from: data))?.status
        if status?.subCode == 8 { throw AulaError.stepUpRequired }
        if Self.isAuthFailure(http: http, data: data) { throw AuthError.notLoggedIn }
        if let code = status?.code, code != 0 {
            throw AulaError.rejected(method: method, code: code, subCode: status?.subCode)
        }
        guard (200..<300).contains(http.statusCode) else { throw AulaError.http(http.statusCode) }
        do {
            guard let value = try JSONDecoder().decode(Envelope<T>.self, from: data).data else {
                // `data: null` → empty list/object where that makes sense.
                if let empty = try? JSONDecoder().decode(T.self, from: Data("[]".utf8)) { return empty }
                if let empty = try? JSONDecoder().decode(T.self, from: Data("{}".utf8)) { return empty }
                throw AulaError.decoding("\(method): ingen data")
            }
            return value
        } catch let e as DecodingError {
            throw AulaError.decoding("\(method): \(e)")
        }
    }

    private static func isAuthFailure(http: HTTPURLResponse, data: Data) -> Bool {
        if http.statusCode == 401 { return true }
        let sub = (try? JSONDecoder().decode(StatusEnvelope.self, from: data))?.status?.subCode
        return sub == 9 || sub == 23
    }

    private func send(_ method: String, query: [URLQueryItem], body: [String: Any]?) async throws -> (Data, HTTPURLResponse) {
        let token = try await tokens.accessToken()
        for _ in 0..<5 {
            let v = version
            var c = URLComponents(string: "\(AulaConfig.apiBase)\(v)/")!
            c.queryItems = [.init(name: "method", value: method)] + query + [.init(name: "access_token", value: token)]
            var req = URLRequest(url: c.url!)
            if let body {
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                if let csrf = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == AulaConfig.csrfCookie })?.value {
                    req.setValue(csrf, forHTTPHeaderField: AulaConfig.csrfHeader)
                }
            }
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw AulaError.http(0) }
            if http.statusCode == 410 {          // API version retired → try the next one
                // Parallel calls all see the 410; bump once, not once per call.
                if version == v {
                    version = v + 1
                    UserDefaults.standard.set(version, forKey: "aula.apiVersion")
                }
                continue
            }
            return (data, http)
        }
        throw AulaError.http(410)
    }

    func external<T: Decodable>(_ url: String, query: [URLQueryItem], headers: [String: String]) async throws -> T {
        var c = URLComponents(string: url)!
        c.queryItems = query
        var req = URLRequest(url: c.url!)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw AulaError.http(code) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AulaError.decoding("\(url): \(error)") }
    }
}
