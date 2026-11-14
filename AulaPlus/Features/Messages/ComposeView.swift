import SwiftUI

/// New message: search recipients, subject, text.
struct ComposeView: View {
    var initialRecipients: [Recipient] = []
    /// A saved draft to continue.
    var draft: MessageDraft? = nil
    let done: (Bool) -> Void
    @Environment(DataStore.self) private var data
    @State private var askSave = false

    @State private var query = ""
    @State private var results: [Recipient] = []
    @State private var recipients: [Recipient] = []
    @State private var subject = ""
    @State private var text = ""
    @State private var sensitive = false
    @State private var photos: [PickedPhoto] = []
    @State private var sending = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    private var canSend: Bool {
        !recipients.isEmpty && !subject.trimmingCharacters(in: .whitespaces).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section("Til") {
                    if !recipients.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(recipients) { r in
                                    Button {
                                        recipients.removeAll { $0.id == r.id }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(r.name).lineLimit(1)
                                            Image(systemName: "xmark.circle.fill").font(.caption)
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.brand.opacity(0.15), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    TextField("Søg lærer, pædagog, forælder…", text: $query)
                        .textInputAutocapitalization(.words)
                        .onChange(of: query) { _, q in search(q) }
                    ForEach(results.filter { r in !recipients.contains { $0.id == r.id } }) { r in
                        Button {
                            recipients.append(r)
                            query = ""
                            results = []
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).foregroundStyle(.primary)
                                if let d = r.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section {
                    TextField("Emne", text: $subject)
                    TextField("Besked", text: $text, axis: .vertical).lineLimit(6...20)
                }
                Section { PhotoPickerStrip(photos: $photos) }
                Section {
                    Toggle("Følsom besked", isOn: $sensitive)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .onAppear {
                if let draft, recipients.isEmpty, subject.isEmpty, text.isEmpty {
                    recipients = draft.recipients
                    subject = draft.subject
                    text = draft.text
                    sensitive = draft.sensitive
                }
                if recipients.isEmpty { recipients = initialRecipients }
            }
            .interactiveDismissDisabled(hasContent)
            .confirmationDialog("Gem som kladde?", isPresented: $askSave, titleVisibility: .visible) {
                Button("Gem kladde") { saveDraft(); done(false) }
                Button("Slet", role: .destructive) {
                    if let draft { data.deleteDraft(draft.id) }
                    done(false)
                }
            } message: { Text("Kladder gemmes kun på denne telefon.") }
            .navigationTitle("Ny besked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuller") { if hasContent { askSave = true } else { done(false) } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else { Button("Send") { Task { await send() } }.disabled(!canSend) }
                }
            }
        }
    }

    private var hasContent: Bool {
        let changed = draft.map { $0.subject != subject || $0.text != text || $0.recipients != recipients } ?? true
        return changed && (!subject.trimmingCharacters(in: .whitespaces).isEmpty
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func saveDraft() {
        data.saveDraft(MessageDraft(id: draft?.id ?? UUID(), recipients: recipients, subject: subject, text: text,
                                    sensitive: sensitive, savedAt: .now))
    }

    private func search(_ q: String) {
        searchTask?.cancel()
        let term = q.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = (try? await AulaAPI.shared.findRecipients(term)) ?? []
            if !Task.isCancelled { results = found }
        }
    }

    private func send() async {
        sending = true
        error = nil
        defer { sending = false }
        do {
            let ids = try await AulaAPI.shared.upload(photos)
            try await AulaAPI.shared.startThread(subject: subject, text: text, recipients: recipients, sensitive: sensitive,
                                                 attachmentIds: ids)
            if let draft { data.deleteDraft(draft.id) }
            done(true)
        } catch {
            self.error = String(localized: "Beskeden blev ikke sendt: \(error.localizedDescription)")
        }
    }
}
