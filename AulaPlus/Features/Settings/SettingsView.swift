import SwiftUI

struct SettingsView: View {
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
            List {
                if let s = app.session.value {
                    Section("Logget ind som") {
                        HStack(spacing: 12) {
                            InitialsAvatar(name: s.displayName, color: ThemeStore.shared.theme.gradientStart, size: 40)
                            Text(s.displayName).font(.headline)
                        }
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
                    Toggle(isOn: Binding(get: { app.lockEnabled }, set: { app.lockEnabled = $0 })) {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "faceid", color: .green)
                            Text("Lås med Face ID")
                        }
                    }
                } footer: {
                    Text("Aula+ tjekker for nyt i baggrunden, når iOS tillader det (typisk hvert 15.–60. minut).")
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
