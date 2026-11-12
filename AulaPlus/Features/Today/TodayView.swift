import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(DataStore.self) private var data
    @State private var showSettings = false

    private var todayEvents: Loadable<[Event]> { data.events(weekOf: .now) }

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.todayPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap + 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, -6)
                    ChildFilterBar().padding(.horizontal, -Theme.pad)
                    StaleBanner(error: data.presence.error ?? app.session.error, savedAt: data.presence.savedAt)
                    vacationBanner

                    if app.children.isEmpty && app.session.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }

                    ForEach(app.visibleChildren) { child in
                        NavigationLink(value: child) {
                        ChildDayCard(child: child,
                                     presence: data.presence.value?.first { $0.childId == child.id },
                                     events: (todayEvents.value ?? []).filter {
                                         Calendar.week.isDateInToday($0.start) &&
                                         ($0.childIds.isEmpty || $0.childIds.contains(child.id))
                                     })
                        }
                        .buttonStyle(.plain)
                    }

                    unreadSection
                    importantPosts
                    upcomingDates
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .navigationDestination(for: Child.self) { ChildPresenceView(child: $0) }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        InitialsAvatar(name: app.session.value?.displayName ?? "", color: .accentColor, size: 32)
                    }
                    .accessibilityLabel(Text("Profil og indstillinger"))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .refreshable { await refreshAll() }
            .task {
                async let a: () = data.presence.load(maxAge: 60)
                async let b: () = todayEvents.load(maxAge: 300)
                async let c: () = data.threads.load(maxAge: 60)
                async let d: () = data.posts.load(maxAge: 300)
                async let e: () = data.importantDates.load(maxAge: 1800)
                async let f: () = data.vacationRequests.load(maxAge: 1800)
                _ = await (a, b, c, d, e, f)
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let first = app.session.value?.displayName.split(separator: " ").first.map(String.init) ?? ""
        let hello = h < 10 ? String(localized: "Godmorgen") : h < 18 ? String(localized: "Hej") : String(localized: "Godaften")
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
            HStack {
                SectionTitle(title: "Ulæste beskeder", systemImage: "bubble.left.and.bubble.right.fill", count: data.unreadCount)
                Button("Se alle") { app.selectedTab = .messages }.font(.subheadline.weight(.semibold)).padding(.top, 8)
            }
            VStack(spacing: 0) {
                ForEach(Array(unread.enumerated()), id: \.element.id) { i, t in
                    NavigationLink(value: t) { ThreadRow(thread: t).padding(.vertical, 8) }
                        .buttonStyle(.plain)
                    if i < unread.count - 1 { Divider().padding(.leading, 20) }
                }
            }
            .cardStyle(padding: 12)
        }
    }

    @ViewBuilder private var vacationBanner: some View {
        let missing = (data.vacationRequests.value ?? []).filter { $0.isMissingAnswer && $0.isEditable }
        if !missing.isEmpty {
            NavigationLink { VacationRequestsView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sun.max.fill").font(.title2).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Institutionen spørger om ferie").font(.subheadline.weight(.semibold))
                        Text(missing.map { "\($0.childName): \($0.title)" }.joined(separator: "\n"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Color.orange.opacity(0.35)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var upcomingDates: some View {
        let soon = (data.importantDates.value ?? []).filter {
            $0.start.timeIntervalSinceNow > -86_400 && $0.start.timeIntervalSinceNow < 14 * 86_400
        }.prefix(3)
        if !soon.isEmpty {
            SectionTitle(title: "Kommende", systemImage: "star.fill", tint: .yellow)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(soon)) { ImportantDateRow(date: $0) }
            }
            .cardStyle()
        }
    }

    @ViewBuilder private var importantPosts: some View {
        let recent = (data.posts.value ?? []).filter {
            $0.isImportant || ($0.date.map { Date.now.timeIntervalSince($0) < 3 * 86_400 } ?? false)
        }.prefix(3)
        if !recent.isEmpty {
            SectionTitle(title: "Nye opslag", systemImage: "newspaper.fill", tint: .purple)
            ForEach(Array(recent)) { post in
                NavigationLink(value: post) { PostCard(post: post, compact: true) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct ChildDayCard: View {
    struct Fact { let icon: String; let label: String; let value: String }

    static func facts(_ p: Presence) -> [Fact] {
        let raw: [(String, String, String?)] = [
            ("arrow.down.right.circle", String(localized: "Kom"), p.checkIn),
            ("arrow.down.right.circle", String(localized: "Afleveres"), p.checkIn == nil ? p.plannedEntry : nil),
            ("arrow.up.right.circle", String(localized: "Gik"), p.checkOut),
            ("arrow.up.right.circle", String(localized: "Hentes"), p.checkOut == nil ? p.plannedExit : nil),
            ("person.circle", String(localized: "Hentes af"), p.exitWith),
            ("mappin.circle", String(localized: "Lokation"), p.location),
        ]
        return raw.compactMap { t in t.2.map { Fact(icon: t.0, label: t.1, value: $0) } }
    }

    let child: Child
    let presence: Presence?
    let events: [Event]
    @Environment(AppModel.self) private var app

    private var upcoming: [Event] { events.filter { $0.end >= .now } }
    private var doneCount: Int { events.count - upcoming.count }

    var body: some View {
        let color = Palette.color(for: child.id, in: app.children)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ChildAvatar(child: child, size: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text(child.firstName).font(.title3.weight(.semibold))
                    Text(child.institutionName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let status = presence?.status {
                    Label(status.label, systemImage: status.symbol)
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(color.opacity(0.16), in: Capsule())
                        .foregroundStyle(color)
                        .fixedSize()
                }
            }

            if let p = presence {
                let facts = Self.facts(p)
                if !facts.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 10) {
                        ForEach(facts, id: \.label) { f in
                            HStack(spacing: 8) {
                                Image(systemName: f.icon).foregroundStyle(color).font(.body)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(f.label).font(.caption).foregroundStyle(.secondary)
                                    Text(f.value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if let c = p.comment {
                    Label { Text(c) } icon: { Image(systemName: "text.bubble") }
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
                }
            }

            if !events.isEmpty {
                Divider()
                if upcoming.isEmpty {
                    Label("Dagens program er slut", systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(upcoming.prefix(4).enumerated()), id: \.element.id) { i, e in
                            let isNow = e.start <= .now && e.end >= .now
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(e.allDay ? String(localized: "Hele dagen") : Fmt.time(e.start))
                                    .font(.subheadline.weight(i == 0 ? .semibold : .regular)).monospacedDigit()
                                    .foregroundStyle(i == 0 ? Color.primary : Color.secondary)
                                    .fixedSize()
                                    .frame(minWidth: 52, alignment: .leading)
                                Text(e.title).font(.subheadline.weight(i == 0 ? .semibold : .regular)).lineLimit(1)
                                if isNow {
                                    Text("Nu").font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(color, in: Capsule()).foregroundStyle(.white)
                                }
                                if e.hasSubstitute {
                                    Image(systemName: "arrow.triangle.swap").foregroundStyle(.orange).font(.caption)
                                        .accessibilityLabel(Text("Vikar"))
                                }
                                Spacer(minLength: 4)
                                if let loc = e.location {
                                    Text(loc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        let more = upcoming.count - 4
                        if more > 0 || doneCount > 0 {
                            Text(Self.moreText(more: max(more, 0), done: doneCount))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .cardStyle()
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, bottomLeadingRadius: Theme.cardRadius, style: .continuous)
                .fill(color).frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    static func moreText(more: Int, done: Int) -> String {
        var parts: [String] = []
        if more > 0 { parts.append(String(localized: "+\(more) mere")) }
        if done > 0 { parts.append(String(localized: "\(done) afsluttet")) }
        return parts.joined(separator: " · ")
    }
}
