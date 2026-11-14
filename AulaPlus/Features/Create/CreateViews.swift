import PhotosUI
import SwiftUI

// MARK: Photos to send

/// A photo picked on the phone, ready to upload (downsized JPEG).
struct PickedPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let preview: UIImage

    static func make(_ data: Data, maxSide: Int = 2048) -> PickedPhoto? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxSide]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        guard let jpeg = img.jpegData(compressionQuality: 0.82) else { return nil }
        return PickedPhoto(jpeg: jpeg, preview: img)
    }
}

/// "Vedhæft billeder": picker plus a strip of what's picked (tap ✕ to remove).
struct PhotoPickerStrip: View {
    @Binding var photos: [PickedPhoto]
    var maxCount = 20
    var label: LocalizedStringKey = "Vedhæft billeder"
    @State private var items: [PhotosPickerItem] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $items, maxSelectionCount: maxCount, matching: .images) {
                HStack {
                    Label(label, systemImage: "photo.badge.plus")
                    if loading { Spacer(); ProgressView() }
                }
            }
            .onChange(of: items) { _, picked in
                guard !picked.isEmpty else { return }
                Task {
                    loading = true
                    for item in picked {
                        if let d = try? await item.loadTransferable(type: Data.self), let p = PickedPhoto.make(d) {
                            photos.append(p)
                        }
                    }
                    items = []
                    loading = false
                }
            }
            if !photos.isEmpty { PhotoThumbStrip(photos: $photos) }
        }
    }
}

struct PhotoThumbStrip: View {
    @Binding var photos: [PickedPhoto]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { p in
                    Image(uiImage: p.preview).resizable().scaledToFill()
                        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            Button { photos.removeAll { $0.id == p.id } } label: {
                                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .padding(2)
                            .accessibilityLabel(Text("Fjern billede"))
                        }
                }
            }
        }
    }
}

extension AulaAPI {
    /// Uploads picked photos as the guardian at the right institution and returns their media ids.
    func upload(_ photos: [PickedPhoto], institutionCode: String? = nil, albumId: Int? = nil,
                progress: ((Int) -> Void)? = nil) async throws -> [Int] {
        guard !photos.isEmpty else { return [] }
        let owners = try await ownerProfiles()
        guard let owner = owners.first(where: { $0.institutionCode == institutionCode }) ?? owners.first else {
            throw AulaError.decoding("profiles.getProfileContext")
        }
        var ids: [Int] = []
        for (i, p) in photos.enumerated() {
            ids.append(try await uploadPhoto(p.jpeg, name: "billede-\(i + 1).jpg", owner: owner.institutionProfileId,
                                             institutionCode: owner.institutionCode, albumId: albumId))
            progress?(i + 1)
        }
        return ids
    }
}

// MARK: New event

struct CreateEventView: View {
    let day: Date
    let done: (Bool) -> Void
    @State private var form: NewEvent
    @State private var owners: [OwnerProfile] = []
    @State private var owner: OwnerProfile?
    @State private var query = ""
    @State private var results: [Recipient] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var hasDeadline = false
    @State private var saving = false
    @State private var error: String?

    init(day: Date, done: @escaping (Bool) -> Void) {
        self.day = day
        self.done = done
        var cal = Calendar(identifier: .gregorian); cal.timeZone = AulaDate.copenhagen
        let start = cal.date(bySettingHour: 16, minute: 0, second: 0, of: day) ?? day
        _form = State(initialValue: NewEvent(start: start, end: start.addingTimeInterval(7200)))
    }

