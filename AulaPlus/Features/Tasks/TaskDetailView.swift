import SwiftUI

/// One to-do: what to do, when, and the message or post it came from.
struct TaskDetailView: View {
    let task: ParentTask
    @Environment(DataStore.self) private var data
    @State private var finder = ParentTaskFinder.shared
    @State private var post: Post?
    @State private var loadError: String?
    @State private var addingEvent = false
    @State private var note: String?

    var body: some View {
        let isDone = finder.done.contains(task.id)
        ThemedList {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title).font(.title3.weight(.semibold))
                        .strikethrough(isDone).foregroundStyle(isDone ? .secondary : .primary)
                    if let due = task.due {
                        Label(ParentTaskRow.dueLabel(due), systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(due < Calendar.current.startOfDay(for: .now) && !isDone ? Color.red : Color.orange)
                    }
                }
                .padding(.vertical, 4)
                Button { withAnimation { finder.toggle(task) } } label: {
                    Label(isDone ? "Markér som ikke klaret" : "Markér som klaret",
                          systemImage: isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
                Button {
                    Task {
                        do { try await ReminderMaker.add(task); note = String(localized: "Lagt i Påmindelser") }
                        catch { note = error.localizedDescription }
                    }
                } label: { Label("Tilføj til Påmindelser", systemImage: "checklist") }
                Button { addingEvent = true } label: { Label("Tilføj til Kalender", systemImage: "calendar.badge.plus") }
            }

            Section {
                source
            } header: {
                Text(task.source.isThread ? "Fra beskeden" : "Fra opslaget")
            } footer: {
                Text(task.byAI ? "Fundet af Apple Intelligence. Tjek altid den oprindelige tekst."
                               : "Fundet ud fra ord som \"husk\" og \"medbring\". Tjek altid den oprindelige tekst.")
            }
        }
        .navigationTitle("Husk")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingEvent) { AddToCalendarSheet(event: ReminderMaker.event(for: task), childNames: []) }
        .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .task { await load() }
    }

    @ViewBuilder private var source: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.sourceTitle).font(.headline)
            if let d = task.sourceDate {
                Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
        }
        switch task.source {
        case .thread(let id):
            let page = data.thread(id)
            if let p = page.value {
                // The newest messages (where the task most likely came from), max 3.
                ForEach(p.messages.prefix(3)) { m in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(m.sender).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let d = m.date { Text(Fmt.time(d)).font(.caption2).foregroundStyle(.secondary) }
                        }
                        if m.deleted == true {
                            Text("Beskeden er slettet").italic().foregroundStyle(.secondary)
                        } else {
                            HTMLText(html: m.html)
                            TranslateButton(html: m.html)
                        }
                    }
                    .padding(.vertical, 4)
                }
                NavigationLink(value: thread(id)) { Label("Åbn hele beskeden", systemImage: "bubble.left.and.bubble.right") }
            } else if page.isLoading || loadError == nil {
                ProgressView()
            } else if let loadError {
                Text(loadError).font(.footnote).foregroundStyle(.secondary)
            }
        case .post:
            if let post {
                HTMLText(html: post.html)
                TranslateButton(html: post.html)
                NavigationLink(value: post) { Label("Åbn opslaget", systemImage: "doc.text") }
            } else if let loadError {
                Text(loadError).font(.footnote).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }

    private func thread(_ id: String) -> ThreadSummary {
        data.threads.value?.first { $0.id == id }
            ?? ThreadSummary(id: id, subject: task.sourceTitle, preview: "", sender: "", date: task.sourceDate,
                             isRead: true, isSensitive: false, regarding: [])
    }

    private func load() async {
        switch task.source {
        case .thread(let id):
            let page = data.thread(id)
            await page.load(maxAge: 3600)
            if page.value == nil { loadError = String(localized: "Beskeden kunne ikke hentes.") }
        case .post(let id):
            if let p = data.posts.value?.first(where: { $0.id == id }) { post = p; return }
            do { post = try await AulaAPI.shared.post(id: id) }
            catch { loadError = String(localized: "Opslaget kunne ikke hentes.") }
        }
    }
}

extension ParentTask.Source {
    var isThread: Bool { if case .thread = self { true } else { false } }
}
