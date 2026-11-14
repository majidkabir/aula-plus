import SwiftUI

struct MoreView: View {
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.morePath) {
            ThemedList {
                Section("Skole") {
                    NavigationLink(value: Route.posts) { row("Opslag", "newspaper.fill", .purple) }
                    NavigationLink(value: Route.gallery) {
                        HStack {
                            row("Galleri", "photo.fill.on.rectangle.fill", .pink)
                            Spacer()
                            NewBadge(count: data.newGalleryCount)
                        }
                    }
                    NavigationLink(value: Route.importantDates) { row("Vigtige datoer", "star.fill", .yellow) }
                    NavigationLink(value: Route.birthdays) { row("Fødselsdage", "birthday.cake.fill", .pink) }
                    NavigationLink(value: Route.documents) { row("Dokumenter", "doc.text.fill", .blue) }
                    NavigationLink(value: Route.contacts) { row("Kontakter", "person.2.fill", .green) }
                }
                Section("Komme/gå") {
                    NavigationLink(value: Route.presence) { row("Tider, hentning og åbningstider", "clock.fill", .teal) }
                    ForEach(app.children) { c in
                        NavigationLink(value: Route.child(c)) {
                            HStack(spacing: 12) {
                                ChildAvatar(child: c, size: 28)
                                Text(c.firstName)
                            }
                        }
                    }
                    NavigationLink(value: Route.vacations) {
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
                if let tools = app.session.value?.widgetLinks, !tools.isEmpty {
                    Section("Værktøjer i Aula") {
                        ForEach(tools) { t in
                            Link(destination: t.url) {
                                HStack {
                                    HStack(spacing: 12) {
                                        IconTile(systemImage: "square.grid.2x2.fill", color: .indigo)
                                        Text(verbatim: t.name)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Section {
                    NavigationLink(value: Route.notifications) { row("Notifikationer", "bell.fill", .red) }
                    NavigationLink(value: Route.profile) { row("Min profil", "person.crop.circle.fill", .purple) }
                    NavigationLink(value: Route.settings) { row("Indstillinger", "gearshape.fill", .gray) }
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Mere")
            .task { await data.notifications.load(maxAge: 300) }
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
            .navigationDestination(for: Album.self) { AlbumView(album: $0) }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private func row(_ title: LocalizedStringKey, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: icon, color: color)
            Text(title)
        }
    }
}

/// The screen for each `Route`, shared by the Today and More tabs.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .posts: PostsList()
        case .gallery: GalleryView()
        case .importantDates: ImportantDatesView()
        case .documents: DocumentsView()
        case .contacts: ContactsView()
        case .vacations: VacationRequestsView()
        case .notifications: NotificationsView()
        case .settings: SettingsView(embedded: true)
        case .tasks: ParentTasksView()
        case .profile: MyProfileView()
        case .birthdays: BirthdaysView()
        case .presence: PresenceHubView()
        case .contact(let c): ContactDetailView(contact: c)
        case .child(let c): ChildPresenceView(child: c)
        case .document(let d): DocumentDetailView(doc: d)
        case .empty:
            // Screenshot of the offline + empty states.
            VStack(spacing: 0) {
                StaleBanner(error: AulaError.http(503).localizedDescription, savedAt: Date().addingTimeInterval(-3600))
                    .padding()
                ContentUnavailableView("Ingen opslag", systemImage: "newspaper")
                Spacer()
            }
            .themedBackground()
            .navigationTitle("Opslag")
        }
    }
}

// MARK: - Gallery

/// The gallery as its own tab (shown instead of the week plan when Aula has none).
struct PhotosTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.photosPath) {
            GalleryView()
                .navigationDestination(for: Album.self) { AlbumView(album: $0) }
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

/// Red "3 nye" capsule for new photos.
struct NewBadge: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text("\(count) nye")
                .font(.caption2.bold())
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.red, in: Capsule())
                .foregroundStyle(.white)
                .accessibilityLabel(Text("\(count) nye billeder"))
        }
    }
}

struct GalleryView: View {
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app
    static func tint(_ id: Int) -> Color { [Color.pink, .orange, .teal, .purple, .indigo, .green][abs(id) % 6] }
    // Top-aligned: a two-line title must not push the neighbouring tile down.
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            StaleBanner(error: data.albums.error, savedAt: data.albums.savedAt).padding(.horizontal)
            if !app.children.isEmpty {
                Text("Billeder af dine børn")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(app.children) { child in
                        ChildAlbumTile(child: child)
                    }
                }
                .padding(.horizontal)
                if !(data.albums.value ?? []).isEmpty {
                    Text("Albums")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal).padding(.top, 16)
                }
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(data.albums.value ?? []) { album in
                    NavigationLink(value: album) {
                        AlbumTile(title: album.title, coverKey: "c\(album.id)", coverURL: album.coverURL, tint: Self.tint(album.id),
                                  newCount: data.newCount(in: album)) {
                            Text(Fmt.listDate(album.date))
                            if let n = album.count { Text("· \(n) billeder") }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .overlay {
            if (data.albums.value ?? []).isEmpty && app.children.isEmpty {
                if data.albums.isLoading { ProgressView("Henter albums …") }
                else { ContentUnavailableView("Ingen albums", systemImage: "photo.on.rectangle") }
            }
        }
        .themedBackground()
        .navigationTitle("Galleri")
        .toolbar {
            if data.albums.isLoading && data.albums.value != nil {
                ToolbarItem(placement: .primaryAction) { ProgressView().accessibilityLabel(Text("Opdaterer")) }
            }
        }
        .refreshable {
            async let a: Void = data.albums.refresh()
            async let n: Void = data.notifications.refresh()
            _ = await (a, n)
        }
        .task {
            async let a: Void = data.albums.load(maxAge: 600)
            async let n: Void = data.notifications.load(maxAge: 60)
            _ = await (a, n)
        }
    }
}

/// "Billeder af Emma": every photo the child is tagged in. Cover = the newest of them.
private struct ChildAlbumTile: View {
    let child: Child
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app

    var body: some View {
        let album = Album.tagged(child)
        let media = data.media(album: album)
        NavigationLink(value: album) {
            AlbumTile(title: album.title, coverKey: media.value?.first.map { "t\($0.id)" } ?? "", coverURL: media.value?.first?.thumbURL,
                      tint: Palette.color(for: child.id, in: app.children), newCount: data.newCount(in: album),
                      placeholder: { ChildAvatar(child: child, size: 64) }) {
                if let n = media.value?.count {
                    if media.isPartial { Text("\(n) billeder …") } else { Text("\(n) billeder") }
                }
                else if media.isLoading { Text("Henter …") }
                else { Text("Alle billeder af \(child.firstName)") }
            }
        }
        .buttonStyle(.plain)
        // No load here: fetching every child's photos would slow down the album the user opens.
    }
}

struct AlbumTile<Subtitle: View, Placeholder: View>: View {
    let title: String
    var coverKey: String = ""
    let coverURL: URL?
    let tint: Color
    let newCount: Int
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var subtitle: () -> Subtitle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Fixed tile first, photo filled inside it: a wide photo can't widen the
            // column or reach into the neighbour's tap area.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .overlay {
                    CachedImage(key: coverKey.isEmpty ? (coverURL?.path ?? "") : coverKey, url: coverURL, maxPixel: 600) {
                        LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(placeholder())
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topTrailing) { NewBadge(count: newCount).padding(6) }
            Text(title).font(.headline.weight(.heavy)).lineLimit(2)
            HStack(spacing: 4) { subtitle() }
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension AlbumTile where Placeholder == AlbumPlaceholderIcon {
    init(title: String, coverKey: String = "", coverURL: URL?, tint: Color, newCount: Int, @ViewBuilder subtitle: @escaping () -> Subtitle) {
        self.init(title: title, coverKey: coverKey, coverURL: coverURL, tint: tint, newCount: newCount,
                  placeholder: { AlbumPlaceholderIcon(tint: tint) }, subtitle: subtitle)
    }
}

struct AlbumPlaceholderIcon: View {
    let tint: Color
    var body: some View {
        Image(systemName: "photo.on.rectangle.angled").font(.title).foregroundStyle(tint)
    }
}

/// "Henter billeder … 48 af 429" with a bar; without a known total just a spinner and "Opdaterer …".
struct LoadProgress: View {
    let loaded: Int
    let expected: Int?

    var body: some View {
        if let expected, expected > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(min(loaded, expected)), total: Double(expected))
                Text("Henter billeder … \(loaded) af \(expected)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Opdaterer …").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AlbumView: View {
    let album: Album
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app
    @State private var viewing: Media?
    @State private var filter: Filter = .all
    /// Photos that were new when the album was opened. Kept for this visit after Aula is told they're seen.
    @State private var newIds: Set<Int> = []
    @State private var refreshedForExpiredURLs = false
    @State private var refreshedForDates = false
    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 3)]

    enum Filter: Hashable { case all, new, child(Int) }

    private var media: Loadable<[Media]> { data.media(album: album) }
    private var faces: FaceIndex { FaceIndex.shared }
    /// In a child's own album: the tagged photos plus those found by face on the phone.
    private var all: [Media] {
        let list = media.value ?? []
        guard let childId = album.childId else { return list }
        let ids = Set(list.map(\.id))
        return list + faces.found(childId).filter { !ids.contains($0.id) }.map(data.freshest)
    }

    private var shown: [Media] {
        switch filter {
        case .all: all
        case .new: all.filter { newIds.contains($0.id) }
        case .child(let id): all.filter { faces.shows($0, id) }
        }
    }

    var body: some View {
        ScrollView {
            StaleBanner(error: media.error, savedAt: media.savedAt).padding(.horizontal)
            if media.isLoading && media.value != nil {
                LoadProgress(loaded: all.count, expected: media.isPartial ? (media.expected ?? album.count) : nil)
                    .padding(.horizontal).padding(.top, 6)
            }
            filterBar
            faceBar
            // Grouped by day, newest first, like the Photos app.
            LazyVGrid(columns: columns, spacing: 3, pinnedViews: [.sectionHeaders]) {
                ForEach(PhotoDay.group(shown)) { day in
                    Section {
                        ForEach(day.items) { m in
                            Button { viewing = m } label: { tile(m) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        PhotoDayHeader(day: day)
                    }
                }
            }
            if !all.isEmpty && shown.isEmpty {
                ContentUnavailableView("Ingen billeder", systemImage: "photo",
                                       description: Text("Ingen billeder passer til filteret."))
            }
        }
        .overlay {
            if media.value == nil && media.isLoading { ProgressView("Henter billeder …") }
            else if media.value == nil, let error = media.error {
                ContentUnavailableView("Kunne ikke hente", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if media.value?.isEmpty == true {
                ContentUnavailableView("Ingen billeder", systemImage: "photo")
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await media.refresh() }
        .task {
            // Photos first; the "new" markers load alongside instead of before them.
            async let notices: Void = data.notifications.load(maxAge: 120)
            // The cached list shows at once; it's refreshed in the background after 15 minutes,
            // when Aula's signed photo URLs may have expired.
            await media.load(maxAge: 900)
            await notices
            // A new-photo notice means the cached list may be missing it.
            if data.newCount(in: album) > 0, media.savedAt.map({ $0 < .now.addingTimeInterval(-30) }) ?? false {
                await media.refresh()
            } else if !refreshedForDates, (media.value ?? []).contains(where: { $0.date == nil }) {
                // Saved by an older version without photo dates: fetch again so the days show.
                refreshedForDates = true
                await media.refresh()
            }
            let ids = Set(all.map(\.id))
            newIds.formUnion(data.newMediaIds.intersection(ids))
            await data.markSeen(album, media: all)
            // Face finding keeps going in the background when the album is closed.
            let photos = media.value ?? []
            let children = app.children
            let data = data
            Task { await FaceFinding.learnAndScan(photos, children: children, data: data) }
        }
        .fullScreenCover(item: $viewing) { start in
            MediaViewer(items: PhotoDay.group(shown).flatMap(\.items), start: start, children: app.children, newIds: newIds)
        }
    }

    @ViewBuilder private var filterBar: some View {
        let newCount = all.filter { newIds.contains($0.id) }.count
        // In a child's own album every photo is that child's: no child chips there.
        let kids: [(Child, Int)] = album.childId != nil ? [] : app.children.compactMap { c in
            let n = all.filter { faces.shows($0, c.id) }.count
            return n > 0 ? (c, n) : nil
        }
        if newCount > 0 || !kids.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(String(localized: "Alle (\(all.count))"), .all, Color.brand, Color.onBrand)
                    if newCount > 0 { chip(String(localized: "Nye (\(newCount))"), .new, .red, .white) }
                    ForEach(kids, id: \.0.id) { kid in
                        chip("\(kid.0.firstName) (\(kid.1))", .child(kid.0.id), Palette.color(for: kid.0.id, in: app.children), .white,
                             icon: "person.crop.square")
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .sensoryFeedback(.selection, trigger: filter)
        }
    }

    private func chip(_ title: String, _ value: Filter, _ color: Color, _ onColor: Color, icon: String? = nil) -> some View {
        let selected = filter == value
        return Button { filter = selected ? .all : value } label: {
            Label {
                Text(title)
            } icon: {
                if let icon { Image(systemName: icon) }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(selected ? color : Color.cardSoft, in: Capsule())
            .foregroundStyle(selected ? onColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Face finding: progress while it checks photos; in a child's album, how to find more.
    @ViewBuilder private var faceBar: some View {
        if faces.isEnabled {
            if let s = faces.scanning {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(s.done), total: Double(max(s.total, 1)))
                    Text("Leder efter dine børn på billederne … \(s.done) af \(s.total)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.horizontal).padding(.bottom, 6)
                .accessibilityElement(children: .combine)
            } else if faces.learning {
                Label("Lærer ansigter at kende …", systemImage: "face.smiling")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 6)
            } else if let childId = album.childId, let child = app.child(childId) {
                FindChildCard(child: child)
                    .padding(.horizontal).padding(.bottom, 8)
            }
        }
    }

    /// A thumbnail couldn't load: the cached list's signed URLs have expired. Fetch fresh ones once.
    private func urlsExpired() {
        guard !refreshedForExpiredURLs, !media.isLoading else { return }
        refreshedForExpiredURLs = true
        Task { await media.refresh() }
    }

    private func tile(_ m: Media) -> some View {
        Color.cardSoft
            .frame(maxWidth: .infinity)
            .frame(height: 115)
            .overlay {
                CachedImage(key: "t\(m.id)", url: m.thumbURL, maxPixel: 360, onFailure: urlsExpired,
                            fallbacks: m.thumbFallbacks) {
                    Color.clear
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .bottomTrailing) {
                if m.isVideo {
                    Image(systemName: "play.circle.fill").foregroundStyle(.white).padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if newIds.contains(m.id) {
                    Text("NY").font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.red, in: Capsule()).foregroundStyle(.white)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // Which of my children are in the photo.
                let mine = app.children.filter { faces.shows(m, $0.id) }
                if !mine.isEmpty && album.childId == nil {
                    HStack(spacing: -6) {
                        ForEach(mine) { c in
                            ChildAvatar(child: c, size: 20)
                                .overlay(alignment: .bottomTrailing) {
                                    if faces.isFaceMatch(m, c.id) { FaceBadge() }
                                }
                        }
                    }
                    .padding(4)
                } else if let childId = album.childId, faces.isFaceMatch(m, childId) {
                    FaceBadge(size: 18).padding(5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel(m)))
            .accessibilityAddTraits(.isButton)
    }

    private func accessibilityLabel(_ m: Media) -> String {
        var parts = [m.isVideo ? String(localized: "Video") : String(localized: "Billede")]
        if newIds.contains(m.id) { parts.append(String(localized: "Ny")) }
        let names = m.tagList.map(\.name)
        if !names.isEmpty { parts.append(String(localized: "Tagget: \(names.joined(separator: ", "))")) }
        return parts.joined(separator: ", ")
    }
}

struct MediaViewer: View {
    @State private var items: [Media]
    let start: Media
    var children: [Child] = []
    var newIds: Set<Int> = []
    @State private var current: Int
    @State private var showTags = true
    @State private var tagging = false
    @State private var tagError: String?

    init(items: [Media], start: Media, children: [Child] = [], newIds: Set<Int> = []) {
        _items = State(initialValue: items)
        self.start = start
        self.children = children
        self.newIds = newIds
        // Set before the first render; changing the page in onAppear is sometimes ignored by TabView.
        _current = State(initialValue: items.firstIndex(where: { $0.id == start.id }) ?? 0)
    }
    @State private var sharing: SharedFile?
    @State private var busy = false
    @State private var savedNote: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                    Group {
                        if m.isVideo {
                            CachedImage(key: "t\(m.id)", url: m.thumbURL, maxPixel: 360, contentMode: .fit, fallbacks: m.thumbFallbacks) {
                                ProgressView().tint(.white)
                            }
                        } else {
                            // Full size; the cached thumbnail shows at once while it loads.
                            // A face found by face recognition is outlined while the info is shown.
                            let box = showTags ? children.lazy.compactMap { FaceIndex.shared.faceBox(m, $0.id) }.first : nil
                            CachedImage(key: "f\(m.id)", url: m.fullURL ?? m.thumbURL, maxPixel: nil, contentMode: .fit, highlight: box) {
                                CachedImage(key: "t\(m.id)", url: m.thumbURL, maxPixel: 360, contentMode: .fit, fallbacks: m.thumbFallbacks, highlight: box) {
                                    ProgressView().tint(.white)
                                }
                                .overlay { ProgressView().tint(.white) }
                            }
                        }
                    }
                    .overlay {
                        if m.isVideo, let url = m.fullURL {
                            Button { openURL(url) } label: {
                                Image(systemName: "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { showTags.toggle() } }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if showTags, items.indices.contains(current) { info(items[current]) }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle(items.isEmpty ? "" : "\(current + 1) / \(items.count)")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if items.indices.contains(current), let d = items[current].date {
                        // Like the Photos app: the day on top, time and position below.
                        VStack(spacing: 0) {
                            Text(PhotoDay.title(for: d)).font(.subheadline.weight(.semibold))
                            Text("\(d.formatted(date: .omitted, time: .shortened)) · \(current + 1) / \(items.count)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(items.isEmpty ? "" : "\(current + 1) / \(items.count)").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Luk") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { faceMenu }
                ToolbarItem(placement: .primaryAction) { tagMenu }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { Task { await save() } } label: { Label("Gem i Fotos", systemImage: "square.and.arrow.down") }
                        Button { Task { await share() } } label: { Label("Del …", systemImage: "square.and.arrow.up") }
                    } label: {
                        if busy { ProgressView() } else { Image(systemName: "square.and.arrow.down") }
                    } primaryAction: {
                        Task { await save() }
                    }
                    .disabled(busy || items.isEmpty)
                    .accessibilityLabel(Text("Gem i Fotos"))
                }
            }
            .overlay(alignment: .center) {
                if let savedNote {
                    Label(savedNote, systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity)
                }
            }
            .sheet(item: $sharing) { file in ShareSheet(items: [file.url]) }

            .alert("Noget gik galt", isPresented: Binding(get: { tagError != nil }, set: { if !$0 { tagError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(tagError ?? "") }
        }
    }

    /// "Det er Emma" / "Ikke Emma": teaches face finding (only on this phone, nothing goes to Aula).
    @ViewBuilder private var faceMenu: some View {
        if FaceIndex.shared.isEnabled, items.indices.contains(current), !items[current].isVideo, !children.isEmpty {
            let m = items[current]
            Menu {
                Section("Ansigtsgenkendelse på telefonen") {
                    ForEach(children) { c in
                        if FaceIndex.shared.isFaceMatch(m, c.id) {
                            Button { FaceIndex.shared.reject(m, isNot: c.id) } label: {
                                Label("Det er ikke \(c.firstName)", systemImage: "xmark.circle")
                            }
                        } else if !m.isTagged(c.id) {
                            Button { Task { await learnFace(m, c) } } label: {
                                Label("Det er \(c.firstName)", systemImage: "face.smiling")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "face.smiling")
            }
            .accessibilityLabel(Text("Ansigtsgenkendelse"))
        }
    }

    private func learnFace(_ m: Media, _ c: Child) async {
        if await !FaceIndex.shared.confirm(m, is: c) {
            tagError = String(localized: "Fandt ikke et ansigt på billedet.")
        }
    }

    /// Tag or untag my children in the current photo. Only where Aula allows it (`currentUserCanEditTags`).
    @ViewBuilder private var tagMenu: some View {
        if items.indices.contains(current), items[current].canEditTags == true, !children.isEmpty {
            let m = items[current]
            Menu {
                ForEach(children) { c in
                    let on = m.isTagged(c.id)
                    Button {
                        Task { await toggle(c, !on, m) }
                    } label: {
                        Label(on ? String(localized: "Fjern tag af \(c.firstName)") : String(localized: "Tag \(c.firstName)"),
                              systemImage: on ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                    }
                }
            } label: {
                if tagging { ProgressView() } else { Image(systemName: "person.crop.circle.badge.plus") }
            }
            .disabled(tagging)
            .accessibilityLabel(Text("Tag barn"))
        }
    }

    private func toggle(_ child: Child, _ on: Bool, _ m: Media) async {
        tagging = true
        defer { tagging = false }
        do {
            let updated = try await DataStore.shared.setTagged(child, on, in: m)
            if let i = items.firstIndex(where: { $0.id == m.id }) { items[i] = updated }
            showTags = true
        } catch {
            tagError = error.localizedDescription
        }
    }

    /// Title, "new" marker and the people tagged in the photo; own children first and in their colour.
    @ViewBuilder private func info(_ m: Media) -> some View {
        let mine = Set(children.map(\.id))
        let tags = m.tagList.sorted { mine.contains($0.id) && !mine.contains($1.id) }
        let maybe = children.filter { FaceIndex.shared.isFaceMatch(m, $0.id) }
        if m.title != nil || !tags.isEmpty || newIds.contains(m.id) || !maybe.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(maybe) { c in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            FaceBadge(size: 18)
                            Text("Er det \(c.firstName) i rammen?").font(.subheadline.weight(.bold))
                        }
                        // Far apart on purpose, so "no" isn't tapped by mistake.
                        HStack {
                            Button { FaceIndex.shared.reject(m, isNot: c.id) } label: {
                                Label("Nej", systemImage: "xmark").frame(minWidth: 96)
                            }
                            .buttonStyle(.bordered).tint(.white)
                            Spacer(minLength: 40)
                            Button { Task { await learnFace(m, c) } } label: {
                                Label("Ja, det er \(c.firstName)", systemImage: "checkmark").frame(minWidth: 96)
                            }
                            .buttonStyle(.borderedProminent).tint(.green)
                        }
                        .controlSize(.large)
                    }
                    .padding(.bottom, 4)
                }
                HStack(spacing: 6) {
                    if newIds.contains(m.id) {
                        Text("NY").font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.red, in: Capsule())
                    }
                    if let t = m.title { Text(t).font(.subheadline.weight(.semibold)).lineLimit(2) }
                }
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill").font(.caption).accessibilityHidden(true)
                            ForEach(tags, id: \.id) { t in
                                let own = mine.contains(t.id)
                                Text(t.name)
                                    .font(.caption.weight(own ? .bold : .regular))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(own ? Palette.color(for: t.id, in: children) : Color.white.opacity(0.18),
                                                in: Capsule())
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Tagget: \(tags.map(\.name).joined(separator: ", "))"))
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea())
            .transition(.opacity)
        }
    }

    /// Downloads the current photo or video in full size.
    private func download() async throws -> URL {
        guard items.indices.contains(current) else { throw AulaError.http(404) }
        let m = items[current]
        guard let url = m.fullURL ?? m.thumbURL else { throw AulaError.http(404) }
        return try await AulaAPI.shared.download(url, suggestedName: "aula-\(m.id)" + (m.isVideo ? ".mp4" : ".jpg"))
    }

    /// Saves the current photo or video straight to Photos (add-only access).
    private func save() async {
        busy = true
        defer { busy = false }
        do {
            let file = try await download()
            let isVideo = items.indices.contains(current) && items[current].isVideo
            try await PhotoSaver.save(file, isVideo: isVideo)
            withAnimation { savedNote = String(localized: "Gemt i Fotos") }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { savedNote = nil }
        } catch {
            tagError = error.localizedDescription
        }
    }

    private func share() async {
        busy = true
        defer { busy = false }
        do { sharing = SharedFile(url: try await download()) } catch { tagError = error.localizedDescription }
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app
    @State private var openingPost: Post?

    var body: some View {
        ThemedList(rowBackground: .clear) {
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
        if n.isTaggedInMedia, let child = app.children.first(where: { $0.id == n.relatedChildId }) {
            NavigationLink(value: Album.tagged(child)) { content }
        } else if let threadId = n.threadId {
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
        ThemedList(rowBackground: .clear) {
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

/// Photos taken (uploaded) on one day, for date headers like the Photos app.
struct PhotoDay: Identifiable {
    let id: String
    let date: Date?
    var items: [Media]

    /// Newest day first; photos without a date last.
    static func group(_ list: [Media]) -> [PhotoDay] {
        let cal = Calendar.current
        var days: [String: PhotoDay] = [:]
        for m in list {
            let start = m.date.map { cal.startOfDay(for: $0) }
            let key = start.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
            days[key, default: PhotoDay(id: key, date: start, items: [])].items.append(m)
        }
        return days.values
            .map { d in PhotoDay(id: d.id, date: d.date, items: d.items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// "I dag", "I går", "Mandag", "5. nov." or "5. nov. 2025".
    static func title(for d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "I dag") }
        if cal.isDateInYesterday(d) { return String(localized: "I går") }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: .now)).day, days < 7 {
            return d.formatted(.dateTime.weekday(.wide)).capitalized
        }
        if cal.isDate(d, equalTo: .now, toGranularity: .year) {
            return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return d.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

struct PhotoDayHeader: View {
    let day: PhotoDay

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.date.map(PhotoDay.title(for:)) ?? String(localized: "Uden dato"))
                .font(.headline)
            Spacer()
            Text(day.items.count == 1 ? String(localized: "1 billede") : String(localized: "\(day.items.count) billeder"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Every birthday in the coming year, by month.
struct BirthdaysView: View {
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app

    var body: some View {
        let list = data.birthdays.value ?? []
        let months = Dictionary(grouping: list) { Calendar.week.dateComponents([.year, .month], from: $0.date) }
            .sorted { ($0.key.year ?? 0, $0.key.month ?? 0) < ($1.key.year ?? 0, $1.key.month ?? 0) }
        ThemedList {
            ForEach(months, id: \.key) { key, items in
                Section(Calendar.week.date(from: key).map { $0.formatted(.dateTime.month(.wide).year()).capitalized } ?? "") {
                    ForEach(items) { b in
                        let mine = app.children.contains { $0.id == b.id }
                        HStack(spacing: 12) {
                            Text("🎂").font(.title3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.name).font(.subheadline.weight(mine ? .bold : .semibold))
                                if let g = b.group { Text(g).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(b.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Calendar.current.isDateInToday(b.date) ? Color.pink : Color.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .overlay {
            if list.isEmpty {
                if data.birthdays.isLoading { ProgressView() }
                else { ContentUnavailableView("Ingen fødselsdage", systemImage: "birthday.cake") }
            }
        }
        .navigationTitle("Fødselsdage")
        .refreshable { await data.birthdays.refresh() }
        .task { await data.birthdays.load(maxAge: 6 * 3600) }
    }
}