    private var canSave: Bool { !form.title.trimmingCharacters(in: .whitespaces).isEmpty && form.end >= form.start && owner != nil && !saving }

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    TextField("Titel", text: $form.title)
                    Picker("Type", selection: $form.type) {
                        ForEach(NewEventType.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Sted", text: $form.location)
                }
                Section {
                    Toggle("Hele dagen", isOn: $form.allDay)
                    DatePicker("Start", selection: $form.start, displayedComponents: form.allDay ? .date : [.date, .hourAndMinute])
                        .onChange(of: form.start) { old, new in form.end = form.end.addingTimeInterval(new.timeIntervalSince(old)) }
                    DatePicker("Slut", selection: $form.end, in: form.start..., displayedComponents: form.allDay ? .date : [.date, .hourAndMinute])
                }
                Section("Inviter") {
                    ForEach(form.invitees) { r in
                        HStack {
                            Text(r.name)
                            Spacer()
                            Button { form.invitees.removeAll { $0.id == r.id } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    TextField("Søg forælder, barn, gruppe …", text: $query)
                        .textInputAutocapitalization(.words)
                        .onChange(of: query) { _, q in search(q) }
                    ForEach(results.filter { r in !form.invitees.contains { $0.id == r.id } }) { r in
                        Button {
                            form.invitees.append(r); query = ""; results = []
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).foregroundStyle(.primary)
                                if let d = r.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if !form.invitees.isEmpty {
                        Toggle("Kræver svar", isOn: $form.responseRequired)
                        if form.responseRequired {
                            Toggle("Svarfrist", isOn: $hasDeadline)
                            if hasDeadline {
                                DatePicker("Svar senest", selection: Binding(get: { form.responseDeadline ?? form.start },
                                                                              set: { form.responseDeadline = $0 }),
                                           in: ...form.start)
                            }
                        }
                    }
                }
                Section {
                    TextField("Beskrivelse", text: $form.description, axis: .vertical).lineLimit(3...12)
                    Toggle("Privat", isOn: $form.isPrivate)
                } footer: {
                    Text("Private begivenheder viser kun tidspunktet for andre end de inviterede.")
                }
                if owners.count > 1 {
                    Section {
                        Picker("Institution", selection: $owner) {
                            ForEach(owners, id: \.self) { Text($0.institutionName).tag(Optional($0)) }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Ny begivenhed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuller") { done(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Opret") { Task { await save() } }.disabled(!canSave) }
                }
            }
            .task {
                if Demo.isOn { owner = OwnerProfile(institutionProfileId: 1, institutionCode: "1", institutionName: "Demo"); return }
                do { owners = try await AulaAPI.shared.ownerProfiles(); owner = owners.first }
                catch { self.error = error.localizedDescription }
            }
        }
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

    private func save() async {
        guard let owner else { return }
        saving = true; error = nil
        defer { saving = false }
        if !hasDeadline { form.responseDeadline = nil }
        do {
            if !Demo.isOn { try await AulaAPI.shared.createEvent(form, owner: owner) }
            done(true)
        } catch {
            self.error = String(localized: "Begivenheden blev ikke oprettet: \(error.localizedDescription)")
        }
    }
}

// MARK: New album / add photos

struct CreateAlbumView: View {
    let done: (Bool) -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var groups: [AulaGroup] = []
    @State private var chosen: Set<Int> = []
    @State private var photos: [PickedPhoto] = []
    @State private var owners: [OwnerProfile] = []
    @State private var uploaded = 0
    @State private var saving = false
    @State private var error: String?

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !chosen.isEmpty && !saving }

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    TextField("Albumnavn", text: $title)
                    TextField("Beskrivelse", text: $text, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    if groups.isEmpty { ProgressView() }
                    ForEach(groups) { g in
                        Button {
                            if chosen.contains(g.id) { chosen.remove(g.id) } else { chosen.insert(g.id) }
                        } label: {
                            HStack {
                                Text(g.name).foregroundStyle(.primary)
                                Spacer()
                                if chosen.contains(g.id) { Image(systemName: "checkmark").foregroundStyle(Color.brand) }
                            }
                        }
                    }
                } header: { Text("Del med") } footer: { Text("Albummet kan ses af medlemmerne i de valgte grupper.") }
                Section { PhotoPickerStrip(photos: $photos, maxCount: 100, label: "Vælg billeder") }
                if saving && !photos.isEmpty {
                    Section { ProgressView(value: Double(uploaded), total: Double(photos.count)) { Text("Uploader \(uploaded) af \(photos.count)") } }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Nyt album")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuller") { done(false) }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Opret") { Task { await save() } }.disabled(!canSave) }
                }
            }
            .task {
                if Demo.isOn { groups = [AulaGroup(id: 1, name: "Solsikken")]; return }
                do {
                    async let g = AulaAPI.shared.myGroups()
                    async let o = AulaAPI.shared.ownerProfiles()
                    (groups, owners) = try await (g, o)
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func save() async {
        let picked = groups.filter { chosen.contains($0.id) }
        let code = picked.first?.institutionCode
        guard Demo.isOn || !owners.isEmpty else { return }
        saving = true; error = nil; uploaded = 0
        defer { saving = false }
        do {
            if !Demo.isOn {
                let owner = owners.first { $0.institutionCode == code } ?? owners[0]
                guard let id = try await AulaAPI.shared.createAlbum(title: title, description: text, groups: picked, owner: owner) else {
                    throw AulaError.decoding("gallery.createAlbum")
                }
                _ = try await AulaAPI.shared.upload(photos, institutionCode: owner.institutionCode, albumId: id) { n in uploaded = n }
            }
            done(true)
        } catch {
            self.error = String(localized: "Albummet blev ikke oprettet: \(error.localizedDescription)")
        }
    }
}

/// "Tilføj billeder" to an album that already exists.
struct AddPhotosView: View {
    let album: Album
    let done: (Bool) -> Void
    @State private var photos: [PickedPhoto] = []
    @State private var uploaded = 0
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section { PhotoPickerStrip(photos: $photos, maxCount: 100, label: "Vælg billeder") }
                if saving {
                    Section { ProgressView(value: Double(uploaded), total: Double(max(photos.count, 1))) { Text("Uploader \(uploaded) af \(photos.count)") } }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(album.title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuller") { done(false) }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Upload") { Task { await save() } }.disabled(photos.isEmpty)
                    }
                }
            }
        }
    }

    private func save() async {
        saving = true; error = nil; uploaded = 0
        defer { saving = false }
        do {
            if !Demo.isOn { _ = try await AulaAPI.shared.upload(photos, albumId: album.id) { n in uploaded = n } }
            done(true)
        } catch {
            self.error = String(localized: "Billederne blev ikke uploadet: \(error.localizedDescription)")
        }
    }
}

