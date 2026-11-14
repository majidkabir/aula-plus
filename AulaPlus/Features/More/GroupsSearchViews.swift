import SwiftUI

/// "Mine grupper", as on aula.dk.
struct GroupsView: View {
    @State private var groups: [AulaGroup]?
    @State private var error: String?

    var body: some View {
        ThemedList {
            ForEach(groups ?? []) { g in
                NavigationLink(value: Route.group(g)) {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "person.3.fill", color: Palette.stable(for: g.name))
                        Text(g.name)
                    }
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .overlay {
            if groups == nil && error == nil { ProgressView() }
            else if groups?.isEmpty == true { ContentUnavailableView("Ingen grupper", systemImage: "person.3") }
        }
        .navigationTitle("Grupper")
        .task {
            if Demo.isOn { groups = [AulaGroup(id: 1, name: "Solsikken", institutionCode: nil)]; return }
            do { groups = try await AulaAPI.shared.myGroups() } catch { self.error = error.localizedDescription }
        }
    }
}

/// One group: its posts, calendar, photos and members.
struct GroupView: View {
    let group: AulaGroup
    enum Tab: String, CaseIterable { case posts = "Opslag", calendar = "Kalender", photos = "Galleri", members = "Medlemmer" }
    @State private var tab: Tab = .posts
    @State private var posts: [Post]?
    @State private var events: [Event]?
    @State private var albums: [Album]?
    @State private var members: [GroupMember]?
    @State private var error: String?

