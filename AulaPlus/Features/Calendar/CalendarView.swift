import SwiftUI

struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @Environment(DataStore.self) private var data
    @State private var selectedDay = Calendar.week.startOfDay(for: .now)
    @State private var addingEvent: Event?

    private var weekStart: Date { Week.start(of: selectedDay) }
    private var week: Loadable<[Event]> { data.events(weekOf: selectedDay) }

    private var dayEvents: [Event] {
        (week.value ?? []).filter { e in
            Calendar.week.isDate(e.start, inSameDayAs: selectedDay) && matchesChild(e)
        }
    }

    private func matchesChild(_ e: Event) -> Bool {
        guard let id = app.selectedChildId else { return true }
        return e.childIds.isEmpty || e.childIds.contains(id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    ChildFilterBar().padding(.horizontal, -Theme.pad)
                    VStack(spacing: 8) {
                        WeekSwitcher(date: $selectedDay)
                        dayStrip
                    }
                    .cardStyle(padding: 10)

                    StaleBanner(error: week.error, savedAt: week.savedAt)

                    HStack(alignment: .firstTextBaseline) {
                        Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                            .font(.title3.weight(.bold))
                        if Calendar.week.isDateInToday(selectedDay) {
                            Text("I dag").font(.caption.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)

                    if dayEvents.isEmpty {
                        if week.isLoading && week.value == nil {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                        } else {
                            ContentUnavailableView("Intet i kalenderen", systemImage: "calendar",
                                                   description: Text("Der er ingen begivenheder denne dag."))
                                .padding(.top, 20)
                        }
                    }

                    ForEach(Array(dayEvents.enumerated()), id: \.element.id) { i, e in
                        if showNowLine(before: i) { NowLine() }
                        NavigationLink { EventDetailView(event: e) } label: { EventCard(event: e) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { addingEvent = e } label: { Label("Føj til min kalender", systemImage: "calendar.badge.plus") }
                            }
                    }
                    if showNowLine(before: dayEvents.count) && !dayEvents.isEmpty { NowLine() }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kalender")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("I dag") { selectedDay = Calendar.week.startOfDay(for: .now) }
                        .disabled(Calendar.week.isDateInToday(selectedDay))
                }
            }
            .refreshable { await week.refresh() }
            .task(id: weekStart) { await week.load(maxAge: 600) }
            .sheet(item: $addingEvent) { e in
                AddToCalendarSheet(event: e, childNames: e.childIds.compactMap { app.child($0)?.firstName })
                    .ignoresSafeArea()
            }
        }
    }

    /// The "now" marker goes before the first event that hasn't started yet (today only).
    private func showNowLine(before index: Int) -> Bool {
        guard Calendar.week.isDateInToday(selectedDay) else { return false }
        let firstUpcoming = dayEvents.firstIndex { $0.start > .now } ?? dayEvents.count
        return index == firstUpcoming
    }

    private var dayStrip: some View {
        HStack(spacing: 2) {
            ForEach(Week.days(of: weekStart), id: \.self) { day in
                let selected = Calendar.week.isDate(day, inSameDayAs: selectedDay)
                let isToday = Calendar.week.isDateInToday(day)
                let count = (week.value ?? []).filter {
                    Calendar.week.isDate($0.start, inSameDayAs: day) && matchesChild($0)
                }.count
                Button { selectedDay = day } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.callout.weight(selected || isToday ? .bold : .regular))
                            .foregroundStyle(selected ? Color.white : isToday ? Color.accentColor : Color.primary)
                        Circle().fill(count > 0 ? (selected ? Color.white : Color.secondary) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(selected ? Color.accentColor : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(day.formatted(date: .complete, time: .omitted)))
                .accessibilityValue(Text("\(count) begivenheder"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -50 { shift(7) } else if v.translation.width > 50 { shift(-7) }
        })
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func shift(_ days: Int) {
        selectedDay = Calendar.week.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
    }
}

struct NowLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Rectangle().fill(.red).frame(height: 1.5)
            Text(Fmt.time(.now)).font(.caption2.weight(.bold)).foregroundStyle(.red).monospacedDigit()
        }
        .accessibilityHidden(true)
    }
}

/// One calendar item: time column, colour bar, title and details.
struct EventCard: View {
    let event: Event
    @Environment(AppModel.self) private var app

    private var isPast: Bool { event.end < .now }
    private var color: Color {
        guard let first = event.childIds.first else { return .gray }
        return Palette.color(for: first, in: app.children)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                if event.allDay {
                    Text("Hele dagen").font(.caption.weight(.semibold))
                } else {
                    Text(Fmt.time(event.start)).font(.subheadline.weight(.semibold))
                    Text(Fmt.time(event.end)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 52, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title).font(.body.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 4)
                    if event.hasSubstitute {
                        Label("Vikar", systemImage: "arrow.triangle.swap")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                let details: [String] = [event.location, event.hasSubstitute ? event.substitute : event.teacher].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                let names = event.childIds.compactMap { app.child($0)?.firstName }
                if app.children.count > 1, app.selectedChildId == nil, !names.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(event.childIds, id: \.self) { id in
                            if let c = app.child(id) {
                                ChildTag(name: c.firstName, color: Palette.color(for: id, in: app.children))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.rowRadius + 2, style: .continuous))
        .opacity(isPast ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}
