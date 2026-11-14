import SwiftUI

struct SettingsView: View {
    @State private var lock = AppLock.shared
    var embedded = false
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    @State private var notificationsOn = BackgroundRefresh.isEnabled
    @State private var language: String = (UserDefaults.standard.array(forKey: "AppleLanguagesOverride") as? [String])?.first ?? ""

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
            ThemedList {
                if let s = app.session.value {
                    Section("Logget ind som") {
                        HStack(spacing: 12) {
                            InitialsAvatar(name: s.displayName, color: ThemeStore.shared.theme.gradientStart, size: 40)
                            Text(s.displayName).font(.headline)
                        }
                        NavigationLink { MyProfileView() } label: { Label("Rediger profil, billede og telefon", systemImage: "pencil") }
                    }
                    Section("Børn") {
                        ForEach(s.children) { c in
                            HStack(spacing: 12) {
                                ChildAvatar(child: c, size: 36)
                                VStack(alignment: .leading) {
                                    Text(c.name)
                                    Text(c.institutionName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Tema") {
                    ThemePicker()
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }
                Section {
                    Toggle(isOn: $notificationsOn) {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "bell.badge.fill", color: .red)
                            Text("Notifikationer om nye beskeder og opslag")
                        }
                    }
                    .onChange(of: notificationsOn) { _, on in
                        Task {
                            if on { notificationsOn = await BackgroundRefresh.requestPermission() }
                            else { BackgroundRefresh.disable() }
                        }
                    }
                } footer: {
                    Text("Aula+ tjekker for nyt i baggrunden, når iOS tillader det (typisk hvert 15.–60. minut).")
                }
                Section {
                    NavigationLink { AulaNotificationSettingsView() } label: {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "app.badge.fill", color: .orange)
                            Text("Aula-notifikationer")
                        }
                    }
                    NavigationLink { CalendarFeedView() } label: {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "calendar.badge.plus", color: .blue)
                            Text("Kalender på telefonen")
                        }
                    }
                } header: { Text("Aula") }
                Section {
                    Toggle(isOn: Binding(get: { ParentTaskFinder.shared.isEnabled },
                                         set: { ParentTaskFinder.shared.isEnabled = $0 })) {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "checklist", color: .orange)
                            Text("Find det, jeg skal gøre")
                        }
                    }
                    Button(role: .destructive) { ParentTaskFinder.shared.eraseAll() } label: { Text("Glem fundne opgaver") }
                } footer: {
                    Text(ParentTaskFinder.usesAI
                         ? "Apple Intelligence læser nye beskeder og opslag på telefonen og samler det, du skal huske. Intet sendes nogen steder hen."
                         : "Aula+ finder ting som \"husk\", \"medbring\" og \"senest\" i nye beskeder og opslag. Med Apple Intelligence (iPhone 15 Pro eller nyere) bliver det mere præcist. Alt sker på telefonen.")
                }
                Section {
                    Toggle(isOn: Binding(get: { FaceIndex.shared.isEnabled }, set: { FaceIndex.shared.isEnabled = $0 })) {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "face.smiling", color: .purple)
                            Text("Find mine børn på billeder")
                        }
                    }
                    Button(role: .destructive) { FaceIndex.shared.eraseAll() } label: {
                        Text("Slet ansigtsdata")
                    }
                } footer: {
                    Text("Aula+ genkender dine børns ansigter på billeder uden tag. Alt sker på telefonen: intet sendes nogen steder, og andre børns ansigter gemmes ikke.")
                }
                Section {
                    Toggle(isOn: Binding(get: { lock.isEnabled }, set: { on in
                        if on { Task { await lock.enable() } } else { lock.disable() }
                    })) {
                        HStack(spacing: 12) {
                            IconTile(systemImage: lock.symbol, color: .green)
                            Text("Lås med \(lock.methodName)")
                        }
                    }
                    .disabled(!lock.isAvailable && !lock.isEnabled)
                    if lock.isEnabled {
                        Picker(selection: $lock.delay) {
                            ForEach(AppLock.Delay.allCases) { Text($0.label).tag($0) }
                        } label: {
                            HStack(spacing: 12) {
                                IconTile(systemImage: "timer", color: .orange)
                                Text("Lås igen")
                            }
                        }
                    }
                } footer: {
                    if lock.isAvailable {
                        Text("Beskeder og kalender skjules, når du skifter app, og kræver \(lock.methodName) for at åbne igen.")
                    } else {
                        Text("Slå en kode til på telefonen for at kunne låse Aula+.")
                    }
                }
                Section {
                    Picker(selection: $language) {
                        Text("Automatisk").tag("")
                        Text(verbatim: "Dansk").tag("da")
                        Text(verbatim: "English").tag("en")
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "globe", color: .blue)
                            Text("Sprog")
                        }
                    }
                    .onChange(of: language) { _, lang in
                        if lang.isEmpty {
                            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                            UserDefaults.standard.removeObject(forKey: "AppleLanguagesOverride")
                        } else {
                            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
                            UserDefaults.standard.set([lang], forKey: "AppleLanguagesOverride")
                        }
                    }
                } footer: {
                    Text("Kræver genstart af appen.")
                }
                Section {
                    Button("Ryd cache") { DiskCache.clear() }
                    Button("Log ud", role: .destructive) { confirmLogout = true }
                }
                Section {
                    Text("Aula+ er en uofficiel app og er ikke lavet af eller godkendt af Aula/KOMBIT. Den bruger samme API som Aulas egen app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) { Button("Færdig") { dismiss() } }
                }
            }
            .confirmationDialog("Log ud af Aula+?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Log ud", role: .destructive) {
                    Task {
                        await app.logout()
                        dismiss()
                    }
                }
            }
    }
}
