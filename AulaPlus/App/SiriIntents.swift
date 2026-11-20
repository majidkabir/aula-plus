import AppIntents
import SwiftUI

// Siri, Spotlight and Shortcuts. Answers come from the summary the app keeps for its widgets
// (updated whenever the app or the background check reads Aula), so Siri answers instantly and offline.

private func snapshot() -> WidgetSnapshot? { WidgetSnapshot.load() }

/// " (opdateret 14:05)" when the data is more than an hour old.
private func staleNote(_ s: WidgetSnapshot) -> String {
    guard s.updated < .now.addingTimeInterval(-3600) else { return "" }
    return " " + String(localized: "(opdateret \(s.updated.formatted(date: .omitted, time: .shortened)))")
}

private func dayText(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) { return String(localized: "i dag") }
    if cal.isDateInTomorrow(d) { return String(localized: "i morgen") }
    return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
}

private var notLoggedIn: String { String(localized: "Åbn Aula+ og log ind først.") }

// MARK: What to remember

struct WhatToRememberIntent: AppIntent {
    static let title: LocalizedStringResource = "Hvad skal jeg huske?"
    static let description = IntentDescription("Det, du skal gøre eller huske fra beskeder og opslag i Aula.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let s = snapshot()
        let tasks = s?.tasks ?? []
        let dialog: String
        if let s {
            if tasks.isEmpty {
                dialog = String(localized: "Der er ikke noget at huske lige nu.") + staleNote(s)
            } else {
                let spoken = tasks.prefix(3).map { t in t.due.map { "\(t.title) \(dayText($0))" } ?? t.title }
                let head = tasks.count == 1 ? String(localized: "Du skal huske én ting:") : String(localized: "Du skal huske \(tasks.count) ting:")
                dialog = head + " " + ListFormatter.localizedString(byJoining: spoken) + "." + staleNote(s)
            }
        } else {
            dialog = notLoggedIn
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog)) {
            SnippetList(title: "Husk", systemImage: "checklist",
                        rows: tasks.prefix(6).map { ($0.title, $0.due.map(dayText)) })
        }
    }
}

// MARK: Unread messages

struct UnreadMessagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Ulæste beskeder i Aula"
    static let description = IntentDescription("Hvor mange ulæste beskeder du har, og fra hvem.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let s = snapshot()
        let list = s?.unreadMessages ?? []
        let dialog: String
        if let s {
            if s.unread == 0 {
                dialog = String(localized: "Du har ingen ulæste beskeder.") + staleNote(s)
            } else {
                let from = list.prefix(3).map { String(localized: "\($0.sender) om \($0.subject)") }
                let head = s.unread == 1 ? String(localized: "Du har én ulæst besked") : String(localized: "Du har \(s.unread) ulæste beskeder")
                dialog = head + (from.isEmpty ? "." : ": " + ListFormatter.localizedString(byJoining: from) + ".") + staleNote(s)
            }
        } else {
            dialog = notLoggedIn
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog)) {
            SnippetList(title: "Ulæste beskeder", systemImage: "bubble.left.fill",
                        rows: list.prefix(5).map { ($0.subject, Optional($0.sender)) })
        }
    }
}

// MARK: A child's day

struct ChildStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Hvordan går det med mit barn?"
    static let description = IntentDescription("Komme/gå-status, hvornår barnet hentes, og hvad der sker næste gang.")

    @Parameter(title: "Barn")
    var child: ChildEntity?

    static var parameterSummary: some ParameterSummary { Summary("Status for \(\.$child)") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let s = snapshot()
        let lines = s?.children(for: child) ?? []
        let parts = lines.map { c -> String in
            var p = c.name
            if let st = c.status { p += ": " + st.lowercased() } 
            if let d = c.detail { p += ", " + d }
            if let e = c.events?.first { p += ". " + String(localized: "Næste: \(e.title) \(dayText(e.start))") }
            return p
        }
        let dialog = s == nil ? notLoggedIn
            : lines.isEmpty ? String(localized: "Jeg kan ikke finde det barn i Aula+.")
            : parts.joined(separator: ". ") + "." + staleNote(s!)
        return .result(dialog: IntentDialog(stringLiteral: dialog)) {
            SnippetList(title: child.map { LocalizedStringKey($0.name) } ?? "Børn", systemImage: "figure.walk",
                        rows: lines.map { ("\($0.name) · \($0.status ?? "–")", $0.detail) })
        }
    }
}

