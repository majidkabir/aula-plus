import SwiftUI

/// Posts list without its own NavigationStack (pushed from Mere).
struct PostsList: View {
    @Environment(DataStore.self) private var data
    @State private var search = ""
    @State private var filter: PostFilter = .all
    /// Posts for a filter other than "Alle", fetched from Aula like aula.dk does.
    @State private var filtered: Loadable<[Post]>?

    private var source: Loadable<[Post]> { filter == .all ? data.posts : (filtered ?? data.posts) }

    private var posts: [Post] {
        let all = source.value ?? []
        guard !search.isEmpty else { return all }
        return all.filter { p in
            [p.title, p.author, HTML.plainText(p.html)].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                filterBar.padding(.horizontal, -16)
                StaleBanner(error: source.error, savedAt: source.savedAt)
                ForEach(posts) { post in
                    NavigationLink(value: post) { PostCard(post: post, compact: true) }
                        .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .themedBackground()
        .overlay {
            if posts.isEmpty {
                if source.isLoading { ProgressView() }
                else {
                    ContentUnavailableView(filter == .saved ? "Ingen gemte opslag" : "Ingen opslag",
                                           systemImage: filter == .saved ? "bookmark" : "newspaper")
                }
            }
        }
        .searchable(text: $search, prompt: String(localized: "Søg i opslag"))
        .navigationTitle("Opslag")
        .refreshable { await source.refresh() }
        .task { await data.posts.load(maxAge: 300) }
        .task(id: filter) {
            guard filter != .all else { filtered = nil; return }
            let f = filter
            let l = Loadable<[Post]>(key: "posts-\(f.rawValue)") {
                let s = try await AulaAPI.shared.bootstrap()
                return try await AulaAPI.shared.posts(institutionProfileIds: s.institutionProfileIds, filter: f)
            }
            filtered = l
            await l.load(maxAge: 120)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PostFilter.allCases) { f in
                    Button { filter = f } label: {
                        Text(f.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(filter == f ? Color.accentColor : Color.card, in: Capsule())
                            .foregroundStyle(filter == f ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct PostCard: View {
    let post: Post
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                InitialsAvatar(name: post.author, color: .purple, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.author).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(Fmt.listDate(post.date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if post.isBookmarked == true {
                    Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Gemt"))
                }
                if post.isImportant {
                    Label("Vigtigt", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.12), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            Text(post.title).font(.headline).lineLimit(compact ? 2 : nil)
            if compact {
                Text(HTML.plainText(post.html))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                let photos = post.attachments.compactMap(\.media)
                if !photos.isEmpty {
                    // A preview only: tapping the card opens the post, where the photos open full screen.
                    PhotoGrid(photos: photos, maxShown: 3).allowsHitTesting(false)
                }
                let files = post.attachments.count - photos.count
                if files > 0 {
                    Label("\(files)", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

struct PostDetailView: View {
    let post: Post
    @State private var saved: Bool?
    @State private var saveError: String?
    @Environment(DataStore.self) private var data
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var posting = false
    @State private var commentError: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              VStack(alignment: .leading, spacing: 14) {
                if post.isImportant {
                    Label("Vigtigt", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(.red)
                }
                Text(post.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    InitialsAvatar(name: post.author, color: .purple, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(post.author).font(.subheadline.weight(.semibold))
                        if let d = post.date {
                            Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                HTMLText(html: post.html)
                AttachmentList(attachments: post.attachments)
              }
              .cardStyle()
                if post.canComment == true {
                HStack(alignment: .bottom) {
                    TextField("Skriv en kommentar", text: $newComment, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.card, in: Capsule())
                    Button {
                        Task { await postComment() }
                    } label: {
                        if posting { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)) }
                    }
                    .accessibilityLabel(Text("Send"))
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
                        .cardStyle(padding: 12)
                    }
                }
            }
            .padding()
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let on = saved ?? post.isBookmarked ?? false
                Button { Task { await toggleSaved(!on) } } label: {
                    Image(systemName: on ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(on ? Text("Fjern fra gemte") : Text("Gem opslag"))
            }
        }
        .alert("Kunne ikke gemme", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "") }
        .task { comments = (try? await AulaAPI.shared.comments(postId: post.id)) ?? [] }
    }

    private func toggleSaved(_ on: Bool) async {
        let before = saved
        saved = on
        do { try await data.setBookmarked(post, on) }
        catch {
            saved = before
            saveError = error.localizedDescription
        }
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
