import PhotosUI
import SwiftUI

/// One contact on its own page: big photo and everything Aula shares about them.
struct ContactDetailView: View {
    let contact: Contact
    @State private var messaging = false
    @Environment(\.openURL) private var openURL

    private var phones: [(String, String)] {
        var out: [(String, String)] = []
        for (label, n) in [(String(localized: "Mobil"), contact.mobilePhone), (String(localized: "Hjem"), contact.homePhone),
                           (String(localized: "Arbejde"), contact.workPhone)] {
            if let n, !out.contains(where: { $0.1 == n }) { out.append((label, n)) }
        }
        for p in contact.phones where !out.contains(where: { $0.1 == p }) { out.append((String(localized: "Telefon"), p)) }
        return out
    }

    var body: some View {
        ThemedList {
            Section {
                VStack(spacing: 12) {
                    BigAvatar(name: contact.name, url: contact.pictureURL, size: 180)
                    Text(contact.name).font(.title2.bold()).multilineTextAlignment(.center)
                    if let sub = [Self.roleName(contact.role), contact.group, contact.institutionName].compactMap({ $0 }).first {
                        Text(sub).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    HStack(spacing: 14) {
                        if let p = phones.first { action("Ring", "phone.fill") { open("tel:", p.1) } }
                        if let p = contact.mobilePhone ?? phones.first?.1 { action("SMS", "message.fill") { open("sms:", p) } }
                        if let e = contact.email { action("Mail", "envelope.fill") { open("mailto:", e) } }
                        action("Besked", "bubble.left.fill") { messaging = true }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            if !phones.isEmpty || contact.email != nil {
                Section("Kontakt") {
                    ForEach(phones, id: \.1) { p in
                        Button { open("tel:", p.1) } label: { LabeledContent(p.0, value: p.1) }
                            .contextMenu { Button("Kopiér") { UIPasteboard.general.string = p.1 } }
                    }
                    if let e = contact.email {
                        Button { open("mailto:", e) } label: { LabeledContent("E-mail", value: e) }
                            .contextMenu { Button("Kopiér") { UIPasteboard.general.string = e } }
                    }
                }
                .tint(.primary)
            }
            if let rel = contact.relations, !rel.isEmpty {
                Section(contact.role == "child" ? "Forældre" : "Børn") {
                    ForEach(rel, id: \.self) { r in
                        HStack(spacing: 12) {
                            InitialsAvatar(name: r.name, color: Palette.stable(for: r.name), size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.name).font(.subheadline.weight(.semibold))
                                if let d = r.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            let info: [(String, String)] = [
                (String(localized: "Rolle"), Self.roleName(contact.institutionRole) ?? Self.roleName(contact.role)),
                (String(localized: "Gruppe"), contact.group),
                (String(localized: "Institution"), contact.institutionName),
                (String(localized: "Fødselsdag"), contact.birthday?.formatted(.dateTime.day().month(.wide).year())),
                (String(localized: "Adresse"), contact.address),
            ].compactMap { k, v in v.map { (k, $0) } }
            if !info.isEmpty {
                Section("Om") { ForEach(info, id: \.0) { LabeledContent($0.0, value: $0.1) } }
            }
        }
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $messaging) {
            ComposeView(initialRecipients: [Recipient(id: contact.id, name: contact.name, detail: contact.detail, type: "Profile")]) { _ in
                messaging = false
            }
        }
    }

    private func action(_ title: LocalizedStringKey, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).frame(width: 52, height: 52)
                    .background(Color.brand.opacity(0.14), in: Circle())
                Text(title).font(.caption)
            }
        }
        .buttonStyle(.plain)
    }

    private func open(_ scheme: String, _ value: String) {
        let v = scheme == "mailto:" ? value : value.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: scheme + v) { openURL(url) }
    }

    static func roleName(_ role: String?) -> String? {
        switch role?.lowercased() {
        case "guardian": String(localized: "Forælder")
        case "child", "daycare", "early-student", "middle-late-student": String(localized: "Barn")
        case "employee": String(localized: "Ansat")
        case "preschool-teacher": String(localized: "Pædagog")
        case "teacher": String(localized: "Lærer")
        case "leader": String(localized: "Leder")
        case "pedagogue": String(localized: "Pædagog")
        case nil, "": nil
        default: role
        }
    }
}

/// A large round photo, or initials when there's none.
struct BigAvatar: View {
    let name: String
    let url: URL?
    var size: CGFloat = 160
    var image: UIImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    InitialsAvatar(name: name, color: Palette.stable(for: name), size: size)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 4))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

/// "Min profil": my photo, phone numbers and e-mail, as on aula.dk.
struct MyProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var profiles: [MyProfile]?
    @State private var saved: [MyProfile] = []
    @State private var error: String?
    @State private var note: String?
    @State private var saving = false
    @State private var pick: PhotosPickerItem?
    @State private var newPicture: UIImage?
    @State private var uploading = false

    var body: some View {
        ThemedForm {
            if let first = profiles?.first {
                Section {
                    VStack(spacing: 12) {
                        BigAvatar(name: first.name, url: first.pictureURL, size: 160, image: newPicture)
                            .overlay { if uploading { ProgressView().controlSize(.large) } }
                        Text(first.name).font(.title2.bold())
                        if first.canEditPicture {
                            PhotosPicker(selection: $pick, matching: .images) {
                                Label("Skift profilbillede", systemImage: "camera.fill")
                            }
                            .disabled(uploading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            if let binding = Binding($profiles) {
                ForEach(binding) { $p in
                    Section {
                        Group {
                            LabeledField("Mobil", text: $p.mobilePhone, placeholder: "Tilføj nummer").keyboardType(.phonePad).textContentType(.telephoneNumber)
                            LabeledField("Hjemme", text: $p.homePhone, placeholder: "Tilføj nummer").keyboardType(.phonePad)
                            if !p.isChild { LabeledField("Arbejde", text: $p.workPhone, placeholder: "Tilføj nummer").keyboardType(.phonePad) }
                            LabeledField("E-mail", text: $p.email, placeholder: "Tilføj e-mail").keyboardType(.emailAddress).textContentType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        .disabled(!p.canEditContact)
                        if let a = p.address { LabeledContent("Adresse", value: a) }
                    } header: {
                        Text(p.isChild ? p.name : (p.institutionName ?? String(localized: "Kontaktoplysninger")))
                    } footer: {
                        if p.id == profiles?.last?.id {
                            Text("Personale og andre forældre kan se det, institutionen deler i kontaktlisten.")
                        }
                    }
                }
            }
            if let note { Section { Label(note, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
        }
        .overlay { if profiles == nil && error == nil { ProgressView() } }
        .navigationTitle("Min profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else {
                    Button("Gem") { Task { await save() } }.disabled(profiles == nil || profiles! == saved)
                }
            }
        }
        .task { await load() }
        .onChange(of: pick) { _, item in if let item { Task { await upload(item) } } }
    }

    private func load() async {
        if Demo.isOn {
            let p = MyProfile(id: 1, profileId: 1, name: "Majid Ghafouri", institutionName: "Valby Skole", institutionCode: nil,
                              email: "far@example.dk", mobilePhone: "20 30 40 50", homePhone: "", workPhone: "",
                              pictureURL: nil, canEditPicture: true)
            profiles = [p]; saved = [p]
            return
        }
        do {
            let s = try await AulaAPI.shared.bootstrap()
            let list = try await AulaAPI.shared.myProfiles(institutionProfileIds: s.guardianProfileIds ?? [])
            profiles = list
            saved = list
        } catch {
            self.error = String(localized: "Kunne ikke hente din profil: \(error.localizedDescription)")
        }
    }

    private func save() async {
        guard let profiles else { return }
        let changed = profiles.filter { p in saved.first { $0.id == p.id } != p }
        guard !changed.isEmpty else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            if !Demo.isOn { try await AulaAPI.shared.saveContactInfo(changed) }
            saved = profiles
            note = String(localized: "Gemt på Aula")
        } catch {
            self.error = String(localized: "Ikke gemt: \(error.localizedDescription)")
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        defer { pick = nil }
        guard let first = profiles?.first,
              let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        // A square, reasonably small JPEG, like Aula's own crop.
        let side = min(img.size.width, img.size.height)
        let crop = CGRect(x: (img.size.width - side) / 2, y: (img.size.height - side) / 2, width: side, height: side)
        let target = CGSize(width: 800, height: 800)
        let square = UIGraphicsImageRenderer(size: target).image { _ in
            img.draw(in: CGRect(x: -crop.minX * target.width / side, y: -crop.minY * target.height / side,
                                width: img.size.width * target.width / side, height: img.size.height * target.height / side))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else { return }
        newPicture = square
        uploading = true
        error = nil
        defer { uploading = false }
        do {
            if !Demo.isOn { try await AulaAPI.shared.uploadProfilePicture(jpeg, for: first, allProfiles: true) }
            note = String(localized: "Profilbillede skiftet")
            // The new picture shows everywhere (front page, settings, children) once the session is fetched again.
            await app.session.refresh()
        } catch {
            newPicture = nil
            self.error = String(localized: "Billedet blev ikke skiftet: \(error.localizedDescription)")
        }
    }
}

/// A form row with its label always visible (placeholders vanish once a field is filled in).
struct LabeledField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var placeholder: LocalizedStringKey = ""

    init(_ label: LocalizedStringKey, text: Binding<String>, placeholder: LocalizedStringKey = "") {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        LabeledContent {
            TextField(placeholder, text: $text).multilineTextAlignment(.trailing)
        } label: {
            Text(label)
        }
    }
}
