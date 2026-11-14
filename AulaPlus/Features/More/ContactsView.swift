import SwiftUI

struct ContactsView: View {
    @Environment(AppModel.self) private var app
    @State private var groups: [AulaGroup] = []
    @State private var groupsLoaded = Demo.isOn
    @State private var groupId: Int?
    @State private var filter = "guardian"
    @State private var contacts: Loadable<[Contact]>?
    @State private var search = ""
    @State private var messaging: Contact?

    private var shown: [Contact] {
        let all = contacts?.value ?? []
        guard !search.isEmpty else { return all }
        return all.filter { [$0.name, $0.detail ?? ""].contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        ThemedList {
            Section {
                if groups.count > 1 {
                    Picker("Gruppe", selection: $groupId) {
                        ForEach(groups) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Picker("Vis", selection: $filter) {
                    Text("Forældre").tag("guardian")
                    Text("Børn").tag("child")
                    Text("Ansatte").tag("employee")
                }
                .pickerStyle(.segmented)
            }
            if let c = contacts {
                StaleBanner(error: c.error, savedAt: c.savedAt).listRowSeparator(.hidden)
            }
            ForEach(shown) { c in
                NavigationLink(value: Route.contact(c)) {
                    ContactRow(contact: c) { messaging = c }
                }
            }
        }
        .overlay {
            if shown.isEmpty {
                if !groupsLoaded || (!groups.isEmpty && (contacts == nil || contacts?.isLoading == true)) { ProgressView() }
                else { ContentUnavailableView("Ingen kontakter", systemImage: "person.2") }
            }
        }
        .searchable(text: $search, prompt: String(localized: "Søg navn"))
        .navigationTitle("Kontakter")
        .task {
            if groups.isEmpty {
                groups = (try? await AulaAPI.shared.groups(childIds: app.children.map(\.id))) ?? []
                groupId = groupId ?? groups.first?.id
            }
            groupsLoaded = true
        }
        .task(id: "\(groupId ?? 0)-\(filter)") { await reload() }
        .refreshable { await contacts?.refresh() }
        .sheet(item: $messaging) { c in
            ComposeView(initialRecipients: [Recipient(id: c.id, name: c.name, detail: c.detail, type: "Profile")]) { _ in
                messaging = nil
            }
        }
    }

    private func reload() async {
        guard let gid = groupId else { return }
        let f = filter
        let l = Loadable<[Contact]>(key: "contacts-\(gid)-\(f)") {
            try await AulaAPI.shared.contacts(groupId: gid, filter: f)
        }
        contacts = l
        await l.load(maxAge: 86_400)
    }
}

struct ContactRow: View {
    let contact: Contact
    let onMessage: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: contact.pictureURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Text(String(contact.name.prefix(1)))
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.gradient)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.subheadline.weight(.semibold))
                if let d = contact.detail { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if let phone = contact.phones.first, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) { Image(systemName: "phone.fill") }
                    .buttonStyle(.borderless)
            }
            if let email = contact.email, let url = URL(string: "mailto:\(email)") {
                Link(destination: url) { Image(systemName: "envelope.fill") }
                    .buttonStyle(.borderless)
            }
            Button(action: onMessage) { Image(systemName: "bubble.left.fill") }
                .buttonStyle(.borderless)
        }
        .contextMenu {
            ForEach(contact.phones, id: \.self) { p in
                Button { UIPasteboard.general.string = p } label: { Label(p, systemImage: "phone") }
            }
            if let e = contact.email {
                Button { UIPasteboard.general.string = e } label: { Label(e, systemImage: "envelope") }
            }
        }
    }
}

struct DocumentsView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0
    @State private var docs: Loadable<[SecureDocument]>?
    @State private var files: Loadable<[CommonFile]>?

    var body: some View {
        ThemedList(rowBackground: .clear) {
            Picker("Vis", selection: $tab) {
                Text("Sikre dokumenter").tag(0)
                Text("Fælles filer").tag(1)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if tab == 0 {
                if let d = docs { StaleBanner(error: d.error, savedAt: d.savedAt).listRowSeparator(.hidden) }
                ForEach(docs?.value ?? []) { doc in
                    NavigationLink(value: Route.document(doc)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.title).font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                if let c = doc.category { Text(c) }
                                Text(Fmt.listDate(doc.updated))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                if let f = files { StaleBanner(error: f.error, savedAt: f.savedAt).listRowSeparator(.hidden) }
                ForEach(files?.value ?? []) { f in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(f.title).font(.subheadline.weight(.semibold))
                        if let i = f.institution { Text(i).font(.caption).foregroundStyle(.secondary) }
                        if let a = f.attachment { AttachmentList(attachments: [a]) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Dokumenter")
        .task {
            let guardianIds = app.session.value?.guardianProfileIds ?? []
            let codes = Array(Set(app.children.compactMap(\.institutionCode)))
            let d = docs ?? Loadable(key: "secure-docs") {
                try await AulaAPI.shared.secureDocuments(guardianProfileIds: guardianIds)
            }
            let f = files ?? Loadable(key: "common-files") {
                try await AulaAPI.shared.commonFiles(institutionCodes: codes)
            }
            docs = d
            files = f
            async let a: () = d.load(maxAge: 600)
            async let b: () = f.load(maxAge: 3600)
            _ = await (a, b)
        }
        .refreshable {
            await docs?.refresh()
            await files?.refresh()
        }
    }
}

struct DocumentDetailView: View {
    let doc: SecureDocument
    @State private var content: DocumentContent?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(doc.title).font(.title2.bold())
                HStack {
                    if let c = doc.creator { Text(c) }
                    Spacer()
                    Text(Fmt.listDate(doc.updated))
                }
                .font(.subheadline).foregroundStyle(.secondary)
                Divider()
                if let content {
                    if !content.html.isEmpty { HTMLText(html: content.html) }
                    AttachmentList(attachments: content.attachments)
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { content = try await AulaAPI.shared.documentContent(doc) }
            catch { self.error = error.localizedDescription }
        }
    }
}
