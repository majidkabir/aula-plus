import EventKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Short summaries of long posts and message threads, written by Apple Intelligence on the phone.
@MainActor
@Observable
final class Summarizer {
    static let shared = Summarizer()

    private struct Entry: Codable { let hash: Int; let bullets: [String] }
    @ObservationIgnored private var cache: [String: Entry] = [:]
    @ObservationIgnored private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("summaries.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: file), let c = try? JSONDecoder().decode([String: Entry].self, from: data) { cache = c }
    }

    /// Only texts this long get a summary.
    static let minLength = 600

    static var isAvailable: Bool { ParentTaskFinder.usesAI }

    func cached(_ key: String, text: String) -> [String]? {
        guard let e = cache[key], e.hash == ParentTaskFinder.stableHash(text) else { return nil }
        return e.bullets
    }

    func summary(_ key: String, text: String) async -> [String]? {
        if let c = cached(key, text: text) { return c }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AIReader.isAvailable,
           let bullets = try? await AISummary.make(text), !bullets.isEmpty {
            cache[key] = Entry(hash: ParentTaskFinder.stableHash(text), bullets: bullets)
            if cache.count > 300 { cache = Dictionary(uniqueKeysWithValues: cache.suffix(200).map { ($0.key, $0.value) }) }
            try? JSONEncoder().encode(cache).write(to: file, options: .atomic)
            return bullets
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct SummaryPoints {
    @Guide(description: "One to three short Danish sentences with what a busy parent needs to know.", .count(1...3))
    var points: [String]
}

@available(iOS 26.0, *)
enum AISummary {
    static func make(_ text: String) async throws -> [String] {
        let session = LanguageModelSession(instructions: """
            Summarize messages from a Danish daycare or school for a busy parent. Write in Danish. \
            Keep dates, times and things to bring. Leave out greetings. Never add anything that is not in the text.
            """)
        let answer = try await session.respond(to: String(text.prefix(3500)), generating: SummaryPoints.self)
        return answer.content.points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
#endif

/// "Kort fortalt": shown on top of long posts and threads when Apple Intelligence is on.
struct SummaryBox: View {
    let key: String
    let text: String
    @State private var bullets: [String]?
    @State private var loading = false

    var body: some View {
        Group {
            if text.count >= Summarizer.minLength && Summarizer.isAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Kort fortalt", systemImage: "sparkles").font(.caption.weight(.bold)).foregroundStyle(.purple)
                    if let bullets {
                        ForEach(bullets, id: \.self) { b in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•")
                                Text(b).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.subheadline)
                        }
                    } else if loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Læser …").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .task(id: "\(key)|\(text.count)") {
            guard text.count >= Summarizer.minLength, Summarizer.isAvailable else { return }
            bullets = Summarizer.shared.cached(key, text: text)
            guard bullets == nil else { return }
            loading = true
            bullets = await Summarizer.shared.summary(key, text: text)
            loading = false
        }
    }
}

/// Puts a task in the Reminders app (needs permission once).
enum ReminderMaker {
    private static let store = EKEventStore()

    static func add(_ t: ParentTask) async throws {
        guard try await store.requestFullAccessToReminders() else {
            throw NSError(domain: "Aula+", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Aula+ har ikke adgang til Påmindelser. Slå det til i Indstillinger → Aula+.")])
        }
        let r = EKReminder(eventStore: store)
        r.title = t.title
        r.notes = String(localized: "Fra Aula: \(t.sourceTitle)")
        r.calendar = store.defaultCalendarForNewReminders()
        if let due = t.due {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: due)
            c.hour = 8
            r.dueDateComponents = c
            r.addAlarm(EKAlarm(absoluteDate: Calendar.current.date(from: c) ?? due))
        }
        try store.save(r, commit: true)
    }

    /// An all-day event on the day the task is due (today when it has no day), for Apple's own sheet.
    static func event(for t: ParentTask) -> Event {
        let day = Calendar.current.startOfDay(for: t.due ?? .now)
        return Event(id: t.id, title: t.title, start: day, end: Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day,
                     allDay: true, location: nil, teacher: nil, substitute: nil, hasSubstitute: false, type: nil, childIds: [])
    }
}
