import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Something a parent has to do, found in a message or post: bring something, reply, sign up, pay …
struct ParentTask: Codable, Identifiable, Hashable {
    enum Source: Codable, Hashable {
        case thread(String)
        case post(Int)
        var key: String {
            switch self {
            case .thread(let id): "t\(id)"
            case .post(let id): "p\(id)"
            }
        }
    }
    let id: String
    let title: String
    let due: Date?
    let source: Source
    let sourceTitle: String
    let sourceDate: Date?
    /// Found by Apple Intelligence (else by keywords).
    let byAI: Bool
}

/// Reads messages and posts on the phone and lists what the parent must do.
/// Nothing leaves the phone: Apple Intelligence runs on the device, the fallback is plain keyword rules.
@MainActor
@Observable
final class ParentTaskFinder {
    static let shared = ParentTaskFinder()

    private struct Store: Codable {
        var tasks: [ParentTask] = []
        /// Source key → hash of the text that was read, so unchanged texts aren't read again.
        var read: [String: Int] = [:]
        var done: Set<String> = []
        var aiVersion = 0
    }

    private(set) var tasks: [ParentTask] = []
    private(set) var done: Set<String> = []
    /// While reading: (done, total).
    private(set) var progress: (Int, Int)?
    var isEnabled: Bool {
        get { access(keyPath: \.isEnabled); return !UserDefaults.standard.bool(forKey: "parentTasksOff") }
        set { withMutation(keyPath: \.isEnabled) { UserDefaults.standard.set(!newValue, forKey: "parentTasksOff") } }
    }

    @ObservationIgnored private var store = Store()
    @ObservationIgnored private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("parent-tasks.json")
    }()
    @ObservationIgnored private var running: Task<Void, Never>?
    /// Bumped when the AI prompt changes, so everything is read again once.
    private static let aiVersion = 1

    private init() {
        if let data = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Store.self, from: data) { store = s }
        if Self.usesAI && store.aiVersion != Self.aiVersion {
            store.read = [:]
            store.aiVersion = Self.aiVersion
        }
        publish()
    }

    /// Open tasks, soonest first (undated ones by when they were sent).
    var open: [ParentTask] {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!
        let fortnight = Date.now.addingTimeInterval(-14 * 86_400)
        return tasks.filter { t in
            guard !done.contains(t.id) else { return false }
            if let due = t.due { return due >= yesterday }
            return (t.sourceDate ?? .now) >= fortnight
        }
        .sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.sourceDate ?? .distantPast) > (b.sourceDate ?? .distantPast)
            }
        }
    }

    var finished: [ParentTask] { tasks.filter { done.contains($0.id) } }

    func tasks(for source: ParentTask.Source) -> [ParentTask] { tasks.filter { $0.source == source } }

    func toggle(_ t: ParentTask) {
        if done.contains(t.id) { store.done.remove(t.id) } else { store.done.insert(t.id) }
        publish()
        save()
    }

    func eraseAll() {
        store = Store(aiVersion: Self.aiVersion)
        publish()
        save()
    }

    static var usesAI: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return AIReader.isAvailable }
        #endif
        return false
    }

    /// Reads messages and posts from the last three weeks that changed since last time.
    func update(threads: [ThreadSummary], posts: [Post], myName: String) {
        guard isEnabled, running == nil else { return }
        let since = Date.now.addingTimeInterval(-21 * 86_400)
        var todo: [(ParentTask.Source, String, String, Date?)] = []
        for t in threads where (t.date ?? .distantPast) >= since {
            // My own reply is the latest message: nothing new from the school.
            if !myName.isEmpty, t.sender.localizedCaseInsensitiveCompare(myName) == .orderedSame { continue }
            todo.append((.thread(t.id), t.subject, t.subject + "\n" + t.preview, t.date))
        }
        for p in posts where (p.date ?? .distantPast) >= since {
            todo.append((.post(p.id), p.title, p.title + "\n" + HTML.plainText(p.html), p.date))
        }
        todo = todo.filter { store.read[$0.0.key] != Self.stableHash($0.2) }
        guard !todo.isEmpty else { return }
        running = Task {
            defer { running = nil; progress = nil }
            for (i, item) in todo.enumerated() {
                progress = (i, todo.count)
                let (source, title, text, date) = item
                let found = await Self.extract(text: text, sentAt: date ?? .now)
                if Task.isCancelled { return }
                let made = found.prefix(4).map { f in
                    ParentTask(id: "\(source.key)-\(Self.stableHash(f.title.lowercased()))", title: f.title, due: f.due, source: source,
                               sourceTitle: title, sourceDate: date, byAI: f.byAI)
                }
                store.tasks.removeAll { $0.source == source }
                store.tasks.append(contentsOf: made)
                store.read[source.key] = Self.stableHash(text)
                publish()
            }
            // Forget tasks from texts older than two months.
            let old = Date.now.addingTimeInterval(-60 * 86_400)
            store.tasks.removeAll { ($0.due ?? $0.sourceDate ?? .now) < old }
            store.done = store.done.intersection(Set(store.tasks.map(\.id)))
            publish()
            save()
        }
    }

    private func publish() {
        tasks = store.tasks
        done = store.done
    }

    private func save() {
        try? JSONEncoder().encode(store).write(to: file, options: .atomic)
    }

    /// FNV-1a: unlike `hashValue` it's the same on every launch.
    nonisolated static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Int(truncatingIfNeeded: h)
    }

    nonisolated static func extract(text: String, sentAt: Date) async -> [FoundTask] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AIReader.isAvailable,
           let found = try? await AIReader.read(text, sentAt: sentAt) {
            return found
        }
        #endif
        return KeywordReader.read(text, sentAt: sentAt)
    }
}

