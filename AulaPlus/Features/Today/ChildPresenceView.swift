import SwiftUI

/// Komme/Gå for one child: status, sick report, ferie/fri and the week's pickup plan.
struct ChildPresenceView: View {
    let child: Child
    @Environment(DataStore.self) private var data
    @Environment(AppModel.self) private var app

    @State private var weekDate = Date.now
    @State private var plans: Loadable<[DayPlan]>?
    @State private var permissions: PresencePermissions?
    @State private var editing: DayPlan?
    @State private var showVacation = false
    @State private var confirmSick = false
    @State private var busy = false
    @State private var message: String?

    private var presence: Presence? { data.presence.value?.first { $0.childId == child.id } }
    private var isSick: Bool { presence?.status == .sick }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ChildAvatar(child: child, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(child.name).font(.headline)
                        if let s = presence?.status {
                            Label(s.label, systemImage: s.symbol).foregroundStyle(.secondary)
                        } else {
                            Text(child.institutionName).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("I dag") {
                if permissions?.canReportSick != false {
                    Button {
                        confirmSick = true
                    } label: {
                        Label(isSick ? String(localized: "Fjern sygemelding") : String(localized: "Meld syg i dag"),
                              systemImage: isSick ? "cross.case" : "cross.case.fill")
                    }
                    .tint(isSick ? .accentColor : .red)
                    .disabled(busy)
                }
                if permissions?.canAddVacation != false {
                    Button { showVacation = true } label: {
                        Label("Meld ferie/fri", systemImage: "sun.max")
                    }
                }
            }

            Section {
                ForEach(Week.days(of: Week.start(of: weekDate)).prefix(5), id: \.self) { day in
                    let plan = plans?.value?.first { Calendar.week.isDate($0.date, inSameDayAs: day) }
                    Button {
                        editing = plan ?? DayPlan(templateId: nil, childId: child.id, date: day, entry: nil, exit: nil,
                                                  kind: .pickedUpBy, exitWith: nil, comment: nil,
                                                  isOnVacation: false, repeats: false)
                    } label: {
                        DayPlanRow(day: day, plan: plan)
                    }
                    .buttonStyle(.plain)
                    .disabled(permissions?.canEditPickup == false || day < Calendar.week.startOfDay(for: .now))
                }
            } header: {
                HStack {
                    Text("Afhentning — uge \(Week.isoWeek(weekDate).week)")
                    Spacer()
                    Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                    Button { shift(7) } label: { Image(systemName: "chevron.right") }
                }
            } footer: {
                if permissions?.canEditPickup == false {
                    Text("Institutionen tillader ikke at forældre ændrer tider her.")
                }
            }
        }
        .navigationTitle(child.firstName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task(id: Week.key(weekDate)) { await reload() }
        .task { permissions = try? await AulaAPI.shared.presencePermissions(childIds: [child.id]).first }
        .confirmationDialog(isSick ? String(localized: "Fjern sygemelding for \(child.firstName)?") : String(localized: "Meld \(child.firstName) syg i dag?"),
                            isPresented: $confirmSick, titleVisibility: .visible) {
            Button(isSick ? String(localized: "Fjern sygemelding") : String(localized: "Meld syg"), role: isSick ? nil : .destructive) {
                Task { await toggleSick() }
            }
        }
        .sheet(item: $editing) { plan in
            DayPlanEditor(child: child, plan: plan) { saved in
                editing = nil
                if saved {
                    message = String(localized: "Tider gemt.")
                    Task { await reload() }
                }
            }
        }
        .sheet(isPresented: $showVacation) {
            VacationForm(child: child) { saved in
                showVacation = false
                if saved {
                    message = String(localized: "Ferie/fri er meldt.")
                    Task { await data.presence.refresh() }
                }
            }
        }
    }

    private func loadable() -> Loadable<[DayPlan]> {
        let start = Week.start(of: weekDate)
        let id = child.id
        return Loadable(key: "plans-\(id)-\(Week.key(start))") {
            let end = Calendar.week.date(byAdding: .day, value: 6, to: start)!
            return try await AulaAPI.shared.dayPlans(childIds: [id], from: start, to: end)
        }
    }

    private func reload() async {
        let l = loadable()
        plans = l
        await l.refresh()
    }

    private func shift(_ days: Int) {
        weekDate = Calendar.week.date(byAdding: .day, value: days, to: weekDate) ?? weekDate
    }

    private func toggleSick() async {
        busy = true
        defer { busy = false }
        do {
            try await AulaAPI.shared.setSick(childIds: [child.id], sick: !isSick)
            message = isSick ? String(localized: "Sygemelding fjernet.") : "\(child.firstName) er meldt syg."
            await data.presence.refresh()
        } catch {
            message = String(localized: "Ikke gemt: \(error.localizedDescription)")
        }
    }
}

struct DayPlanRow: View {
    let day: Date
    let plan: DayPlan?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.wide)).capitalized).font(.subheadline.weight(.semibold))
                Text(day.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 90, alignment: .leading)
            if let p = plan {
                if p.isOnVacation {
                    Label("Ferie/fri", systemImage: "sun.max.fill").foregroundStyle(.orange)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(p.entry ?? "–") – \(p.exit ?? "–")").font(.subheadline.monospacedDigit())
                        if let who = p.exitWith ?? p.kind?.label {
                            Text(who).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } else {
                Text("Ingen tider").foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct DayPlanEditor: View {
    let child: Child
    @State var plan: DayPlan
    let done: (Bool) -> Void

    @State private var entry = Date()
    @State private var exit = Date()
    @State private var names: [String] = []
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(plan.date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized) {
                    DatePicker("Afleveres", selection: $entry, displayedComponents: .hourAndMinute)
                    DatePicker("Hentes", selection: $exit, displayedComponents: .hourAndMinute)
                    Picker("Hvordan", selection: Binding(get: { plan.kind ?? .pickedUpBy }, set: { plan.kind = $0 })) {
                        ForEach(PickupKind.allCases) { Text($0.label).tag($0) }
                    }
                    if (plan.kind ?? .pickedUpBy).needsName {
                        if !names.isEmpty {
                            Picker("Hvem", selection: Binding(get: { plan.exitWith ?? "" }, set: { plan.exitWith = $0 })) {
                                Text("Vælg").tag("")
                                ForEach(names, id: \.self) { Text($0).tag($0) }
                                if let w = plan.exitWith, !w.isEmpty, !names.contains(w) { Text(w).tag(w) }
                            }
                        }
                        TextField("Navn (fx Mor)", text: Binding(get: { plan.exitWith ?? "" }, set: { plan.exitWith = $0 }))
                    }
                }
                Section("Bemærkning") {
                    TextField("Valgfri", text: Binding(get: { plan.comment ?? "" }, set: { plan.comment = $0 }), axis: .vertical)
                }
                if plan.repeats {
                    Section {
                        Text("Dagen følger en fast ugeplan. Ændringen gælder kun denne dag.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(child.firstName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuller") { done(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Gem") { Task { await save() } } }
                }
            }
            .task {
                entry = Self.time(plan.entry ?? "08:00", on: plan.date)
                exit = Self.time(plan.exit ?? "16:00", on: plan.date)
                names = (try? await AulaAPI.shared.pickupNames(childId: child.id)) ?? []
            }
        }
    }

    private func save() async {
        if (plan.kind ?? .pickedUpBy).needsName, (plan.exitWith ?? "").isEmpty {
            error = String(localized: "Vælg hvem der henter.")
            return
        }
        guard exit > entry else { error = String(localized: "Hentetid skal være efter afleveringstid."); return }
        saving = true
        defer { saving = false }
        plan.entry = Self.hhmm(entry)
        plan.exit = Self.hhmm(exit)
        do {
            try await AulaAPI.shared.savePlan(plan)
            done(true)
        } catch {
            self.error = String(localized: "Ikke gemt: \(error.localizedDescription)")
        }
    }

    static func time(_ hhmm: String, on day: Date) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        return Calendar.week.date(bySettingHour: parts.first ?? 8, minute: parts.count > 1 ? parts[1] : 0,
                                  second: 0, of: day) ?? day
    }

    static func hhmm(_ d: Date) -> String {
        let c = Calendar.week.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

struct VacationForm: View {
    let child: Child
    let done: (Bool) -> Void
    @Environment(AppModel.self) private var app

    @State private var from = Calendar.week.startOfDay(for: .now)
    @State private var to = Calendar.week.startOfDay(for: .now)
    @State private var comment = ""
    @State private var allChildren = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Fra", selection: $from, in: Calendar.week.startOfDay(for: .now)..., displayedComponents: .date)
                    DatePicker("Til", selection: $to, in: from..., displayedComponents: .date)
                    if app.children.count > 1 {
                        Toggle("Gælder alle børn", isOn: $allChildren)
                    }
                }
                Section("Besked til institutionen") {
                    TextField("Fx Vi er i sommerhus", text: $comment, axis: .vertical)
                    Text("\(comment.count)/250").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Ferie/fri")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: from) { _, new in if to < new { to = new } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuller") { done(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Meld") { Task { await save() } } }
                }
            }
        }
    }

    private func save() async {
        guard comment.count <= 250 else { error = String(localized: "Højst 250 tegn."); return }
        saving = true
        defer { saving = false }
        let ids = allChildren ? app.children.map(\.id) : [child.id]
        do {
            try await AulaAPI.shared.addVacation(childIds: ids, from: from, to: to, comment: comment)
            done(true)
        } catch {
            self.error = String(localized: "Ikke gemt: \(error.localizedDescription)")
        }
    }
}