// MARK: Meeting times

/// Bookable times for a school-home talk or parent meeting.
struct MeetingSlotsSection: View {
    let detail: EventDetail
    /// Who I book for: my children (or me), by institution profile id → name.
    let people: [(id: Int, name: String)]
    let reload: () async -> Void
    @State private var who: Int?
    @State private var busy = false
    @State private var error: String?

    private var person: Int? { who ?? people.first?.id }
    private func mine(_ id: Int) -> MeetingSlot? { detail.slots.first { $0.bookedFor == id } }

    var body: some View {
        Section {
            if people.count > 1 {
                Picker("For", selection: Binding(get: { person ?? 0 }, set: { who = $0 })) {
                    ForEach(people, id: \.id) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
            }
            if let p = person, let booked = mine(p) {
                HStack {
                    Label(slotText(booked), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Afmeld", role: .destructive) { Task { await run { try await AulaAPI.shared.cancelBooking(eventId: detail.id, slot: booked, for: p) } } }
                        .buttonStyle(.bordered).disabled(busy || detail.deadlineExceeded)
                }
            }
            ForEach(groupedDays, id: \.0) { day, slots in
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(slots) { s in slotButton(s) }
                    }
                }
                .padding(.vertical, 2)
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        } header: {
            Text("Vælg tid")
        } footer: {
            Text(detail.deadlineExceeded ? String(localized: "Svarfristen er overskredet.") : String(localized: "Tryk på en ledig tid for at booke den."))
        }
    }

    private var groupedDays: [(Date, [MeetingSlot])] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = AulaDate.copenhagen
        return Dictionary(grouping: detail.slots) { cal.startOfDay(for: $0.start) }
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func slotText(_ s: MeetingSlot) -> String {
        "\(s.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \(Fmt.time(s.start))–\(Fmt.time(s.end))"
    }

    @ViewBuilder private func slotButton(_ s: MeetingSlot) -> some View {
        let isMine = person != nil && s.bookedFor == person
        let taken = (s.bookedFor != nil || s.blocked) && !isMine
        Button {
            guard let p = person, !taken, !isMine else { return }
            Task {
                await run {
                    if mine(p) != nil { try await AulaAPI.shared.moveBooking(eventId: detail.id, to: s, for: p) }
                    else { try await AulaAPI.shared.bookSlot(eventId: detail.id, slot: s, for: p) }
                }
            }
        } label: {
            Text(Fmt.time(s.start)).font(.subheadline.monospacedDigit())
                .strikethrough(taken)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isMine ? Color.green.opacity(0.25) : taken ? Color.gray.opacity(0.12) : Color.brand.opacity(0.15),
                            in: Capsule())
                .foregroundStyle(taken ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(taken || busy || detail.deadlineExceeded)
        .accessibilityLabel(Text(taken ? String(localized: "\(Fmt.time(s.start)), optaget") : Fmt.time(s.start)))
    }

    private func run(_ action: () async throws -> Void) async {
        busy = true; error = nil
        defer { busy = false }
        do { if !Demo.isOn { try await action() }; await reload() }
        catch { self.error = String(localized: "Ikke gemt: \(error.localizedDescription)") }
    }
}

/// Wraps its children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}
