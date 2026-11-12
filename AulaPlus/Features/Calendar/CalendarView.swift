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
            VStack(spacing: 0) {
                ChildFilterBar().padding(.vertical, 4)
                weekStrip
                Divider()
                List {
                    StaleBanner(error: week.error, savedAt: week.savedAt)
                        .listRowSeparator(.hidden)
                    ForEach(dayEvents) { e in
                        NavigationLink { EventDetailView(event: e) } label: { EventRow(event: e) }
                            .swipeActions {
                                Button { addingEvent = e } label: { Label("Kalender", systemImage: "calendar.badge.plus") }
                                    .tint(.accentColor)
                            }
                            .contextMenu {
                                Button { addingEvent = e } label: { Label("Føj til min kalender", systemImage: "calendar.badge.plus") }
                            }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if dayEvents.isEmpty {
                        if week.isLoading && week.value == nil { ProgressView() }
                        else { ContentUnavailableView("Intet i kalenderen", systemImage: "calendar") }
                    }
                }
                .refreshable { await week.refresh() }
            }
            .navigationTitle(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("I dag") { selectedDay = Calendar.week.startOfDay(for: .now) }
                }
            }
            .task(id: weekStart) { await week.load(maxAge: 600) }
            .sheet(item: $addingEvent) { e in
                AddToCalendarSheet(event: e, childNames: e.childIds.compactMap { app.child($0)?.firstName })
                    .ignoresSafeArea()
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left") }
            ForEach(Week.days(of: weekStart), id: \.self) { day in
                let selected = Calendar.week.isDate(day, inSameDayAs: selectedDay)
                let isToday = Calendar.week.isDateInToday(day)
                let count = (week.value ?? []).filter {
                    Calendar.week.isDate($0.start, inSameDayAs: day) && matchesChild($0)
                }.count
                Button { selectedDay = day } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.callout.weight(selected || isToday ? .bold : .regular))
                            .frame(width: 34, height: 34)
                            .background(selected ? Color.accentColor : .clear, in: Circle())
                            .foregroundStyle(selected ? Color.white : isToday ? Color.accentColor : Color.primary)
                        Circle().fill(count > 0 ? Color.secondary : .clear).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -50 { shift(7) } else if v.translation.width > 50 { shift(-7) }
        })
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func shift(_ days: Int) {
        selectedDay = Calendar.week.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
    }
}

struct EventRow: View {
    let event: Event
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                if event.allDay {
                    Text("Hele\ndagen").multilineTextAlignment(.trailing)
                } else {
                    Text(Fmt.time(event.start))
                    Text(Fmt.time(event.end)).foregroundStyle(.secondary)
                }
            }
            .font(.caption.monospacedDigit())
            .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.subheadline.weight(.semibold))
                if let loc = event.location { Label(loc, systemImage: "mappin").font(.caption) }
                if event.hasSubstitute {
                    Label("Vikar\(event.substitute.map { ": \($0)" } ?? "")", systemImage: "arrow.triangle.swap")
                        .font(.caption).foregroundStyle(.orange)
                } else if let t = event.teacher {
                    Label(t, systemImage: "person").font(.caption).foregroundStyle(.secondary)
                }
                let names = event.childIds.compactMap { app.child($0)?.firstName }
                if app.children.count > 1, !names.isEmpty {
                    Text(names.joined(separator: ", ")).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(event.end < .now ? 0.5 : 1)
    }

    private var color: Color {
        guard let first = event.childIds.first else { return .gray }
        return Palette.color(for: first, in: app.children)
    }
}