    var body: some View {
        ThemedList {
            Picker("Vis", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            switch tab {
            case .posts:
                ForEach(posts ?? []) { p in
                    NavigationLink(value: p) { PostCard(post: p, compact: true) }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                if posts?.isEmpty == true { Text("Ingen opslag").foregroundStyle(.secondary) }
            case .calendar:
                ForEach(events ?? []) { e in
                    NavigationLink { EventDetailView(event: e) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.subheadline.weight(.semibold))
                            Text(e.allDay ? e.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
                                 : e.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if events?.isEmpty == true { Text("Ingen begivenheder de næste 8 uger").foregroundStyle(.secondary) }
            case .photos:
                ForEach(albums ?? []) { a in
                    NavigationLink(value: a) {
                        HStack(spacing: 12) {
                            CachedImage(key: "c\(a.id)", url: a.coverURL, maxPixel: 200) {
                                Image(systemName: "photo").foregroundStyle(.secondary)
                            }
                            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                if let d = a.date { Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if albums?.isEmpty == true { Text("Ingen albums").foregroundStyle(.secondary) }
            case .members:
                let groups = Dictionary(grouping: members ?? []) { Self.roleGroup($0.role) }
                ForEach(["Medarbejdere", "Børn", "Forældre"], id: \.self) { title in
                    if let list = groups[title], !list.isEmpty {
                        Section("\(String(localized: String.LocalizationValue(title))) (\(list.count))") {
                            ForEach(list) { m in
                                NavigationLink(value: Route.contact(Contact(id: m.id, name: m.name, detail: m.detail, phones: [], email: nil,
                                                                           pictureURL: m.pictureURL, role: m.role, group: m.detail))) {
                                    HStack(spacing: 12) {
                                        ContactAvatar(name: m.name, url: m.pictureURL, size: 34)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(m.name).font(.subheadline)
                                            if let d = m.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle(group.name)
        .task(id: tab) { await load() }
        .refreshable { posts = nil; events = nil; albums = nil; members = nil; await load() }
    }

    private var isLoading: Bool {
        switch tab {
        case .posts: posts == nil
        case .calendar: events == nil
        case .photos: albums == nil
        case .members: members == nil
        }
    }

    static func roleGroup(_ role: String?) -> String {
        switch role {
        case "guardian": "Forældre"
        case "child", "daycare", "early-student", "middle-late-student": "Børn"
        default: "Medarbejdere"
        }
    }

    private func load() async {
        guard !Demo.isOn else { posts = []; events = []; albums = []; members = []; return }
        error = nil
        do {
            switch tab {
            case .posts where posts == nil: posts = try await AulaAPI.shared.groupPosts(group.id)
            case .calendar where events == nil:
                let from = Calendar.week.startOfDay(for: .now)
                events = try await AulaAPI.shared.groupEvents(group.id, from: from, to: Calendar.week.date(byAdding: .day, value: 56, to: from) ?? from)
            case .photos where albums == nil: albums = try await AulaAPI.shared.groupAlbums(group.id)
            case .members where members == nil: members = try await AulaAPI.shared.groupMembers(group.id)
            default: break
            }
        } catch {
            self.error = error.localizedDescription
            switch tab {
            case .posts: posts = posts ?? []
            case .calendar: events = events ?? []
            case .photos: albums = albums ?? []
            case .members: members = members ?? []
            }
        }
    }
}

struct ContactAvatar: View {
    let name: String
    let url: URL?
    var size: CGFloat = 36
    var body: some View {
        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
            InitialsAvatar(name: name, color: Palette.stable(for: name), size: size)
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

/// Search in all of Aula: posts, people, events and photos (messages have their own search).
struct GlobalSearchView: View {
    @State private var text = ""
    @State private var kind: SearchKind = .posts
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var error: String?
    @State private var viewing: Media?
    @Environment(AppModel.self) private var app

    var body: some View {
        ThemedList {
            Picker("Søg i", selection: $kind) {
                Text("Opslag").tag(SearchKind.posts)
                Text("Personer").tag(SearchKind.people)
                Text("Begivenheder").tag(SearchKind.events)
                Text("Billeder").tag(SearchKind.photos)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            if kind == .photos {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 3)], spacing: 3) {
                    ForEach(hits) { h in
                        if let m = h.media {
                            Button { viewing = m } label: {
                                Color.cardSoft.aspectRatio(1, contentMode: .fit)
                                    .overlay { CachedImage(key: "t\(m.id)", url: m.thumbURL, maxPixel: 360, fallbacks: m.thumbFallbacks) { EmptyView() } }
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                ForEach(hits) { h in row(h) }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .overlay {
            if searching { ProgressView() }
            else if hits.isEmpty && text.count >= 2 { ContentUnavailableView.search(text: text) }
            else if text.isEmpty { ContentUnavailableView("Søg i Aula", systemImage: "magnifyingglass",
                                                          description: Text("Opslag, personer, begivenheder og billeder. Beskeder søger du i under Beskeder.")) }
        }
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "Søg i Aula"))
        .navigationTitle("Søg")
        .task(id: "\(kind.rawValue)|\(text)") { await run() }
        .fullScreenCover(item: $viewing) { m in
            MediaViewer(items: hits.compactMap(\.media), start: m, children: app.children)
        }
    }

    @ViewBuilder private func row(_ h: SearchHit) -> some View {
        let label = HStack(spacing: 12) {
            if h.kind == .people { ContactAvatar(name: h.title, url: h.pictureURL, size: 36) }
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let d = h.detail { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if let date = h.date { Text(date.formatted(date: .abbreviated, time: h.kind == .events ? .shortened : .omitted)).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        switch h.kind {
        case .posts:
            if let id = h.postId { NavigationLink { PostLoaderView(id: id) } label: { label } } else { label }
        case .people:
            if let c = h.contact { NavigationLink(value: Route.contact(c)) { label } } else { label }
        case .events:
            NavigationLink {
                EventDetailView(event: Event(id: h.eventId ?? h.id, title: h.title, start: h.date ?? .now, end: h.date ?? .now,
                                             allDay: false, location: h.detail, teacher: nil, substitute: nil, hasSubstitute: false,
                                             type: nil, childIds: []))
            } label: { label }
        case .photos:
            label
        }
    }

    private func run() async {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, !Demo.isOn else { hits = []; return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        searching = true
        error = nil
        defer { searching = false }
        do {
            let s = try await AulaAPI.shared.bootstrap()
            let found = try await AulaAPI.shared.search(t, kind: kind, guardianIds: s.guardianProfileIds ?? [],
                                                        childIds: s.children.map(\.id))
            if !Task.isCancelled { hits = found }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription; hits = [] }
        }
    }
}

/// Opens a post by id (from search or a link).
struct PostLoaderView: View {
    let id: Int
    @State private var post: Post?
    @State private var error: String?
    @Environment(DataStore.self) private var data

    var body: some View {
        Group {
            if let post { PostDetailView(post: post) }
            else if let error { ContentUnavailableView("Kunne ikke åbne opslaget", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView() }
        }
        .task {
            if let p = data.posts.value?.first(where: { $0.id == id }) { post = p; return }
            do { post = try await AulaAPI.shared.post(id: id) } catch { self.error = error.localizedDescription }
        }
    }
}

/// "Samtykker": who may see contact details, photos etc. Same answers as on aula.dk.
struct ConsentsView: View {
    @State private var items: [ConsentItem]?
    @State private var saved: [ConsentItem] = []
    @State private var error: String?
    @State private var note: String?
    @State private var saving = false

    var body: some View {
        ThemedForm {
            if let binding = Binding($items) {
                let people = Array(Set(binding.wrappedValue.map(\.profileName))).sorted()
                ForEach(people, id: \.self) { person in
                    ForEach(binding) { $c in
                        if c.profileName == person {
                            Section {
                                Text(c.text).font(.subheadline.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .listRowBackground(Color.card)
                                ForEach(c.allowed, id: \.self) { a in
                                    Button { c.answer = a } label: {
                                        HStack {
                                            Text(Self.label(a)).foregroundStyle(.primary)
                                            Spacer()
                                            if c.answer == a { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.brand) }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!c.editable)
                                    .accessibilityAddTraits(c.answer == a ? .isSelected : [])
                                }
                            } header: {
                                Text(person)
                            } footer: {
                                if c.answer == nil { Text("Ikke besvaret endnu") }
                            }
                        }
                    }
                }
            }
            if let note { Section { Label(note, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
        }
        .overlay { if items == nil && error == nil { ProgressView() } }
        .navigationTitle("Samtykker")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else { Button("Gem") { Task { await save() } }.disabled(items == nil || items! == saved) }
            }
        }
        .task {
            if Demo.isOn {
                let d = [ConsentItem(id: 1, profileId: 1, profileName: "Emma", text: "Mit barns kontaktoplysninger må deles med forældre og børn inden for mit barns:",
                                     allowed: ["class_or_stue", "institution", "not_at_all"], answer: "institution", editable: true)]
                items = d; saved = d; return
            }
            do { let c = try await AulaAPI.shared.consents(); items = c; saved = c } catch { self.error = error.localizedDescription }
        }
    }

    static func label(_ answer: String) -> String {
        switch answer {
        case "class_or_stue": String(localized: "Klasse eller stue")
        case "institution": String(localized: "Hele institutionen")
        case "not_at_all": String(localized: "Slet ikke")
        case "accepted": String(localized: "Ja")
        case "declined": String(localized: "Nej")
        default: answer
        }
    }

    private func save() async {
        guard let items else { return }
        let changed = items.filter { c in saved.first { $0.id == c.id && $0.profileId == c.profileId } != c }
        saving = true
        error = nil
        defer { saving = false }
        do {
            if !Demo.isOn { try await AulaAPI.shared.saveConsents(changed) }
            saved = items
            note = String(localized: "Gemt på Aula")
        } catch {
            self.error = String(localized: "Ikke gemt: \(error.localizedDescription)")
        }
    }
}
