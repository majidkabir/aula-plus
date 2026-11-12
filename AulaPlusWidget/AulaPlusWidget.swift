import SwiftUI
import WidgetKit

private let palette: [Color] = [.orange, .teal, .pink, .purple, .green, .indigo, .mint, .brown]

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
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bubble.left.fill").foregroundStyle(.tint)
                Spacer()
                Text("\(s.unread)").font(.title.bold()).contentTransition(.numericText())
            }
            Text(s.unread == 1 ? "ulæst besked" : "ulæste beskeder").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let subject = s.latestSubject {
                Text(s.latestSender ?? "").font(.caption2.weight(.semibold)).lineLimit(1)
                Text(subject).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
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
            AulaWidgetView(entry: entry)
        }
        .configurationDisplayName("Aula+")
        .description("Børnenes status i dag og ulæste beskeder.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
