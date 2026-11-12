import SwiftUI

struct EventDetailView: View {
    let event: Event
    @Environment(AppModel.self) private var app
    @State private var detail: EventDetail?
    @State private var error: String?
    @State private var busy = false
    @State private var addToCalendar = false

    /// Invitees that are me or one of my children — the ones I can answer for.
    private var mine: [EventDetail.Invitee] {
        let ids = Set((app.session.value?.guardianProfileIds ?? []) + app.children.map(\.id))
        return (detail?.invitees ?? []).filter { $0.institutionProfileId.map(ids.contains) ?? false }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail?.title ?? event.title).font(.title3.bold())
                    Label(timeText, systemImage: "clock").font(.subheadline)
                    if let loc = detail?.location ?? event.location {
                        Label(loc, systemImage: "mappin.and.ellipse").font(.subheadline)
                    }
                    if let c = detail?.creator {
                        Label(c, systemImage: "person").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if event.hasSubstitute {
                        Label("Vikar\(event.substitute.map { ": \($0)" } ?? "")", systemImage: "arrow.triangle.swap")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            if let html = detail?.html.nilIfEmpty {
                Section("Beskrivelse") { HTMLText(html: html) }
            }

            if let d = detail, d.responseRequired, !mine.isEmpty {
                Section {
                    ForEach(mine, id: \.self) { invitee in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(invitee.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text((invitee.response ?? .waiting).label).font(.caption).foregroundStyle(.secondary)
                            }
                            if !d.deadlineExceeded, let pid = invitee.institutionProfileId {
                                HStack {
                                    rsvpButton(.accepted, pid: pid, current: invitee.response, color: .green)
                                    rsvpButton(.tentative, pid: pid, current: invitee.response, color: .orange)
                                    rsvpButton(.declined, pid: pid, current: invitee.response, color: .red)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Svar")
                } footer: {
                    if let dl = d.responseDeadline {
                        Text(d.deadlineExceeded ? String(localized: "Svarfristen er overskredet.") : String(localized: "Svarfrist \(dl.formatted(date: .abbreviated, time: .shortened))"))
                    }
                }
            }

            if let a = detail?.attachments, !a.isEmpty {
                Section("Filer") { AttachmentList(attachments: a) }
            }

            if let invitees = detail?.invitees, invitees.count > mine.count {
                Section("Inviterede (\(invitees.count))") {
                    ForEach(invitees, id: \.self) { i in
                        HStack {
                            Text(i.name)
                            Spacer()
                            if let r = i.response, r != .waiting {
                                let look = Self.look(r)
                                Image(systemName: look.0).foregroundStyle(look.1)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Begivenhed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addToCalendar = true } label: { Image(systemName: "calendar.badge.plus") }
            }
        }
        .sheet(isPresented: $addToCalendar) {
            AddToCalendarSheet(event: event, childNames: event.childIds.compactMap { app.child($0)?.firstName })
                .ignoresSafeArea()
        }
        .task { await load() }
        .refreshable { await load() }
    }

    static func look(_ r: RSVP) -> (String, Color) {
        switch r {
        case .accepted: return ("checkmark.circle.fill", .green)
        case .declined: return ("xmark.circle.fill", .red)
        case .tentative, .waiting: return ("questionmark.circle.fill", .orange)
        }
    }

    private var timeText: String {
        let start = detail?.start ?? event.start
        let end = detail?.end ?? event.end
        if detail?.allDay ?? event.allDay {
            return start.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
        }
        return "\(start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) – \(Fmt.time(end))"
    }

    private func rsvpButton(_ r: RSVP, pid: Int, current: RSVP?, color: Color) -> some View {
        Button {
            Task { await respond(r, pid: pid) }
        } label: {
            Text(r.label).font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(current == r ? color : .gray)
        .disabled(busy)
    }

    private func load() async {
        do {
            detail = try await AulaAPI.shared.eventDetail(id: event.id)
            error = nil
        } catch {
            // Lessons often have no detail page; the summary above is enough.
            if detail == nil, !(error is AulaError) { self.error = error.localizedDescription }
        }
    }

    private func respond(_ r: RSVP, pid: Int) async {
        guard let id = detail?.id else { return }
        busy = true
        defer { busy = false }
        do {
            try await AulaAPI.shared.respond(eventId: id, as: pid, response: r)
            await load()
        } catch {
            self.error = String(localized: "Svaret blev ikke sendt: \(error.localizedDescription)")
        }
    }
}
