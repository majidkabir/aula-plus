import SwiftUI

/// What Aula itself notifies about (push from the Aula app and e-mail), same settings as on aula.dk.
struct AulaNotificationSettingsView: View {
    @State private var settings: AulaNotificationSettings?
    @State private var saved: AulaNotificationSettings?
    @State private var error: String?
    @State private var saving = false
    @State private var savedNote = false

    var body: some View {
        ThemedForm {
            if let binding = Binding($settings) {
                content(binding)
            } else if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .overlay { if settings == nil && error == nil { ProgressView() } }
        .navigationTitle("Aula-notifikationer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else {
                    Button("Gem") { Task { await save() } }.disabled(settings == nil || settings == saved)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder private func content(_ s: Binding<AulaNotificationSettings>) -> some View {
        Section {
            if s.wrappedValue.pushAvailable { Toggle("Push i Aula-appen", isOn: s.push) }
            if s.wrappedValue.emailAvailable { Toggle("E-mail", isOn: s.email) }
        } header: { Text("Hvordan") } footer: {
            Text("Det er Aulas egne notifikationer. Aula+ giver besked om nyt for sig selv.")
        }
        Section("Hvornår") {
            Toggle("Med det samme", isOn: s.instant)
            if !s.wrappedValue.instant {
                DatePicker("Daglig opsummering kl.", selection: timeBinding(s), displayedComponents: .hourAndMinute)
                ForEach(0..<7, id: \.self) { i in
                    Toggle(Self.dayNames[i], isOn: s.days[i])
                }
            }
        }
        Section("Beskeder fra") {
            Toggle("Personale", isOn: s.fromEmployees)
            Toggle("Forældre", isOn: s.fromGuardians)
            Toggle("Børn", isOn: s.fromChildren)
        }
        Section("Andet") {
            Toggle("Kalender", isOn: s.calendar)
            Toggle("Galleri", isOn: s.gallery)
            Toggle("Opslag", isOn: s.posts)
        }
        if !s.wrappedValue.comeGo.isEmpty {
            Section("Komme/gå") {
                ForEach(s.comeGo) { $t in Toggle(t.title, isOn: $t.on) }
            }
        }
        if !s.wrappedValue.widgets.isEmpty {
            Section("Værktøjer") {
                ForEach(s.widgets) { $t in Toggle(t.title, isOn: $t.on) }
            }
        }
        if savedNote {
            Section { Label("Gemt på Aula", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        }
        if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
    }

    static let dayNames = [String(localized: "Mandag"), String(localized: "Tirsdag"), String(localized: "Onsdag"),
                           String(localized: "Torsdag"), String(localized: "Fredag"), String(localized: "Lørdag"),
                           String(localized: "Søndag")]

    private func timeBinding(_ s: Binding<AulaNotificationSettings>) -> Binding<Date> {
        Binding(get: {
            let t = s.wrappedValue.scheduledTime ?? "0800"
            let h = Int(t.prefix(2)) ?? 8, m = Int(t.suffix(2)) ?? 0
            return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: .now) ?? .now
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            s.wrappedValue.scheduledTime = String(format: "%02d%02d", c.hour ?? 8, c.minute ?? 0)
        })
    }

    private func load() async {
        if Demo.isOn {
            let d = AulaNotificationSettings(instant: true, scheduledTime: "0800", days: Array(repeating: false, count: 7),
                                             push: true, pushAvailable: true, email: false, emailAvailable: true,
                                             fromEmployees: true, fromGuardians: true, fromChildren: true, calendar: true,
                                             gallery: true, posts: true, substitute: false, lessonNote: false,
                                             comeGo: [.init(id: "PickupActivity", title: String(localized: "Afhentning"), on: true)],
                                             widgets: [])
            settings = d; saved = d
            return
        }
        do {
            let s = try await AulaAPI.shared.notificationSettings()
            settings = s
            saved = s
        } catch {
            self.error = String(localized: "Kunne ikke hente indstillingerne: \(error.localizedDescription)")
        }
    }

    private func save() async {
        guard let s = settings else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            if !Demo.isOn { try await AulaAPI.shared.saveNotificationSettings(s) }
            saved = s
            savedNote = true
        } catch {
            self.error = String(localized: "Ikke gemt: \(error.localizedDescription)")
        }
    }
}

/// An iCal link from Aula, so events show up in the phone's own calendar and stay updated.
struct CalendarFeedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var feeds: [CalendarFeed]?
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false
    @State private var confirmDelete: CalendarFeed?

    var body: some View {
        ThemedForm {
            if let feeds {
                if let f = feeds.first {
                    Section {
                        if let url = f.oneYear ?? f.oneWeek {
                            Button {
                                openURL(Self.webcal(url))
                            } label: { Label("Abonnér i Kalender", systemImage: "calendar.badge.plus") }
                            Button {
                                UIPasteboard.general.url = url
                                copied = true
                            } label: { Label(copied ? String(localized: "Kopieret") : String(localized: "Kopiér link"),
                                             systemImage: copied ? "checkmark" : "doc.on.doc") }
                        }
                        if let w = f.oneWeek, f.oneYear != nil {
                            Button { openURL(Self.webcal(w)) } label: {
                                Label("Abonnér (kun næste uge)", systemImage: "calendar")
                            }
                        }
                    } footer: {
                        Text("Kalender-appen henter ændringer fra Aula af sig selv. Linket er personligt – del det ikke.")
                    }
                    Section {
                        Button("Slet kalenderlink", role: .destructive) { confirmDelete = f }
                    }
                } else {
                    Section {
                        Button { Task { await create() } } label: {
                            Label("Opret kalenderlink", systemImage: "link.badge.plus")
                        }
                        .disabled(busy)
                    } footer: {
                        Text("Aula laver et personligt link med begivenheder, ferier, ture og møder. Når du opretter det, accepterer du Aulas vilkår for kalenderdeling: begivenhederne kopieres til din kalender, og Aula kan ikke slette dem derfra igen.")
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
        }
        .overlay { if feeds == nil && error == nil || busy { ProgressView() } }
        .navigationTitle("Kalender på telefonen")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Slet kalenderlinket?", isPresented: Binding(get: { confirmDelete != nil },
                                                                         set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Slet", role: .destructive) { if let f = confirmDelete { Task { await delete(f) } } }
        } message: { Text("Abonnementer på linket holder op med at blive opdateret.") }
        .task { await load() }
    }

    static func webcal(_ url: URL) -> URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = "webcal"
        return c?.url ?? url
    }

    private func load() async {
        if Demo.isOn { feeds = []; return }
        do { feeds = try await AulaAPI.shared.calendarFeeds() }
        catch { self.error = error.localizedDescription }
    }

    private func create() async {
        guard let me = app.session.value?.guardianProfileIds?.first else {
            error = String(localized: "Kunne ikke finde din profil. Træk ned for at opdatere.")
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await AulaAPI.shared.createCalendarFeed(institutionProfileId: me)
            feeds = try await AulaAPI.shared.calendarFeeds()
        } catch {
            self.error = String(localized: "Ikke oprettet: \(error.localizedDescription)")
        }
    }

    private func delete(_ f: CalendarFeed) async {
        busy = true
        defer { busy = false }
        do {
            try await AulaAPI.shared.deleteCalendarFeed(f.id)
            feeds = try await AulaAPI.shared.calendarFeeds()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
