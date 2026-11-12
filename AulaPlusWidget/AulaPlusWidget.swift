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
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { .init(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(.init(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct AulaWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .systemSmall: small(s)
                default: medium(s)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aula+").font(.headline)
                    Text("Åbn appen og log ind.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                LinearGradient(colors: themeColors(entry.snapshot?.theme), startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Color(.systemBackground)
            }
        }
        .foregroundStyle(family == .systemSmall ? Color.white : Color.primary)
    }

    private func small(_ s: WidgetSnapshot) -> some View {
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

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(s.children.prefix(3), id: \.self) { c in
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
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(s.unread)").font(.title.bold())
                    .foregroundStyle(LinearGradient(colors: themeColors(s.theme), startPoint: .top, endPoint: .bottom))
                Text("ulæste").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(s.updated, style: .time).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

@main
struct AulaPlusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AulaPlusWidget", provider: Provider()) { entry in
            AulaWidgetView(entry: entry).fontDesign(.rounded)
        }
        .configurationDisplayName("Aula+")
        .description("Børnenes status i dag og ulæste beskeder.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
