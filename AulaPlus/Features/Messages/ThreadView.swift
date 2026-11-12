import SwiftUI

struct ThreadView: View {
    let thread: ThreadSummary
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app

    private var page: Loadable<ThreadPage> { data.thread(thread.id) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(page.value?.subject.nilIfEmpty ?? thread.subject)
                        .font(.title2.bold())
                        .padding(.bottom, 4)
                    StaleBanner(error: page.error, savedAt: page.savedAt)

                    if page.value?.moreExist == true {
                        Text("Ældre beskeder i tråden vises ikke endnu.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    ForEach(messages) { m in
                        MessageBubble(message: m).id(m.id)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .overlay {
                if page.value == nil && page.isLoading { ProgressView() }
            }
            .onChange(of: messages.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await page.refresh() }
        .task {
            await page.load(maxAge: thread.isRead ? 300 : 0)
            await markReadIfNeeded()
        }
    }

    /// Oldest first, like a chat.
    private var messages: [Message] { (page.value?.messages ?? []).reversed() }

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
                Text(message.sender.isEmpty ? "Ukendt" : message.sender)
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
    }
}
