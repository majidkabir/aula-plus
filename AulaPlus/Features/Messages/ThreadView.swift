import SwiftUI

struct ThreadView: View {
    let thread: ThreadSummary
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app

    @State private var older: [Message] = []       // pages 1…n, newest first
    @State private var nextPage = 1
    @State private var olderExhausted = false
    @State private var loadingOlder = false
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var muted: Bool?
    @State private var confirmLeave = false
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool

    private var page: Loadable<ThreadPage> { data.thread(thread.id) }

    /// Oldest first, like a chat.
    private var messages: [Message] {
        var seen = Set<String>()
        let newestFirst = (page.value?.messages ?? []) + older
        return newestFirst.filter { seen.insert($0.id).inserted }.reversed()
    }

    private func isMine(_ m: Message) -> Bool {
        guard let me = app.session.value?.displayName, !me.isEmpty else { return false }
        return m.sender.localizedCaseInsensitiveCompare(me) == .orderedSame
    }

    private var canLoadOlder: Bool { (page.value?.moreExist ?? false) && !olderExhausted }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text(page.value?.subject.nilIfEmpty ?? thread.subject)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    StaleBanner(error: page.error, savedAt: page.savedAt)
                    SummaryBox(key: "t\(thread.id)", text: messages.map { HTML.plainText($0.html) }.joined(separator: "\n\n"))
                    SourceTasksBanner(source: .thread(thread.id))

                    if canLoadOlder {
                        Button {
                            Task { await loadOlder() }
                        } label: {
                            HStack {
                                Spacer()
                                if loadingOlder { ProgressView() } else { Label("Vis ældre beskeder", systemImage: "arrow.up") }
                                Spacer()
                            }
                        }
                        .font(.subheadline)
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                        let prev = i > 0 ? messages[i - 1] : nil
                        if let d = m.date, prev?.date.map({ !Calendar.week.isDate($0, inSameDayAs: d) }) ?? true {
                            Text(d.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                        }
                        MessageBubble(message: m, isMine: isMine(m),
                                      showSender: prev?.sender != m.sender)
                            .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .themedBackground()
            .overlay {
                if page.value == nil && page.isLoading { ProgressView() }
            }
            .onChange(of: page.value?.messages.first?.id) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { composer }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if thread.subscriptionId != nil {
                        let isMuted = muted ?? thread.isMuted ?? false
                        Button {
                            Task {
                                do { try await data.setMuted(thread, !isMuted); muted = !isMuted }
                                catch { actionError = error.localizedDescription }
                            }
                        } label: {
                            Label(isMuted ? String(localized: "Slå lyd til") : String(localized: "Slå lyd fra"),
                                  systemImage: isMuted ? "bell" : "bell.slash")
                        }
                    }
                    Menu {
                        MoveToFolderItems(thread: thread, currentFolderId: thread.folderId) { target in
                            Task {
                                do { try await data.move(thread, to: target); dismiss() }
                                catch { actionError = error.localizedDescription }
                            }
                        }
                    } label: { Label("Flyt til", systemImage: "folder") }
                    Button(role: .destructive) { confirmLeave = true } label: {
                        Label("Forlad samtalen", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(Text("Flere handlinger"))
            }
        }
        .confirmationDialog("Forlad samtalen?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Forlad", role: .destructive) {
                Task {
                    do { try await data.leave(thread); dismiss() }
                    catch { actionError = error.localizedDescription }
                }
            }
        } message: { Text("Du får ikke flere beskeder i denne tråd.") }
        .alert(actionError ?? "", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .task { await data.folders.load(maxAge: 600) }
        .refreshable { await page.refresh() }
        .task {
            await page.load(maxAge: thread.isRead ? 300 : 0)
            await markReadIfNeeded()
        }
    }

    @ViewBuilder private var composer: some View {
        if page.value?.isOwnMailbox ?? true {
            VStack(spacing: 4) {
                if let sendError {
                    Text(sendError).font(.caption).foregroundStyle(.red)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Skriv et svar", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    Button {
                        Task { await send() }
                    } label: {
                        if sending { ProgressView().frame(width: 34, height: 34) }
                        else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)) }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    .accessibilityLabel(Text("Send"))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            try await AulaAPI.shared.reply(threadId: thread.id, text: text)
            draft = ""
            composerFocused = false
            await page.refresh()
            await data.threads.refresh()
        } catch {
            sendError = String(localized: "Svaret blev ikke sendt: \(error.localizedDescription)")
        }
    }

    private func loadOlder() async {
        guard !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let p = try await AulaAPI.shared.messages(threadId: thread.id, page: nextPage)
            older += p.messages
            nextPage += 1
            olderExhausted = !p.moreExist || p.messages.isEmpty
        } catch {
            olderExhausted = true
        }
    }

    private func markReadIfNeeded() async {
        guard !thread.isRead, let p = page.value, p.isOwnMailbox,
              let newest = p.messages.first else { return }
        do {
            try await AulaAPI.shared.markRead(threadId: thread.id, messageId: newest.id)
            data.markRead(threadId: thread.id)
        } catch {
            // Not fatal: the thread just stays unread in Aula.
        }
    }
}

struct MessageBubble: View {
    let message: Message
    var isMine = false
    var showSender = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 48) }
            else {
                InitialsAvatar(name: message.sender, color: .gray, size: 30)
                    .opacity(showSender ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                if showSender && !isMine {
                    Text(message.sender.isEmpty ? String(localized: "Ukendt") : message.sender)
                        .font(.subheadline.weight(.semibold))
                }
                HTMLText(html: message.html)
                AttachmentList(attachments: message.attachments)
                if let d = message.date {
                    Text(Fmt.time(d))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(isMine ? Color.brand.opacity(0.16) : Color.card,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if !isMine { Spacer(minLength: 24) }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = HTML.plainText(message.html) } label: {
                Label("Kopiér tekst", systemImage: "doc.on.doc")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