// MARK: What's coming

struct ComingEventsIntent: AppIntent {
    static let title: LocalizedStringResource = "Hvad sker der i Aula?"
    static let description = IntentDescription("De næste begivenheder i kalenderen den kommende uge.")

    @Parameter(title: "Barn")
    var child: ChildEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let s = snapshot()
        let list = s.map { $0.events(for: $0.children(for: child)) } ?? []
        let spoken = list.prefix(3).map { i -> String in
            let time = i.event.allDay ? "" : " " + String(localized: "kl. \(i.event.start.formatted(date: .omitted, time: .shortened))")
            return "\(i.event.title) \(dayText(i.event.start))\(time)"
        }
        let dialog = s == nil ? notLoggedIn
            : list.isEmpty ? String(localized: "Der er ikke noget i kalenderen den næste uge.") + staleNote(s!)
            : String(localized: "Næste: ") + ListFormatter.localizedString(byJoining: spoken) + "." + staleNote(s!)
        return .result(dialog: IntentDialog(stringLiteral: dialog)) {
            SnippetList(title: "Næste", systemImage: "calendar",
                        rows: list.prefix(6).map { ($0.event.title, dayText($0.event.start) + ($0.event.allDay ? "" : " " + $0.event.start.formatted(date: .omitted, time: .shortened))) })
        }
    }
}

// MARK: Open the app

struct OpenMessagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Åbn beskeder i Aula+"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.selectedTab = .messages
        return .result()
    }
}

struct OpenToDoIntent: AppIntent {
    static let title: LocalizedStringResource = "Åbn huskelisten i Aula+"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.selectedTab = .today
        AppModel.shared.todayPath.append(Route.tasks)
        return .result()
    }
}

// MARK: Phrases

struct AulaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatToRememberIntent(), phrases: [
            "Hvad skal jeg huske i \(.applicationName)",
            "Huskeliste i \(.applicationName)",
            "What do I need to remember in \(.applicationName)",
        ], shortTitle: "Hvad skal jeg huske?", systemImageName: "checklist")
        AppShortcut(intent: UnreadMessagesIntent(), phrases: [
            "Nye beskeder i \(.applicationName)",
            "Har jeg ulæste beskeder i \(.applicationName)",
            "Any new messages in \(.applicationName)",
        ], shortTitle: "Ulæste beskeder", systemImageName: "bubble.left.fill")
        AppShortcut(intent: ChildStatusIntent(), phrases: [
            "Hvordan går det med \(\.$child) i \(.applicationName)",
            "Status for \(\.$child) i \(.applicationName)",
            "Status for børnene i \(.applicationName)",
            "How is \(\.$child) doing in \(.applicationName)",
        ], shortTitle: "Status", systemImageName: "figure.walk")
        AppShortcut(intent: ComingEventsIntent(), phrases: [
            "Hvad sker der i \(.applicationName)",
            "Hvad skal \(\.$child) i \(.applicationName)",
            "What's coming up in \(.applicationName)",
        ], shortTitle: "Næste begivenheder", systemImageName: "calendar")
        AppShortcut(intent: OpenMessagesIntent(), phrases: [
            "Åbn beskeder i \(.applicationName)",
            "Open messages in \(.applicationName)",
        ], shortTitle: "Åbn beskeder", systemImageName: "envelope.open")
    }
}

/// The card Siri shows under its answer.
private struct SnippetList: View {
    let title: LocalizedStringKey
    let systemImage: String
    let rows: [(String, String?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline) {
                    Text(r.0).font(.subheadline).lineLimit(2)
                    Spacer(minLength: 8)
                    if let d = r.1 { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        }
        .padding()
    }
}
