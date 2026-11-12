import SwiftUI

struct MoreView: View {
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.morePath) {
            List {
                Section("Skole") {
                    NavigationLink { PostsList() } label: { row("Opslag", "newspaper.fill", .purple) }
                    NavigationLink { GalleryView() } label: { row("Galleri", "photo.fill.on.rectangle.fill", .pink) }
                    NavigationLink { ImportantDatesView() } label: { row("Vigtige datoer", "star.fill", .yellow) }
                    NavigationLink { DocumentsView() } label: { row("Dokumenter", "doc.text.fill", .blue) }
                    NavigationLink { ContactsView() } label: { row("Kontakter", "person.2.fill", .green) }
                }
                Section("Komme/gå") {
                    ForEach(app.children) { c in
                        NavigationLink { ChildPresenceView(child: c) } label: {
                            HStack(spacing: 12) {
                                ChildAvatar(child: c, size: 28)
                                Text(c.firstName)
                            }
                        }
                    }
                    NavigationLink { VacationRequestsView() } label: {
                        HStack {
                            row("Ferieanmodninger", "sun.max.fill", .orange)
                            let missing = (data.vacationRequests.value ?? []).filter { $0.isMissingAnswer }.count
                            if missing > 0 {
                                Spacer()
                                Text("\(missing)").font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(.red, in: Capsule()).foregroundStyle(.white)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink { NotificationsView() } label: { row("Notifikationer", "bell.fill", .red) }
                    NavigationLink { SettingsView(embedded: true) } label: { row("Profil og indstillinger", "gearshape.fill", .gray) }
                }
            }
            .navigationTitle("Mere")
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .navigationDestination(for: DemoRoute.self) { r in
                switch r {
                case .notifications: NotificationsView()
                case .settings: SettingsView(embedded: true)
                case .gallery: GalleryView()
                case .empty:
                    // Screenshot of the offline + empty states.
                    VStack(spacing: 0) {
                        StaleBanner(error: AulaError.http(503).localizedDescription, savedAt: Date().addingTimeInterval(-3600))
                            .padding()
                        ContentUnavailableView("Ingen opslag", systemImage: "newspaper")
                        Spacer()
                    }
                    .background(Color(.systemGroupedBackground))
                    .navigationTitle("Opslag")
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: icon, color: color)
            Text(title)
        }
    }
}

// MARK: - Gallery

struct GalleryView: View {
    @Environment(DataStore.self) private var data
    static func tint(_ id: Int) -> Color { [Color.pink, .orange, .teal, .purple, .indigo, .green][abs(id) % 6] }
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            StaleBanner(error: data.albums.error, savedAt: data.albums.savedAt).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(data.albums.value ?? []) { album in
                    NavigationLink(value: album) {
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: album.coverURL) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                LinearGradient(colors: [Self.tint(album.id).opacity(0.35), Self.tint(album.id).opacity(0.12)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .overlay(Image(systemName: "photo.on.rectangle.angled").font(.title)
                                        .foregroundStyle(Self.tint(album.id)))
                            }
                            .frame(height: 130)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(album.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            HStack(spacing: 4) {
                                Text(Fmt.listDate(album.date))
                                if let n = album.count { Text("· \(n) billeder") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .overlay {
            if (data.albums.value ?? []).isEmpty {
                if data.albums.isLoading { ProgressView() }
                else { ContentUnavailableView("Ingen albums", systemImage: "photo.on.rectangle") }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Galleri")
        .refreshable { await data.albums.refresh() }
        .task { await data.albums.load(maxAge: 600) }
    }
}

struct AlbumView: View {
    let album: Album
    @Environment(DataStore.self) private var data
    @State private var viewing: Media?
    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 3)]

    private var media: Loadable<[Media]> { data.media(albumId: album.id) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(media.value ?? []) { m in
                    Button { viewing = m } label: {
                        AsyncImage(url: m.thumbURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color(.tertiarySystemFill)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 115)
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            if m.isVideo {
                                Image(systemName: "play.circle.fill").foregroundStyle(.white).padding(4)
                            }
                        }
                    }
                }
            }
        }
        .overlay { if media.value == nil && media.isLoading { ProgressView() } }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await media.refresh() }
        .task { await media.load(maxAge: 3600) }
        .fullScreenCover(item: $viewing) { start in
            MediaViewer(items: media.value ?? [], start: start)
        }
    }
}

struct MediaViewer: View {
    let items: [Media]
    let start: Media
    @State private var current: Int = 0
    @State private var sharing: URL?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                    AsyncImage(url: m.isVideo ? m.thumbURL : (m.fullURL ?? m.thumbURL)) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                    .overlay {
                        if m.isVideo, let url = m.fullURL {
                            Button { openURL(url) } label: {
                                Image(systemName: "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white)
                            }
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle(items.isEmpty ? "" : "\(current + 1) / \(items.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Luk") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let url = sharing {
                        ShareLink(item: url)
                    } else {
                        Button {
                            Task { await prepareShare() }
                        } label: {
                            if busy { ProgressView() } else { Image(systemName: "square.and.arrow.down") }
                        }
                    }
                }
            }
            .onChange(of: current) { _, _ in sharing = nil }
            .onAppear { current = items.firstIndex(of: start) ?? 0 }
        }
    }

    /// Downloads the full image so it can be saved to Photos or shared.
    private func prepareShare() async {
        guard items.indices.contains(current), let url = items[current].fullURL else { return }
        busy = true
        defer { busy = false }
        sharing = try? await AulaAPI.shared.download(url, suggestedName: "aula-\(items[current].id)")
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @Environment(DataStore.self) private var data
    @State private var openingPost: Post?

    var body: some View {
        List {
            StaleBanner(error: data.notifications.error, savedAt: data.notifications.savedAt)
                .listRowSeparator(.hidden)
            ForEach(data.notifications.value ?? []) { n in
                row(n)
            }
        }
        .listStyle(.plain)
        .overlay {
            if (data.notifications.value ?? []).isEmpty {
                if data.notifications.isLoading { ProgressView() }
                else { ContentUnavailableView("Ingen notifikationer", systemImage: "bell.slash") }
            }
        }
        .navigationTitle("Notifikationer")
        .refreshable { await data.notifications.refresh() }
        .task { await data.notifications.load(maxAge: 60) }
        .navigationDestination(item: $openingPost) { PostDetailView(post: $0) }
    }

    @ViewBuilder private func row(_ n: AulaNotification) -> some View {
        let content = NotificationRow(notification: n)
        if let threadId = n.threadId {
            NavigationLink(value: ThreadSummary(id: threadId, subject: n.title, preview: "", sender: "",
                                                date: n.date, isRead: true, isSensitive: false, regarding: [])) { content }
        } else if let albumId = n.albumId {
            NavigationLink(value: Album(id: albumId, title: n.title, date: n.date, coverURL: nil, count: nil)) { content }
        } else if let postId = n.postId {
            Button {
                Task { openingPost = try? await AulaAPI.shared.post(id: postId) }
            } label: { content }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

struct NotificationRow: View {
    let notification: AulaNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: icon, color: tileColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title).font(.subheadline.weight(.medium)).lineLimit(2)
                HStack(spacing: 6) {
                    if let c = notification.childName { Text(c) }
                    Text(Fmt.listDate(notification.date))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var tileColor: Color {
        switch icon {
        case "bubble.left.fill": return .blue
        case "photo.fill": return .pink
        case "newspaper.fill": return .purple
        case "calendar": return .red
        case "figure.walk": return .teal
        default: return .gray
        }
    }

    private var icon: String {
        let m = (notification.module ?? "").lowercased()
        if notification.threadId != nil || m.contains("messag") { return "bubble.left.fill" }
        if notification.albumId != nil || m.contains("gallery") { return "photo.fill" }
        if notification.postId != nil || m.contains("post") { return "newspaper.fill" }
        if m.contains("calendar") { return "calendar" }
        if m.contains("presence") { return "figure.walk" }
        return "bell.fill"
    }
}

// MARK: - Important dates

struct ImportantDatesView: View {
    @Environment(DataStore.self) private var data

    var body: some View {
        List {
            StaleBanner(error: data.importantDates.error, savedAt: data.importantDates.savedAt)
                .listRowSeparator(.hidden)
            ForEach(data.importantDates.value ?? []) { d in
                ImportantDateRow(date: d)
            }
        }
        .listStyle(.plain)
        .overlay {
            if (data.importantDates.value ?? []).isEmpty, !data.importantDates.isLoading {
                ContentUnavailableView("Ingen vigtige datoer", systemImage: "star")
            }
        }
        .navigationTitle("Vigtige datoer")
        .refreshable { await data.importantDates.refresh() }
        .task { await data.importantDates.load(maxAge: 1800) }
    }
}

struct ImportantDateRow: View {
    let date: ImportantDate

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(date.start.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.caption2.weight(.bold)).foregroundStyle(.red)
                Text(date.start.formatted(.dateTime.day())).font(.title3.bold())
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(date.title).font(.subheadline.weight(.semibold))
                Text(date.allDay ? date.start.formatted(.dateTime.weekday(.wide)).capitalized
                                 : date.start.formatted(.dateTime.weekday(.wide).hour().minute()))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
