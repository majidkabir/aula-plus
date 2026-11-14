import SwiftUI

/// Menu items for moving a thread: the inbox and every folder except the one it's in.
struct MoveToFolderItems: View {
    let thread: ThreadSummary
    var currentFolderId: Int?
    let move: (Int?) -> Void
    @Environment(DataStore.self) private var data

    var body: some View {
        if currentFolderId != nil {
            Button { move(nil) } label: { Label("Indbakke", systemImage: "tray") }
        }
        ForEach((data.folders.value ?? []).filter { $0.id != currentFolderId }) { f in
            Button { move(f.id) } label: {
                Label(f.isDeleted ? String(localized: "Slettet post") : f.name,
                      systemImage: f.isDeleted ? "trash" : "folder")
            }
        }
    }
}

/// Create, rename and delete your own message folders.
struct FoldersView: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    @State private var naming: MailFolder?
    @State private var creating = false
    @State private var name = ""
    @State private var deleting: MailFolder?
    @State private var busy = false
    @State private var error: String?

    private var own: [MailFolder] { (data.folders.value ?? []).filter { !$0.isDeleted } }

    var body: some View {
        NavigationStack {
            ThemedList {
                Section {
                    ForEach(own) { f in
                        Button {
                            name = f.name
                            naming = f
                        } label: {
                            Label(f.name, systemImage: "folder").foregroundStyle(.primary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { deleting = f } label: { Label("Slet", systemImage: "trash") }
                        }
                    }
                    Button {
                        name = ""
                        creating = true
                    } label: { Label("Ny mappe", systemImage: "folder.badge.plus") }
                } footer: {
                    Text("Mapperne er de samme som på aula.dk. Tryk på en mappe for at omdøbe den, swipe for at slette.")
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .overlay { if busy { ProgressView() } }
            .navigationTitle("Mapper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Færdig") { dismiss() } } }
            .alert("Ny mappe", isPresented: $creating) {
                TextField("Navn", text: $name)
                Button("Opret") { run { try await AulaAPI.shared.createFolder(name: name) } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Annuller", role: .cancel) {}
            }
            .alert("Omdøb mappe", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Navn", text: $name)
                Button("Gem") {
                    if let f = naming { run { try await AulaAPI.shared.renameFolder(f.id, to: name) } }
                }
                Button("Annuller", role: .cancel) {}
            }
            .confirmationDialog("Slet mappen \"\(deleting?.name ?? "")\"?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    if let f = deleting { run { try await AulaAPI.shared.deleteFolder(f.id) } }
                }
            } message: { Text("Beskederne i mappen flyttes til Slettet post.") }
            .task { await data.folders.load(maxAge: 60) }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            busy = true
            error = nil
            defer { busy = false }
            do {
                try await action()
                await data.folders.refresh()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Aula's out-of-office reply ("Autosvar").
struct AutoReplyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current: AutoReply?
    @State private var loaded = false
    @State private var text = ""
    @State private var start = Date()
    @State private var hasEnd = true
    @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ThemedForm {
                if let current {
                    Section {
                        Label("Autosvar er slået til", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if let s = current.start {
                            LabeledContent("Fra", value: s.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let e = current.end {
                            LabeledContent("Til", value: e.formatted(date: .abbreviated, time: .shortened))
                        }
                        Button("Slå autosvar fra", role: .destructive) { Task { await remove(current) } }
                    }
                }
                Section {
                    TextField("Fx: Jeg er på ferie og svarer, når jeg er tilbage.", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                } header: { Text("Besked") }
                Section {
                    DatePicker("Fra", selection: $start)
                    Toggle("Slutdato", isOn: $hasEnd)
                    if hasEnd { DatePicker("Til", selection: $end, in: start...) }
                } footer: {
                    Text("Alle der skriver til dig i perioden, får automatisk dette svar.")
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .disabled(busy || !loaded)
            .overlay { if !loaded || busy { ProgressView() } }
            .navigationTitle("Autosvar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuller") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                if !Demo.isOn, let r = try? await AulaAPI.shared.autoReply() {
                    current = r
                    text = r.text
                    start = r.start ?? .now
                    hasEnd = r.end != nil
                    if let e = r.end { end = e }
                }
                loaded = true
            }
        }
    }

    private func save() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if !Demo.isOn {
                try await AulaAPI.shared.setAutoReply(text: text, start: start, end: hasEnd ? end : nil)
            }
            dismiss()
        } catch {
            self.error = String(localized: "Ikke gemt: \(error.localizedDescription)")
        }
    }

    private func remove(_ r: AutoReply) async {
        guard let id = r.id else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            if !Demo.isOn { try await AulaAPI.shared.deleteAutoReply(id: id) }
            current = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DraftRow: View {
    let draft: MessageDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(draft.recipients.map(\.name).joined(separator: ", ").nilIfEmpty ?? String(localized: "Ingen modtagere"))
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(Fmt.listDate(draft.savedAt)).font(.caption).foregroundStyle(.secondary)
            }
            Text(draft.subject.nilIfEmpty ?? String(localized: "(Intet emne)")).font(.subheadline).lineLimit(1)
            if !draft.text.isEmpty {
                Text(draft.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
