import SwiftUI

/// "Skal gøres" on the Today screen.
struct ParentTasksCard: View {
    @State private var finder = ParentTaskFinder.shared

    var body: some View {
        let open = finder.open
        if finder.isEnabled && (!open.isEmpty || finder.progress != nil) {
            HStack {
                SectionTitle(title: "Skal gøres", systemImage: "checklist", count: open.isEmpty ? nil : open.count, tint: .orange)
                Spacer()
                NavigationLink(value: Route.tasks) { Text("Vis alle").font(.subheadline.weight(.semibold)) }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(open.prefix(4)) { t in ParentTaskRow(task: t) }
                if let p = finder.progress {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Læser beskeder \(p.0 + 1) af \(p.1) …").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .cardStyle()
        }
    }
}

/// Every task, grouped by when it's due.
struct ParentTasksView: View {
    @State private var finder = ParentTaskFinder.shared

    var body: some View {
        let open = finder.open
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let groups: [(LocalizedStringKey, [ParentTask])] = [
            ("For sent", open.filter { ($0.due ?? .distantFuture) < today }),
            ("I dag", open.filter { $0.due.map { $0 >= today && $0 < tomorrow } ?? false }),
            ("Kommende", open.filter { ($0.due ?? .distantPast) >= tomorrow }),
            ("Uden dato", open.filter { $0.due == nil }),
        ]
        ThemedList {
            ForEach(groups.indices, id: \.self) { i in
                if !groups[i].1.isEmpty {
                    Section(groups[i].0) { ForEach(groups[i].1) { ParentTaskRow(task: $0) } }
                }
            }
            if !finder.finished.isEmpty {
                Section("Klaret") { ForEach(finder.finished) { ParentTaskRow(task: $0) } }
            }
            Section {
                EmptyView()
            } footer: {
                Text(ParentTaskFinder.usesAI
                     ? "Fundet af Apple Intelligence på telefonen. Beskederne sendes ingen steder hen. Tjek altid den oprindelige besked."
                     : "Fundet ud fra nøgleord som \"husk\", \"medbring\" og \"senest\". Med Apple Intelligence (iPhone 15 Pro eller nyere) bliver det mere præcist. Alt sker på telefonen.")
            }
        }
        .overlay {
            if open.isEmpty && finder.finished.isEmpty {
                ContentUnavailableView("Intet at gøre", systemImage: "checkmark.circle",
                                       description: Text("Når en besked eller et opslag beder dig om noget, står det her."))
            }
        }
        .navigationTitle("Skal gøres")
    }
}

struct ParentTaskRow: View {
    let task: ParentTask
    @State private var finder = ParentTaskFinder.shared
    @Environment(DataStore.self) private var data

    var body: some View {
        let isDone = finder.done.contains(task.id)
        HStack(alignment: .top, spacing: 12) {
            Button { withAnimation { finder.toggle(task) } } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? Text("Markér som ikke klaret") : Text("Markér som klaret"))
            source {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let due = task.due {
                            Label(Self.dueLabel(due), systemImage: "calendar")
                                .foregroundStyle(due < Calendar.current.startOfDay(for: .now) && !isDone ? Color.red : Color.orange)
                        }
                        Text(task.sourceTitle).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
    }

    /// Opens the message or post the task came from.
    @ViewBuilder private func source<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        switch task.source {
        case .thread(let id):
            let t = data.threads.value?.first { $0.id == id }
                ?? ThreadSummary(id: id, subject: task.sourceTitle, preview: "", sender: "", date: task.sourceDate,
                                 isRead: true, isSensitive: false, regarding: [])
            NavigationLink(value: t) { content() }.buttonStyle(.plain)
        case .post(let id):
            if let p = data.posts.value?.first(where: { $0.id == id }) {
                NavigationLink(value: p) { content() }.buttonStyle(.plain)
            } else {
                content()
            }
        }
    }

    static func dueLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "I dag") }
        if cal.isDateInTomorrow(d) { return String(localized: "I morgen") }
        if cal.isDateInYesterday(d) { return String(localized: "I går") }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: d).day, (0..<7).contains(days) {
            return d.formatted(.dateTime.weekday(.wide)).capitalized
        }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// Tasks found in one message or post, shown on top of it.
struct SourceTasksBanner: View {
    let source: ParentTask.Source
    @State private var finder = ParentTaskFinder.shared

    var body: some View {
        let list = finder.tasks(for: source)
        if finder.isEnabled && !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Skal gøres", systemImage: "checklist").font(.caption.weight(.bold)).foregroundStyle(.orange)
                ForEach(list) { t in
                    let isDone = finder.done.contains(t.id)
                    Button { withAnimation { finder.toggle(t) } } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isDone ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(.subheadline.weight(.semibold)).strikethrough(isDone)
                                    .multilineTextAlignment(.leading)
                                if let due = t.due {
                                    Text(ParentTaskRow.dueLabel(due)).font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
