import SwiftUI

/// Posts list without its own NavigationStack (pushed from Mere).
struct PostsList: View {
    @Environment(DataStore.self) private var data
    @State private var search = ""

    private var posts: [Post] {
        let all = data.posts.value ?? []
        guard !search.isEmpty else { return all }
        return all.filter { p in
            [p.title, p.author, HTML.plainText(p.html)].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                StaleBanner(error: data.posts.error, savedAt: data.posts.savedAt)
                ForEach(posts) { post in
                    NavigationLink(value: post) { PostCard(post: post, compact: true) }
                        .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if posts.isEmpty {
                if data.posts.isLoading { ProgressView() }
                else { ContentUnavailableView("Ingen opslag", systemImage: "newspaper") }
            }
        }
        .searchable(text: $search, prompt: String(localized: "Søg i opslag"))
        .navigationTitle("Opslag")
        .refreshable { await data.posts.refresh() }
        .task { await data.posts.load(maxAge: 300) }
    }
}

struct PostCard: View {
    let post: Post
    var compact = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    if post.isImportant {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    }
                    Text(post.title).font(.headline).lineLimit(compact ? 2 : nil)
                }
                HStack {
                    Text(post.author)
                    Spacer()
                    Text(Fmt.listDate(post.date))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if compact {
                    Text(HTML.plainText(post.html))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    if !post.attachments.isEmpty {
                        Label("\(post.attachments.count)", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct PostDetailView: View {
    let post: Post
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var posting = false
    @State private var commentError: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(post.title).font(.title2.bold())
                HStack {
                    Text(post.author)
                    Spacer()
                    if let d = post.date { Text(d.formatted(date: .abbreviated, time: .shortened)) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Divider()
                HTMLText(html: post.html)
                AttachmentList(attachments: post.attachments)
                Divider().padding(.vertical, 4)
                if post.canComment == true {
                HStack(alignment: .bottom) {
                    TextField("Skriv en kommentar", text: $newComment, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(8)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    Button {
                        Task { await postComment() }
                    } label: {
                        if posting { ProgressView() } else { Image(systemName: "paperplane.fill") }
                    }
                    .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || posting)
                }
                if let commentError { Text(commentError).font(.caption).foregroundStyle(.red) }
                }
                if !comments.isEmpty {
                    Text("Kommentarer (\(comments.count))").font(.headline)
                    ForEach(comments) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(c.author).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(Fmt.listDate(c.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            HTMLText(html: c.html)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { comments = (try? await AulaAPI.shared.comments(postId: post.id)) ?? [] }
    }

    private func postComment() async {
        guard let me = app.session.value?.guardianProfileIds?.first else {
            commentError = String(localized: "Kunne ikke finde din profil. Træk ned for at opdatere.")
            return
        }
        posting = true
        commentError = nil
        defer { posting = false }
        do {
            try await AulaAPI.shared.addComment(postId: post.id, text: newComment, asProfile: me)
            newComment = ""
            comments = (try? await AulaAPI.shared.comments(postId: post.id)) ?? comments
        } catch {
            commentError = String(localized: "Ikke sendt: \(error.localizedDescription)")
        }
    }
}
