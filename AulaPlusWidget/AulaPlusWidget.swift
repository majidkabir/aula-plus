import AppIntents
import SwiftUI
import WidgetKit

private let palette: [Color] = [.orange, .teal, .pink, .purple, .green, .indigo, .mint, .brown]

/// Mirrors the app's themes (brand → secondary) for the widget background.
private func themeColors(_ id: String?) -> [Color] {
    switch id {
    case "forest": return [Color(red: 0.10, green: 0.52, blue: 0.36), Color(red: 0.55, green: 0.80, blue: 0.30)]
    case "sunset": return [Color(red: 0.90, green: 0.33, blue: 0.22), Color(red: 0.99, green: 0.66, blue: 0.22)]
    case "lavender": return [Color(red: 0.45, green: 0.32, blue: 0.88), Color(red: 0.90, green: 0.45, blue: 0.80)]
    case "graphite": return [Color(red: 0.24, green: 0.29, blue: 0.37), Color(red: 0.50, green: 0.58, blue: 0.68)]
    default: return [Color(red: 0.16, green: 0.40, blue: 0.93), Color(red: 0.20, green: 0.74, blue: 0.95)]
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let child: ChildEntity?
    let content: WidgetContent
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .init(date: .now, snapshot: .placeholder, child: nil, content: .overview)
    }

    func snapshot(for configuration: ConfigureAulaWidget, in context: Context) async -> SnapshotEntry {
        .init(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load(),
              child: configuration.child, content: configuration.content)
    }

    func timeline(for configuration: ConfigureAulaWidget, in context: Context) async -> Timeline<SnapshotEntry> {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load(), child: configuration.child, content: configuration.content)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

struct AulaWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool {
        [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
    }
    private var gradient: Bool { family == .systemSmall && entry.content == .overview }

    var body: some View {
        Group {
            if let s = entry.snapshot {
                content(s)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aula+").font(.headline)
                    Text("Åbn appen og log ind.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) {
            if gradient {
                LinearGradient(colors: themeColors(entry.snapshot?.theme), startPoint: .topLeading, endPoint: .bottomTrailing)
            } else if isAccessory {
                Color.clear
            } else {
                Color(.systemBackground)
            }
        }
        .foregroundStyle(gradient ? Color.white : Color.primary)
    }

    @ViewBuilder private func content(_ s: WidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular: circular(s)
        case .accessoryRectangular: rectangular(s)
        case .accessoryInline: Text(inlineText(s))
        default:
            switch entry.content {
            case .overview:
                if family == .systemSmall { smallUnread(s) } else { overview(s) }
            case .status: statusList(s)
            case .events: eventList(s)
            case .todos: todoList(s)
            case .messages: messageList(s)
            }
        }
    }

    private var rowLimit: Int { family == .systemLarge ? 8 : family == .systemMedium ? 3 : 3 }

    // MARK: Home screen

    private func smallUnread(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bubble.left.fill")
                Spacer()
                Text("\(s.unread)").font(.title.bold()).contentTransition(.numericText())
            }
            Text(s.unread == 1 ? "ulæst besked" : "ulæste beskeder").font(.caption).opacity(0.85)
            Spacer(minLength: 0)
            if let subject = s.latestSubject {
                Text(s.latestSender ?? "").font(.caption2.weight(.semibold)).lineLimit(1)
                Text(subject).font(.caption2).lineLimit(2).opacity(0.85)
            }
        }
    }

    private func overview(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                statusRows(s, limit: 3)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s.unread)").font(.title.bold())
                        .foregroundStyle(LinearGradient(colors: themeColors(s.theme), startPoint: .top, endPoint: .bottom))
                    Text("ulæste").font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(s.updated, style: .time).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if family == .systemLarge {
                Divider()
                section(Text("Husk"), systemImage: "checklist") { taskRows(s, limit: 3) }
                section(Text("Næste"), systemImage: "calendar") { eventRows(s, limit: 3) }
                Spacer(minLength: 0)
            }
        }
    }

    private func statusList(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(Text("Komme/gå"), systemImage: "figure.walk")
            statusRows(s, limit: rowLimit)
            Spacer(minLength: 0)
        }
    }

    private func eventList(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(entry.child.map { Text("\($0.name) · Næste") } ?? Text("Næste"), systemImage: "calendar")
            eventRows(s, limit: rowLimit)
            Spacer(minLength: 0)
        }
    }

    private func todoList(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(Text("Husk"), systemImage: "checklist")
            taskRows(s, limit: rowLimit)
            Spacer(minLength: 0)
        }
    }

    private func messageList(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                header(Text("Ulæste"), systemImage: "bubble.left.fill")
                Spacer()
                Text("\(s.unread)").font(.headline.bold())
            }
            let list = s.unreadMessages ?? []
            if list.isEmpty {
                Text("Ingen ulæste beskeder").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(list.prefix(family == .systemSmall ? 2 : rowLimit).enumerated()), id: \.offset) { _, m in
                VStack(alignment: .leading, spacing: 0) {
                    Text(m.sender).font(.caption2.weight(.semibold)).lineLimit(1)
                    Text(m.subject).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Rows

    private func header(_ title: Text, systemImage: String) -> some View {
        Label { title } icon: { Image(systemName: systemImage) }
            .font(.caption.weight(.bold))
            .foregroundStyle(LinearGradient(colors: themeColors(entry.snapshot?.theme), startPoint: .leading, endPoint: .trailing))
    }

    private func section<C: View>(_ title: Text, systemImage: String, @ViewBuilder rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(title, systemImage: systemImage)
            rows()
        }
    }

    private func statusRows(_ s: WidgetSnapshot, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(s.children(for: entry.child).prefix(limit), id: \.self) { c in
                HStack(spacing: 8) {
                    Image(systemName: c.symbol ?? "person.fill")
                        .foregroundStyle(palette[c.colorIndex % palette.count])
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(c.name) · \(c.status ?? "–")").font(.caption.weight(.semibold)).lineLimit(1)
                        if let d = c.detail { Text(d).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func eventRows(_ s: WidgetSnapshot, limit: Int) -> some View {
        let lines = s.children(for: entry.child)
        let list = s.events(for: lines).prefix(limit)
        if list.isEmpty {
            Text("Intet i kalenderen den næste uge").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Array(list.enumerated()), id: \.offset) { _, item in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(when(item.event)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: family == .systemSmall ? 44 : 62, alignment: .leading)
                Text(item.event.title).font(.caption.weight(.medium)).lineLimit(1)
                if entry.child == nil && lines.count > 1 && family != .systemSmall {
                    Spacer(minLength: 0)
                    Text(item.child).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder private func taskRows(_ s: WidgetSnapshot, limit: Int) -> some View {
        let list = (s.tasks ?? []).prefix(limit)
        if list.isEmpty {
            Text("Intet at huske lige nu").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Array(list.enumerated()), id: \.offset) { _, t in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "circle").font(.caption2).foregroundStyle(.secondary)
                Text(t.title).font(.caption).lineLimit(1)
                Spacer(minLength: 0)
                if let due = t.due, family != .systemSmall {
                    Text(due, format: .dateTime.weekday(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func when(_ e: WidgetSnapshot.EventLine) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(e.start) {
            return e.allDay ? String(localized: "I dag") : e.start.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInTomorrow(e.start) { return String(localized: "I morgen") }
        return e.start.formatted(.dateTime.weekday(.abbreviated).day())
    }

    // MARK: Lock screen

    @ViewBuilder private func circular(_ s: WidgetSnapshot) -> some View {
        switch entry.content {
        case .todos:
            Gauge(value: 0) { Image(systemName: "checklist") } currentValueLabel: { Text("\(s.tasks?.count ?? 0)") }
                .gaugeStyle(.accessoryCircularCapacity)
        case .status, .events:
            if let c = s.children(for: entry.child).first {
                VStack(spacing: 1) {
                    Image(systemName: c.symbol ?? "person.fill").font(.title3)
                    Text(c.name).font(.caption2).lineLimit(1)
                }
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bubble.left.fill").font(.caption)
                    Text("\(s.unread)").font(.title3.bold())
                }
            }
        }
    }

    @ViewBuilder private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            switch entry.content {
            case .todos:
                Label("Husk", systemImage: "checklist").font(.caption.weight(.bold))
                ForEach(Array((s.tasks ?? []).prefix(2).enumerated()), id: \.offset) { _, t in
                    Text(t.title).font(.caption).lineLimit(1)
                }
            case .events:
                let list = s.events(for: s.children(for: entry.child)).prefix(2)
                Label("Næste", systemImage: "calendar").font(.caption.weight(.bold))
                ForEach(Array(list.enumerated()), id: \.offset) { _, i in
                    Text("\(when(i.event)) \(i.event.title)").font(.caption).lineLimit(1)
                }
            case .messages:
                Label("\(s.unread) ulæste", systemImage: "bubble.left.fill").font(.caption.weight(.bold))
                if let m = s.unreadMessages?.first { Text(m.subject).font(.caption).lineLimit(2) }
            default:
                ForEach(s.children(for: entry.child).prefix(3), id: \.self) { c in
                    Label("\(c.name) · \(c.status ?? "–")", systemImage: c.symbol ?? "person.fill").font(.caption).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineText(_ s: WidgetSnapshot) -> String {
        switch entry.content {
        case .todos:
            return s.tasks?.first.map { String(localized: "Husk: \($0.title)") } ?? String(localized: "Intet at huske")
        case .events:
            return s.events(for: s.children(for: entry.child)).first.map { "\(when($0.event)) \($0.event.title)" }
                ?? String(localized: "Intet i kalenderen")
        case .status:
            return s.children(for: entry.child).first.map { "\($0.name): \($0.status ?? "–")" } ?? "Aula+"
        default:
            return String(localized: "\(s.unread) ulæste beskeder")
        }
    }
}

@main
struct AulaPlusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AulaPlusWidget", intent: ConfigureAulaWidget.self, provider: Provider()) { entry in
            AulaWidgetView(entry: entry).fontDesign(.rounded)
        }
        .configurationDisplayName("Aula+")
        .description("Status, begivenheder, huskeliste eller beskeder – for ét barn eller alle. Hold fingeren på widgetten for at vælge.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
