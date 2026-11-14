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
                    TodayHero(greeting: greeting, unread: data.unreadCount,
                              pickup: firstPickup, next: nextThing) { app.selectedTab = .messages }
                    ChildFilterBar().padding(.horizontal, -Theme.pad)
                    StaleBanner(error: data.presence.error ?? app.session.error, savedAt: data.presence.savedAt)
                    vacationBanner
                    newPhotosCard

                    if app.children.isEmpty && app.session.isLoading {
                        // Skeleton while the first load runs.
                        ForEach([Demo.emma, Demo.noah]) { c in
                            ChildDayCard(child: c, presence: Demo.presence.first { $0.childId == c.id }, events: [])
                        }
                        .redacted(reason: .placeholder)
                        .allowsHitTesting(false)
                    }

                    ForEach(app.visibleChildren) { child in
                        NavigationLink(value: child) {
                        ChildDayCard(child: child,
                                     presence: data.presence.value?.first { $0.childId == child.id },
                                     events: (todayEvents.value ?? []).filter {
                                         $0.occurs(on: .now) &&
                                         ($0.childIds.isEmpty || $0.childIds.contains(child.id))
                                     })
                        }
                        .buttonStyle(.plain)
                    }

                    ParentTasksCard()
                    unreadSection
                    importantPosts
                    upcomingDates
                    birthdaysCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .navigationDestination(for: Child.self) { ChildPresenceView(child: $0) }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .navigationTitle("I dag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        InitialsAvatar(name: app.session.value?.displayName ?? "", color: ThemeStore.shared.theme.gradientStart, size: 32)
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
                async let g: () = data.notifications.load(maxAge: 300)
                async let h: () = data.birthdays.load(maxAge: 6 * 3600)
                _ = await (a, b, c, d, e, f, g, h)
                findTasks()
            }
            .onChange(of: data.threads.value) { _, _ in findTasks() }
            .onChange(of: data.posts.value) { _, _ in findTasks() }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let first = app.session.value?.displayName.split(separator: " ").first.map(String.init) ?? ""
        let hello = h < 10 ? String(localized: "Godmorgen") : h < 18 ? String(localized: "Hej") : String(localized: "Godaften")
        return first.isEmpty ? hello : "\(hello), \(first)"
    }

    /// Earliest planned pick-up among visible children not yet picked up.
    /// "Fri" when none of them is coming today.
    private var firstPickup: String? {
        let ids0 = Set(app.visibleChildren.map(\.id))
        let today = (data.presence.value ?? []).filter { ids0.contains($0.childId) }
        if !today.isEmpty, today.allSatisfy(\.isDayOff) { return String(localized: "Fri") }
        let ids = Set(app.visibleChildren.map(\.id))
        return (data.presence.value ?? [])
            .filter { ids.contains($0.childId) && $0.checkOut == nil }
            .compactMap(\.plannedExit).min()
    }

    /// The next event today or an upcoming important date.
    private var nextThing: (title: String, time: String)? {
        if let e = (todayEvents.value ?? []).first(where: { !$0.allDay && $0.start > .now && Calendar.week.isDateInToday($0.start) }) {
            return (e.title, Fmt.time(e.start))
        }
        if let d = (data.importantDates.value ?? []).first(where: { $0.start > .now }) {
            let when = Calendar.week.isDateInTomorrow(d.start)
                ? String(localized: "I morgen")
                : d.start.formatted(.dateTime.weekday(.abbreviated).day())
            return (d.title, when)
        }
        return nil
    }

    /// Reads new messages and posts on the phone for things to do.
    private func findTasks() {
        ParentTaskFinder.shared.update(threads: data.threads.value ?? [], posts: data.posts.value ?? [],
                                       myName: app.session.value?.displayName ?? "")
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

    /// "12 nye billeder" — opens the gallery (its own tab when there's no week plan).
    @ViewBuilder private var newPhotosCard: some View {
        let count = data.newGalleryCount
        if count > 0 {
            Button {
                if app.showsWeekPlan { app.todayPath.append(Route.gallery) } else { app.selectedTab = .photos }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "photo.stack.fill")
                        .font(.title3.weight(.bold)).foregroundStyle(.purple)
                        .frame(width: 46, height: 46)
                        .background(Color.purple.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(count) nye billeder").font(.headline.weight(.heavy))
                        Text("Se dem i galleriet").font(.subheadline).foregroundStyle(Color.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Color.inkSoft)
                }
                .cardStyle(padding: 14)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var vacationBanner: some View {
        let missing = (data.vacationRequests.value ?? []).filter { $0.isMissingAnswer && $0.isEditable }
        if !missing.isEmpty {
            NavigationLink(value: Route.vacations) {
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

    @ViewBuilder private var birthdaysCard: some View {
        let soon = (data.birthdays.value ?? []).filter { $0.date.timeIntervalSinceNow < 30 * 86_400 }.prefix(4)
        if !soon.isEmpty {
            HStack {
                SectionTitle(title: "Fødselsdage", systemImage: "birthday.cake.fill", tint: .pink)
                Spacer()
                NavigationLink(value: Route.birthdays) { Text("Vis alle").font(.subheadline.weight(.semibold)) }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(soon)) { b in
                    let mine = app.children.contains { $0.id == b.id }
                    HStack(spacing: 10) {
                        Text("🎂").font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.name).font(.subheadline.weight(mine ? .bold : .semibold)).lineLimit(1)
                            if let g = b.group { Text(g).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 8)
                        Text(Calendar.current.isDateInToday(b.date) ? String(localized: "I dag")
                             : b.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Calendar.current.isDateInToday(b.date) ? Color.pink : Color.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
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
        let planned = !Presence.isPlaceholder(entry: p.plannedEntry, exit: p.plannedExit)
        let raw: [(String, String, String?)] = [
            ("arrow.down.right.circle", String(localized: "Kom"), p.checkIn),
            ("arrow.down.right.circle", String(localized: "Afleveres"), p.checkIn == nil && planned ? p.plannedEntry : nil),
            ("arrow.up.right.circle", String(localized: "Gik"), p.checkOut),
            ("arrow.up.right.circle", String(localized: "Hentes"), p.checkOut == nil && planned ? p.plannedExit : nil),
            ("person.circle", String(localized: "Hentes af"), p.exitWith),
            ("mappin.circle", String(localized: "Lokation"), p.location),
        ]
        return raw.compactMap { t in t.2.map { Fact(icon: t.0, label: t.1, value: $0) } }
    }

    let child: Child
    let presence: Presence?
    let events: [Event]
    @Environment(AppModel.self) private var app
    @Environment(DataStore.self) private var data
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Not coming today (weekend, holiday): no times, no timeline, the next drop-off instead.
    private var dayOff: Bool { presence?.isDayOff ?? false }
    private var isWeekend: Bool { Calendar.week.isDateInWeekend(.now) }

    /// First upcoming day with a real drop-off plan.
    private var nextDropOff: DayPlan? {
        (data.upcomingPlans(childId: child.id).value ?? [])
            .sorted { $0.date < $1.date }
            .first { !$0.isOnVacation && $0.entry != nil && !Presence.isPlaceholder(entry: $0.entry, exit: $0.exit) }
    }

    private var upcoming: [Event] { events.filter { $0.end >= .now } }
    private var doneCount: Int { events.count - upcoming.count }

    var body: some View {
        let color = Palette.color(for: child.id, in: app.children)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ChildAvatar(child: child, size: 54)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(child.firstName).font(.title2.weight(.heavy))
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    Text(child.institutionName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if dayOff {
                        Label(isWeekend ? String(localized: "Weekend") : String(localized: "Fri i dag"),
                              systemImage: isWeekend ? "sun.max.fill" : "house.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.card, in: Capsule())
                            .foregroundStyle(color)
                            .padding(.top, 2)
                    } else if let status = presence?.status {
                        Label(status.label, systemImage: status.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.card, in: Capsule())
                            .foregroundStyle(color)
                            .padding(.top, 2)
                    }
                }
            }

            if let p = presence {
                let facts = Self.facts(p)
                if !facts.isEmpty {
                    LazyVGrid(columns: typeSize.isAccessibilitySize
                              ? [GridItem(.flexible(), alignment: .leading)]
                              : [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 10) {
                        ForEach(facts, id: \.label) { f in
                            HStack(spacing: 8) {
                                Image(systemName: f.icon).foregroundStyle(color).font(.body.weight(.bold))
                                    .frame(width: 30, height: 30)
                                    .background(Color.card, in: Circle())
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
                        .background(Color.card, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
                }
            }

            if dayOff {
                nextDropOffRow(color)
            } else if presence != nil || !events.isEmpty {
                DayTimeline(presence: presence, events: events, color: color)
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
                                if let loc = e.location, !typeSize.isAccessibilitySize {
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
        .pastelCard(color, padding: 18)
        .task(id: dayOff) {
            if dayOff { await data.upcomingPlans(childId: child.id).load(maxAge: 3600) }
        }
    }

    /// "Næste aflevering · Mandag 07:45 · hentes 16:00".
    @ViewBuilder private func nextDropOffRow(_ color: Color) -> some View {
        if let next = nextDropOff, let entry = next.entry {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").font(.body.weight(.bold)).foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(Color.card, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("Næste aflevering").font(.caption).foregroundStyle(.secondary)
                    Text(Self.nextText(next, entry: entry)).font(.subheadline.weight(.semibold))
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(isWeekend ? "Ingen aflevering i weekenden" : "Ingen aflevering i dag")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    static func nextText(_ p: DayPlan, entry: String) -> String {
        let day = Calendar.week.isDateInTomorrow(p.date)
            ? String(localized: "I morgen")
            : p.date.formatted(.dateTime.weekday(.wide)).capitalized
        if let exit = p.exit { return String(localized: "\(day) \(entry) · hentes \(exit)") }
        return "\(day) \(entry)"
    }

    static func moreText(more: Int, done: Int) -> String {
        var parts: [String] = []
        if more > 0 { parts.append(String(localized: "+\(more) mere")) }
        if done > 0 { parts.append(String(localized: "\(done) afsluttet")) }
        return parts.joined(separator: " · ")
    }
}

/// Header: date, a big friendly greeting, and three pastel tiles with the day's key numbers.
struct TodayHero: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let greeting: String
    let unread: Int
    let pickup: String?
    let next: (title: String, time: String)?
    let openMessages: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                    .font(.subheadline.weight(.bold)).foregroundStyle(Color.inkSoft)
                Text(greeting).font(.largeTitle.weight(.heavy))
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                Button(action: openMessages) {
                    tile(value: "\(unread)", label: String(localized: "Ulæste"), icon: "bubble.left.fill", color: .purple)
                }
                .buttonStyle(.plain)
                tile(value: pickup ?? "–", label: String(localized: "Afhentning"), icon: "figure.and.child.holdinghands", color: .teal)
                tile(value: next?.time ?? "–", label: next?.title ?? String(localized: "Intet planlagt"), icon: "calendar", color: .orange)
            }
        }
        .padding(.top, 4)
    }

    private func tile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.subheadline.weight(.bold)).foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Color.card, in: Circle())
            Text(value).font(.title2.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Color.inkSoft)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
