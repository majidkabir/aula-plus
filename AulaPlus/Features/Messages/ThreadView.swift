import SwiftUI

struct ThreadView: View {
    let thread: ThreadSummary
    @Environment(DataStore.self) private var data

    @State private var older: [Message] = []       // pages 1…n, newest first
    @State private var nextPage = 1
    @State private var olderExhausted = false
    @State private var loadingOlder = false
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @FocusState private var composerFocused: Bool

    private var page: Loadable<ThreadPage> { data.thread(thread.id) }

    /// Oldest first, like a chat.
    private var messages: [Message] {
        var seen = Set<String>()
        let newestFirst = (page.value?.messages ?? []) + older
        return newestFirst.filter { seen.insert($0.id).inserted }.reversed()
    }

    private var canLoadOlder: Bool { (page.value?.moreExist ?? false) && !olderExhausted }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(page.value?.subject.nilIfEmpty ?? thread.subject)
                        .font(.title2.bold())
                        .padding(.bottom, 4)
                    StaleBanner(error: page.error, savedAt: page.savedAt)

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

                    ForEach(messages) { m in
                        MessageBubble(message: m).id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .overlay {
                if page.value == nil && page.isLoading { ProgressView() }
            }
            .onChange(of: page.value?.messages.first?.id) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { composer }
        }
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.sender.isEmpty ? String(localized: "Ukendt") : message.sender)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let d = message.date {
                    Text(d.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HTMLText(html: message.html)
            AttachmentList(attachments: message.attachments)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button { UIPasteboard.general.string = HTML.plainText(message.html) } label: {
                Label("Kopiér tekst", systemImage: "doc.on.doc")
            }
        }
    }
}
