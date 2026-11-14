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
    @State private var noMoreOlder = false
    @State private var actionError: String?
    /// nil = the inbox.
    @State private var folderId: Int?
    @State private var showDrafts = false
    @State private var managingFolders = false
    @State private var editingAutoReply = false
    @State private var openDraft: MessageDraft?
    @State private var serverResults: [ThreadSummary] = []
    @State private var searching = false

    private var source: Loadable<[ThreadSummary]> { data.threads(in: folderId) }

    private var folderTitle: String {
        if showDrafts { return String(localized: "Kladder") }
        guard let folderId, let f = data.folders.value?.first(where: { $0.id == folderId }) else {
            return String(localized: "Beskeder")
        }
        return f.isDeleted ? String(localized: "Slettet post") : f.name
    }

    private var threads: [ThreadSummary] {
        var seen = Set<String>()
        let pages = (source.value ?? []) + (folderId == nil ? older : [])
        // While searching, Aula's own full-text results come after the local matches.
        let extra = search.isEmpty ? [] : serverResults
        let all = (pages + extra).filter { seen.insert($0.id).inserted }
        return all.filter { t in
            if serverResults.contains(where: { $0.id == t.id }) && !search.isEmpty { return true }
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
            list
            .sheet(isPresented: $managingFolders) { FoldersView() }
            .sheet(isPresented: $editingAutoReply) { AutoReplyView() }
            .sheet(item: $openDraft) { d in
                ComposeView(draft: d) { sent in
                    openDraft = nil
                    if sent { Task { await data.threads.refresh() } }
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
                noMoreOlder = false
                await source.refresh()
                await data.folders.refresh()
            }
            .task { await data.threads.load(maxAge: 30) }
            .task { await data.folders.load(maxAge: 600) }
            .task(id: folderId) { if folderId != nil { await source.load(maxAge: 60) } }
            // Threads from older pages aren't in the cache: keep their read state in step here.
            .onChange(of: app.messagesPath) { _, path in
                if let t = path.last { updateOlder(t.id) { $0.isRead = true } }
            }
            .alert(actionError ?? "", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var list: some View {
    ThemedList(rowBackground: .clear) {
        listContent
    }
    .listStyle(.plain)
    .overlay {
        if showDrafts && data.drafts.isEmpty {
            ContentUnavailableView("Ingen kladder", systemImage: "doc.text")
        } else if !showDrafts && threads.isEmpty {
            if source.isLoading || searching { ProgressView() }
            else { ContentUnavailableView(onlyUnread ? String(localized: "Ingen ulæste beskeder") : String(localized: "Ingen beskeder"),
                                          systemImage: "tray") }
        }
    }
    .searchable(text: $search, prompt: String(localized: "Søg i alle beskeder"))
    .task(id: search) { await searchAula() }
    .navigationTitle(folderTitle)
    .toolbarTitleMenu {
        folderMenu
    }
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
    }

    @ViewBuilder private var listContent: some View {
        Section {
            ChildFilterBar().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            StaleBanner(error: data.threads.error, savedAt: data.threads.savedAt)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        .listSectionSeparator(.hidden)

        if showDrafts {
            ForEach(data.drafts) { d in
                Button { openDraft = d } label: { DraftRow(draft: d) }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 26, bottom: 12, trailing: 24))
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.card)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { data.deleteDraft(d.id) } label: { Label("Slet", systemImage: "trash") }
                    }
            }
        }
        ForEach(showDrafts ? [] : threads) { t in threadCell(t) }

        if search.isEmpty && folderId == nil && !showDrafts && !threads.isEmpty && !noMoreOlder {
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

    @ViewBuilder private var folderMenu: some View {
        Button { showDrafts = false; folderId = nil } label: { Label("Indbakke", systemImage: "tray") }
        Button { showDrafts = true } label: {
            Label(data.drafts.isEmpty ? String(localized: "Kladder") : String(localized: "Kladder (\(data.drafts.count))"),
                  systemImage: "doc.text")
        }
        ForEach(data.folders.value ?? []) { f in
            Button { showDrafts = false; folderId = f.id } label: {
                Label(f.isDeleted ? String(localized: "Slettet post") : f.name, systemImage: f.isDeleted ? "trash" : "folder")
            }
        }
        Divider()
        Button { managingFolders = true } label: { Label("Administrér mapper", systemImage: "folder.badge.gearshape") }
        Button { editingAutoReply = true } label: { Label("Autosvar", systemImage: "arrowshape.turn.up.left.circle") }
    }

    private func threadCell(_ t: ThreadSummary) -> some View {
        NavigationLink(value: t) { ThreadRow(thread: t) }
            // Each thread on its own rounded card.
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 26, bottom: 12, trailing: 24))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(t.isRead ? Color.card : Color.brand.opacity(0.10))
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.card))
                    .padding(.horizontal, 12).padding(.vertical, 4)
            )
            .swipeActions(edge: .leading) {
                Button { Task { await toggleMarked(t) } } label: {
                    Label(t.isMarked == true ? String(localized: "Fjern markering") : String(localized: "Markér"),
                          systemImage: t.isMarked == true ? "star.slash" : "star.fill")
                }
                .tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deleting = t } label: { Label("Slet", systemImage: "trash") }
                Button { Task { await toggleMuted(t) } } label: {
                    Label(t.isMuted == true ? String(localized: "Slå lyd til") : String(localized: "Slå lyd fra"),
                          systemImage: t.isMuted == true ? "bell" : "bell.slash")
                }
                .tint(.indigo)
            }
            .contextMenu {
                Button { Task { await toggleMarked(t) } } label: {
                    Label(t.isMarked == true ? String(localized: "Fjern markering") : String(localized: "Markér"),
                          systemImage: t.isMarked == true ? "star.slash" : "star")
                }
                if t.subscriptionId != nil {
                    Button { Task { await toggleMuted(t) } } label: {
                        Label(t.isMuted == true ? String(localized: "Slå lyd til") : String(localized: "Slå lyd fra"),
                              systemImage: t.isMuted == true ? "bell" : "bell.slash")
                    }
                }
                Menu {
                    MoveToFolderItems(thread: t, currentFolderId: folderId) { target in
                        Task { await move(t, to: target) }
                    }
                } label: { Label("Flyt til", systemImage: "folder") }
                Button(role: .destructive) { deleting = t } label: { Label("Slet", systemImage: "trash") }
            }
    }

    private func updateOlder(_ id: String, _ change: (inout ThreadSummary) -> Void) {
        if let i = older.firstIndex(where: { $0.id == id }) { change(&older[i]) }
    }

    private func toggleMarked(_ t: ThreadSummary) async {
        let new = !(t.isMarked ?? false)
        data.setMarked(threadId: t.id, marked: new)
        updateOlder(t.id) { $0.isMarked = new }
        do { try await AulaAPI.shared.setMarked(threadId: t.id, marked: new) }
        catch {
            data.setMarked(threadId: t.id, marked: !new)
            updateOlder(t.id) { $0.isMarked = !new }
        }
    }

    private func toggleMuted(_ t: ThreadSummary) async {
        let new = !(t.isMuted ?? false)
        do {
            try await data.setMuted(t, new)
            updateOlder(t.id) { $0.isMuted = new }
        } catch {
            actionError = String(localized: "Ikke ændret: \(error.localizedDescription)")
        }
    }

    private func move(_ t: ThreadSummary, to target: Int?) async {
        do {
            try await data.move(t, to: target)
            older.removeAll { $0.id == t.id }
        } catch {
            actionError = String(localized: "Ikke flyttet: \(error.localizedDescription)")
        }
    }

    /// Aula's full-text search (subjects and message text in every folder), after a short pause in typing.
    private func searchAula() async {
        let term = search.trimmingCharacters(in: .whitespaces)
        guard term.count >= 3, !Demo.isOn else { serverResults = []; return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        guard let s = try? await AulaAPI.shared.bootstrap() else { return }
        let codes = Array(Set(s.children.compactMap(\.institutionCode))).sorted()
        let found = (try? await AulaAPI.shared.searchMessages(term, childIds: s.children.map(\.id), institutionCodes: codes)) ?? []
        if !Task.isCancelled { serverResults = found }
    }

    private func delete(_ t: ThreadSummary) async {
        deleting = nil
        do {
            try await AulaAPI.shared.deleteThread(t.id)
            data.removeThread(t.id)
            older.removeAll { $0.id == t.id }
        } catch {
            actionError = String(localized: "Ikke slettet: \(error.localizedDescription)")
            await data.threads.refresh()
        }
    }

    private func loadOlder() async {
        guard !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await AulaAPI.shared.threads(page: nextPage)
            older += page.threads
            nextPage += 1
            noMoreOlder = !page.more || page.threads.isEmpty
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InitialsAvatar(name: thread.sender.isEmpty ? "Aula" : thread.sender,
                           color: Palette.stable(for: thread.sender), size: 40)
                .overlay(alignment: .topTrailing) {
                    if !thread.isRead {
                        Circle().fill(Color.brand).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color.card, lineWidth: 2))
                            .offset(x: 2, y: -2)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.sender.isEmpty ? "Aula" : thread.sender)
                        .font(.subheadline.weight(thread.isRead ? .semibold : .heavy))
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
