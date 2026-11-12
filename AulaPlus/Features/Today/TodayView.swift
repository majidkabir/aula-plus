import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(DataStore.self) private var data
    @State private var showSettings = false

    private var todayEvents: Loadable<[Event]> { data.events(weekOf: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ChildFilterBar().padding(.horizontal, -16)
                    StaleBanner(error: data.presence.error ?? app.session.error, savedAt: data.presence.savedAt)

                    if app.children.isEmpty && app.session.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }

                    ForEach(app.visibleChildren) { child in
                        ChildDayCard(child: child,
                                     presence: data.presence.value?.first { $0.childId == child.id },
                                     events: (todayEvents.value ?? []).filter {
                                         Calendar.week.isDateInToday($0.start) &&
                                         ($0.childIds.isEmpty || $0.childIds.contains(child.id))
                                     })
                    }

                    unreadSection
                    importantPosts
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .refreshable { await refreshAll() }
            .task {
                async let a: () = data.presence.load(maxAge: 60)
                async let b: () = todayEvents.load(maxAge: 300)
                async let c: () = data.threads.load(maxAge: 60)
                async let d: () = data.posts.load(maxAge: 300)
                _ = await (a, b, c, d)
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let first = app.session.value?.displayName.split(separator: " ").first.map(String.init) ?? ""
        let hello = h < 10 ? "Godmorgen" : h < 18 ? "Hej" : "Godaften"
        return first.isEmpty ? hello : "\(hello), \(first)"
    }

    private func refreshAll() async {
        async let a: () = data.presence.refresh()
        async let b: () = todayEvents.refresh()
        async let c: () = data.threads.refresh()
        async let d: () = data.posts.refresh()
        _ = await (a, b, c, d)
    }

    @ViewBuilder private var unreadSection: some View {
        let unread = (data.threads.value ?? []).filter { !$0.isRead }.prefix(3)
        if !unread.isEmpty {
            SectionHeader(title: "Ulæste beskeder", count: data.unreadCount)
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(unread.enumerated()), id: \.element.id) { i, t in
                        NavigationLink(value: t) { ThreadRow(thread: t).padding(.vertical, 6) }
                            .buttonStyle(.plain)
                        if i < unread.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder private var importantPosts: some View {
        let recent = (data.posts.value ?? []).filter {
            $0.isImportant || ($0.date.map { Date.now.timeIntervalSince($0) < 3 * 86_400 } ?? false)
        }.prefix(3)
        if !recent.isEmpty {
            SectionHeader(title: "Nye opslag", count: nil)
            ForEach(Array(recent)) { post in
                NavigationLink(value: post) { PostCard(post: post, compact: true) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int?
    var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 8)
    }
}

struct ChildDayCard: View {
    struct Fact { let label: String; let value: String }

    static func facts(_ p: Presence) -> [Fact] {
        let raw: [(String, String?)] = [
            ("Kom", p.checkIn), ("Gik", p.checkOut),
            ("Afleveres", p.checkIn == nil ? p.plannedEntry : nil),
            ("Hentes", p.checkOut == nil ? p.plannedExit : nil),
            ("Hentes af", p.exitWith), ("Lokation", p.location),
        ]
        return raw.compactMap { pair in pair.1.map { Fact(label: pair.0, value: $0) } }
    }

    let child: Child
    let presence: Presence?
    let events: [Event]
    @Environment(AppModel.self) private var app

    var body: some View {
        let color = Palette.color(for: child.id, in: app.children)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ChildAvatar(child: child, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(child.firstName).font(.headline)
                        Text(child.institutionName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let status = presence?.status {
                        Label(status.label, systemImage: status.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(color.opacity(0.15), in: Capsule())
                            .foregroundStyle(color)
                    }
                }

                if let p = presence {
                    let facts = Self.facts(p)
                    if !facts.isEmpty {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(facts, id: \.label) { fact in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.label).font(.caption2).foregroundStyle(.secondary)
                                    Text(fact.value).font(.subheadline.weight(.medium)).lineLimit(1)
                                }
                            }
                        }
                    }
                    if let c = p.comment {
                        Text(c).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !events.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(events.prefix(8)) { e in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(e.allDay ? "Hele dagen" : Fmt.time(e.start))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .leading)
                                Text(e.title).font(.subheadline).lineLimit(1)
                                if e.hasSubstitute {
                                    Image(systemName: "arrow.triangle.swap").foregroundStyle(.orange).font(.caption)
                                }
                                Spacer()
                                if let loc = e.location {
                                    Text(loc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .opacity(e.end < .now ? 0.45 : 1)
                        }
                    }
                }
            }
        }
    }
}
