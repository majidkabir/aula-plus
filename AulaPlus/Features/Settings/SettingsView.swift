import SwiftUI

struct SettingsView: View {
    var embedded = false
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false

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
