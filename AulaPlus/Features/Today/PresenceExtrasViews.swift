import SwiftUI

/// "Hvem må hente": the child's family from Aula plus names the parents added.
struct PickupPeopleSection: View {
    let child: Child
    @State private var people: [PickupPerson]?
    @State private var adding = false
    @State private var newName = ""
    @State private var removing: PickupPerson?
    @State private var error: String?

    var body: some View {
        Section {
            ForEach(people ?? []) { p in
                HStack(spacing: 12) {
                    InitialsAvatar(name: p.name, color: Palette.stable(for: p.name), size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(.subheadline.weight(.semibold))
                        Text(p.relation ?? String(localized: "Tilføjet af jer")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    if p.suggestionId != nil {
                        Button(role: .destructive) { removing = p } label: { Label("Fjern", systemImage: "trash") }
                    }
                }
            }
            if people == nil { ProgressView() }
            Button { newName = ""; adding = true } label: { Label("Tilføj person", systemImage: "person.badge.plus") }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Må hente \(child.firstName)")
        } footer: {
            Text("Navnene kan vælges, når I melder hvem der henter. Swipe for at fjerne et navn I selv har tilføjet.")
        }
        .task { await load() }
        .alert("Tilføj person", isPresented: $adding) {
            TextField("Navn, fx Mormor Lise", text: $newName)
            Button("Tilføj") { Task { await add() } }.disabled(newName.trimmingCharacters(in: .whitespaces).count < 2)
            Button("Annuller", role: .cancel) {}
        }
        .confirmationDialog("Fjern \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil },
                                                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Fjern", role: .destructive) { if let p = removing { Task { await remove(p) } } }
        }
    }

    private func load() async {
        if Demo.isOn {
            people = [PickupPerson(id: "1", name: "Sara Ghafouri", relation: "Mor", suggestionId: nil),
                      PickupPerson(id: "2", name: "Mormor Lise", relation: nil, suggestionId: 2)]
            return
        }
        do { people = try await AulaAPI.shared.pickupPeople(childId: child.id) }
        catch { self.error = error.localizedDescription; people = people ?? [] }
    }

    private func add() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        do {
            if !Demo.isOn { try await AulaAPI.shared.addPickupPerson(name, childIds: [child.id]) }
            await load()
        } catch { self.error = String(localized: "Ikke gemt: \(error.localizedDescription)") }
    }

    private func remove(_ p: PickupPerson) async {
        guard let id = p.suggestionId else { return }
        do {
            if !Demo.isOn { try await AulaAPI.shared.removePickupPerson(suggestionId: id) }
            await load()
        } catch { self.error = String(localized: "Ikke ændret: \(error.localizedDescription)") }
    }
}

/// Opening hours for the next two weeks and upcoming closed days.
struct OpeningHoursSection: View {
    let institutionCodes: [String]
    @State private var days: [OpeningDay]?
    @State private var closed: [ClosedDays] = []

    var body: some View {
        Section {
            if let days {
                let upcoming = closed.filter { $0.end >= Calendar.week.startOfDay(for: .now) }.prefix(5)
                ForEach(days.prefix(10)) { d in
                    HStack {
                        Text(d.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).capitalized)
                            .font(.subheadline)
                            .fontWeight(Calendar.current.isDateInToday(d.date) ? .bold : .regular)
                        Spacer()
                        if d.isClosed || (d.open == nil && d.close == nil) {
                            Text(d.name ?? String(localized: "Lukket")).font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                        } else {
                            Text("\(d.open ?? "?") – \(d.close ?? "?")").font(.subheadline.monospacedDigit())
                                .foregroundStyle(d.isSpecial ? Color.orange : Color.primary)
                        }
                    }
                }
                if !upcoming.isEmpty {
                    ForEach(Array(upcoming)) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.subheadline.weight(.semibold))
                            Text(Self.range(c)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if days.isEmpty && upcoming.isEmpty {
                    Text("Institutionen har ikke lagt åbningstider i Aula.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Åbningstider og lukkedage")
        } footer: {
            Text("Orange tider er ændrede åbningstider.")
        }
        .task { await load() }
    }

    static func range(_ c: ClosedDays) -> String {
        let f = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        return Calendar.week.isDate(c.start, inSameDayAs: c.end) ? c.start.formatted(f) : "\(c.start.formatted(f)) – \(c.end.formatted(f))"
    }

    private func load() async {
        guard !institutionCodes.isEmpty, !Demo.isOn else { days = days ?? []; return }
        let from = Calendar.week.startOfDay(for: .now)
        let to = Calendar.week.date(byAdding: .day, value: 14, to: from) ?? from
        days = ((try? await AulaAPI.shared.openingDays(institutionCodes: institutionCodes, from: from, to: to)) ?? [])
            .filter { !Calendar.week.isDateInWeekend($0.date) || $0.open != nil }
        closed = (try? await AulaAPI.shared.closedDays(institutionCodes: institutionCodes)) ?? []
    }
}

/// "Komme/gå" in Mere: every child's times, who may pick up, and opening hours.
struct PresenceHubView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ThemedList {
            Section("Børn") {
                ForEach(app.children) { c in
                    NavigationLink(value: Route.child(c)) {
                        HStack(spacing: 12) {
                            ChildAvatar(child: c, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).font(.subheadline.weight(.semibold))
                                Text("Tider, ferie, sygemelding og hvem der må hente").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            OpeningHoursSection(institutionCodes: Array(Set(app.children.compactMap(\.institutionCode))).sorted())
        }
        .navigationTitle("Komme/gå")
    }
}