struct FoundTask: Sendable { let title: String; let due: Date?; let byAI: Bool }

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ExtractedTasks {
    @Guide(description: "Things the parent must do. Empty when the text is only information.")
    var tasks: [ExtractedTask]
}

@available(iOS 26.0, *)
@Generable
struct ExtractedTask {
    @Guide(description: "A short Danish instruction to the parent, at most 8 words, e.g. 'Medbring gummistøvler' or 'Tilmeld Sofie til juletræsfest'.")
    var title: String
    @Guide(description: "The deadline or the day it concerns as yyyy-MM-dd, or an empty string when no day is given.")
    var date: String
}

/// Apple Intelligence on the phone (iPhone 15 Pro and newer, iOS 26).
@available(iOS 26.0, *)
enum AIReader {
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale(Locale(identifier: "da_DK"))
    }

    static func read(_ text: String, sentAt: Date) async throws -> [FoundTask] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd EEEE"
        let session = LanguageModelSession(instructions: """
            You read messages from a Danish daycare or school to parents. List only concrete things the parent \
            has to do or remember: bring or pack something, reply, sign up, pay, fill in or sign a form, \
            pick up or drop off at a special time, or a day the place is closed. Ignore greetings, news and \
            descriptions of what the children did. Write each task in Danish. Never invent tasks.
            """)
        let prompt = "The message was sent \(f.string(from: sentAt)).\n\n" + String(text.prefix(2500))
        let answer = try await session.respond(to: prompt, generating: ExtractedTasks.self)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = AulaDate.copenhagen
        var seen = Set<String>()
        return answer.content.tasks.compactMap { t in
            let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(title.lowercased()).inserted else { return nil }
            return .init(title: title, due: f.date(from: t.date.trimmingCharacters(in: .whitespaces)), byAI: true)
        }
    }
}
#endif

