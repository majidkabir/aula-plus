import SwiftUI

struct SettingsView: View {
    var embedded = false
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    @State private var notificationsOn = BackgroundRefresh.isEnabled

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
            List {
                if let s = app.session.value {
                    Section("Logget ind som") {
                        Text(s.displayName).font(.headline)
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
                Section {
                    Toggle(isOn: $notificationsOn) {
                        Label("Notifikationer om nye beskeder og opslag", systemImage: "bell.badge")
                    }
                    .onChange(of: notificationsOn) { _, on in
                        Task {
                            if on { notificationsOn = await BackgroundRefresh.requestPermission() }
                            else { BackgroundRefresh.disable() }
                        }
                    }
                    Toggle(isOn: Binding(get: { app.lockEnabled }, set: { app.lockEnabled = $0 })) {
                        Label("Lås med Face ID", systemImage: "faceid")
                    }
                } footer: {
                    Text("Aula+ tjekker for nyt i baggrunden, når iOS tillader det (typisk hvert 15.–60. minut).")
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
