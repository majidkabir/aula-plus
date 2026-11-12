import SwiftUI

struct MessagesView: View {
    @Environment(AppModel.self) private var app
    @Environment(DataStore.self) private var data
    @State private var search = ""
    @State private var onlyUnread = false
    @State private var onlyMarked = false
    @State private var composing = false
    @State private var deleting: ThreadSummary?
    @State private var older: [ThreadSummary] = []
    @State private var nextPage = 1
    @State private var loadingOlder = false

    private var threads: [ThreadSummary] {
        var seen = Set<String>()
        let all = ((data.threads.value ?? []) + older).filter { seen.insert($0.id).inserted }
        return all.filter { t in
            if onlyUnread && t.isRead { return false }
            if onlyMarked && t.isMarked != true { return false }
            if let id = app.selectedChildId, let child = app.child(id), !t.regarding.isEmpty,
               !t.regarding.contains(where: { $0.localizedCaseInsensitiveContains(child.firstName) }) {
                return false
            }
            guard !search.isEmpty else { return true }
            return [t.subject, t.sender, t.preview].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.messagesPath) {
            List {
                Section {
                    ChildFilterBar().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    StaleBanner(error: data.threads.error, savedAt: data.threads.savedAt)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                .listSectionSeparator(.hidden)

                ForEach(threads) { t in
                    NavigationLink(value: t) { ThreadRow(thread: t) }
                        .swipeActions(edge: .leading) {
                            Button { Task { await toggleMarked(t) } } label: {
                                Label(t.isMarked == true ? String(localized: "Fjern markering") : String(localized: "Markér"),
                                      systemImage: t.isMarked == true ? "star.slash" : "star.fill")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleting = t } label: { Label("Slet", systemImage: "trash") }
                        }
                }

                if search.isEmpty && !threads.isEmpty {
                    Button {
                        Task { await loadOlder() }
                    } label: {
                        HStack {
                            Spacer()
                            if loadingOlder { ProgressView() } else { Text("Hent ældre beskeder") }
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if threads.isEmpty {
                    if data.threads.isLoading { ProgressView() }
                    else { ContentUnavailableView(onlyUnread ? String(localized: "Ingen ulæste beskeder") : String(localized: "Ingen beskeder"),
                                                  systemImage: "tray") }
                }
            }
            .searchable(text: $search, prompt: String(localized: "Søg i beskeder"))
            .navigationTitle("Beskeder")
            .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Kun ulæste", isOn: $onlyUnread)
                        Toggle("Kun markerede", isOn: $onlyMarked)
                    } label: {
                        Image(systemName: onlyUnread || onlyMarked
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(Text("Filtrér"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel(Text("Ny besked"))
                }
            }
            .sheet(isPresented: $composing) {
                ComposeView { sent in
                    composing = false
                    if sent { Task { await data.threads.refresh() } }
                }
            }
            .confirmationDialog("Slet tråden \"\(deleting?.subject ?? "")\"?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    if let t = deleting { Task { await delete(t) } }
                }
            }
            .refreshable {
                older = []
                nextPage = 1
                await data.threads.refresh()
            }
            .task { await data.threads.load(maxAge: 30) }
        }
    }

    private func toggleMarked(_ t: ThreadSummary) async {
        let new = !(t.isMarked ?? false)
        data.setMarked(threadId: t.id, marked: new)
        do { try await AulaAPI.shared.setMarked(threadId: t.id, marked: new) }
        catch { data.setMarked(threadId: t.id, marked: !new) }
    }

    private func delete(_ t: ThreadSummary) async {
        deleting = nil
        do {
            try await AulaAPI.shared.deleteThread(t.id)
            data.removeThread(t.id)
            older.removeAll { $0.id == t.id }
        } catch {
            await data.threads.refresh()
        }
    }

    private func loadOlder() async {
        guard !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        if let page = try? await AulaAPI.shared.threads(page: nextPage) {
            older += page.threads
            nextPage += 1
        }
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(thread.isRead ? Color.clear : Color.brand)
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.sender.isEmpty ? "Aula" : thread.sender)
                        .font(.subheadline.weight(thread.isRead ? .regular : .bold))
                        .lineLimit(1)
                    Spacer()
                    Text(Fmt.listDate(thread.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if thread.isMarked == true {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                    if thread.isSensitive {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    Text(thread.subject)
                        .font(.subheadline.weight(thread.isRead ? .regular : .semibold))
                        .lineLimit(1)
                }
                if !thread.preview.isEmpty {
                    Text(thread.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !thread.regarding.isEmpty, app.children.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(thread.regarding, id: \.self) { name in
                            let child = app.children.first { name.localizedCaseInsensitiveContains($0.firstName) }
                            ChildTag(name: child?.firstName ?? name,
                                     color: child.map { Palette.color(for: $0.id, in: app.children) } ?? .gray)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(thread.isRead ? "" : String(localized: "Ulæst. ")) + Text("\(thread.sender). \(thread.subject). \(thread.preview)"))
    }
}