/// Danish keyword rules: sentences that ask the parent to do something, with the day they mention.
enum KeywordReader {
    private static let triggers: [String] = [
        #"\bhusk"#, #"\bmedbring"#, #"\btag\b.{0,40}\bmed\b"#, #"\bskal have\b.{0,40}\bmed\b"#, #"\btilmeld"#,
        #"\bsvar\b"#, #"\bsvar på\b"#, #"\bgiv (os )?besked"#, #"\bmeld (tilbage|fra|til)"#, #"\bsenest\b"#, #"\bfrist"#,
        #"\bbetal"#, #"\bmobilepay"#, #"\bunderskriv"#, #"\baflever"#, #"\budfyld"#, #"\bkryds af"#,
        #"\bafhent"#, #"\bhent(e|es)?\b.{0,30}\b(kl|klokken|senest|tidlig)"#, #"\blukket\b"#, #"\blukker\b"#,
        #"\bskiftetøj"#, #"\bregntøj"#, #"\bmadpakke"#, #"\bnavn i\b"#, #"\bpak(ke)?\b"#, #"\bpåmind"#,
    ]
    private static let weekdays = ["mandag": 2, "tirsdag": 3, "onsdag": 4, "torsdag": 5, "fredag": 6, "lørdag": 7, "søndag": 1]
    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "maj": 5, "jun": 6, "jul": 7, "aug": 8,
                                 "sep": 9, "okt": 10, "nov": 11, "dec": 12]

    static func read(_ text: String, sentAt: Date) -> [FoundTask] {
        var out: [FoundTask] = []
        var seen = Set<String>()
        for sentence in sentences(text) {
            let lower = sentence.lowercased()
            guard lower.count >= 8, !lower.hasSuffix("?"),
                  triggers.contains(where: { lower.range(of: $0, options: .regularExpression) != nil }) else { continue }
            let title = cleanTitle(sentence)
            guard seen.insert(title.lowercased()).inserted else { continue }
            out.append(.init(title: title, due: date(in: lower, sentAt: sentAt), byAI: false))
            if out.count >= 3 { break }
        }
        return out
    }

    private static func sentences(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: CharacterSet(charactersIn: ".!\n•"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func cleanTitle(_ s: String) -> String {
        var t = s
        for prefix in ["vi vil gerne minde jer om at ", "vi minder om at ", "husk lige at ", "husk at ", "husk "] {
            if t.lowercased().hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)); break }
        }
        t = t.prefix(1).uppercased() + t.dropFirst()
        if t.count > 90 {
            let cut = t.prefix(90)
            t = (cut.range(of: " ", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? String(cut)) + "…"
        }
        return t
    }

    static func date(in lower: String, sentAt: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AulaDate.copenhagen
        let base = cal.startOfDay(for: sentAt)
        if lower.contains("i overmorgen") { return cal.date(byAdding: .day, value: 2, to: base) }
        if lower.contains("i morgen") { return cal.date(byAdding: .day, value: 1, to: base) }
        if lower.contains("i dag") { return base }
        // 20/11, 20.11, 20-11 (optionally with year)
        if let m = lower.firstMatch(of: #/\b(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?\b/#),
           let d = Int(m.1), let mo = Int(m.2), (1...31).contains(d), (1...12).contains(mo) {
            return make(d, mo, m.3.flatMap { Int($0) }, cal: cal, base: base)
        }
        // 20. november, 20 nov
        if let m = lower.firstMatch(of: #/\b(\d{1,2})\.?\s+(jan|feb|mar|apr|maj|jun|jul|aug|sep|okt|nov|dec)[a-z]*/#),
           let d = Int(m.1), let mo = months[String(m.2)] {
            return make(d, mo, nil, cal: cal, base: base)
        }
        for (name, wd) in weekdays where lower.range(of: "\\b\(name)", options: .regularExpression) != nil {
            return cal.nextDate(after: base, matching: DateComponents(weekday: wd), matchingPolicy: .nextTime)
        }
        return nil
    }

    private static func make(_ day: Int, _ month: Int, _ year: Int?, cal: Calendar, base: Date) -> Date? {
        var y = year.map { $0 < 100 ? 2000 + $0 : $0 } ?? cal.component(.year, from: base)
        guard var d = cal.date(from: DateComponents(year: y, month: month, day: day)) else { return nil }
        if year == nil, d < base.addingTimeInterval(-60 * 86_400) {
            y += 1
            d = cal.date(from: DateComponents(year: y, month: month, day: day)) ?? d
        }
        return d
    }
}
