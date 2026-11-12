import SwiftUI

struct VacationRequestsView: View {
    @Environment(DataStore.self) private var data
    @State private var answering: VacationRequest?

    var body: some View {
        List {
            StaleBanner(error: data.vacationRequests.error, savedAt: data.vacationRequests.savedAt)
                .listRowSeparator(.hidden)
            ForEach(data.vacationRequests.value ?? []) { r in
                Button { answering = r } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            if r.isMissingAnswer {
                                Text("Mangler svar").font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.red, in: Capsule()).foregroundStyle(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        Text("\(r.childName) · \(r.start.formatted(.dateTime.day().month(.abbreviated))) – \(r.end.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let d = r.deadline {
                            Text("Svarfrist \(d.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(r.isMissingAnswer ? .red : .secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!r.isEditable)
            }
        }
        .listStyle(.plain)
        .overlay {
            if (data.vacationRequests.value ?? []).isEmpty, !data.vacationRequests.isLoading {
                ContentUnavailableView("Ingen ferieanmodninger", systemImage: "sun.max")
            }
        }
        .navigationTitle("Ferieanmodninger")
        .refreshable { await data.vacationRequests.refresh() }
        .task { await data.vacationRequests.load(maxAge: 600) }
        .sheet(item: $answering) { r in
            VacationAnswerForm(request: r) { saved in
                answering = nil
                if saved { Task { await data.vacationRequests.refresh() } }
            }
        }
    }
}

struct VacationAnswerForm: View {
    let request: VacationRequest
    let done: (Bool) -> Void
    @State private var days: [VacationDayAnswer] = []
    @State private var comment = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let note = request.note {
                    Section { Text(note).font(.subheadline) }
                }
                Section {
                    HStack {
                        Button("Kommer alle dage") { setAll(true) }
                        Spacer()
                        Button("Kommer ikke") { setAll(false) }
                    }
                    .buttonStyle(.borderless)
                    ForEach($days) { $d in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $d.isComing) {
                                Text(d.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).capitalized)
                            }
                            if d.isComing && request.needsTimes {
                                HStack {
                                    TimeField(title: String(localized: "Afleveres"), hhmm: $d.entry, day: d.date)
                                    TimeField(title: String(localized: "Hentes"), hhmm: $d.exit, day: d.date)
                                }
                            }
                        }
                    }
                } header: {
                    Text(request.childName)
                }
                Section("Bemærkning") {
                    TextField("Valgfri", text: $comment, axis: .vertical)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuller") { done(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Send") { Task { await save() } } }
                }
            }
            .onAppear { if days.isEmpty { days = Self.days(for: request) } }
        }
    }

    static func days(for r: VacationRequest) -> [VacationDayAnswer] {
        var out: [VacationDayAnswer] = []
        var d = Calendar.week.startOfDay(for: r.start)
        let last = Calendar.week.startOfDay(for: r.end)
        while d <= last && out.count < 120 {
            let wd = Calendar.week.component(.weekday, from: d)
            if wd != 1 && wd != 7 { out.append(.init(date: d, isComing: false, entry: "08:00", exit: "16:00")) }
            d = Calendar.week.date(byAdding: .day, value: 1, to: d) ?? last.addingTimeInterval(86_400)
        }
        return out
    }

    private func setAll(_ coming: Bool) {
        for i in days.indices { days[i].isComing = coming }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await AulaAPI.shared.answerVacationRequest(request, days: days, comment: comment)
            done(true)
        } catch {
            self.error = String(localized: "Ikke sendt: \(error.localizedDescription)")
        }
    }
}

/// Compact hour:minute picker bound to an "HH:mm" string.
struct TimeField: View {
    let title: String
    @Binding var hhmm: String
    let day: Date

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { DayPlanEditor.time(hhmm, on: day) },
            set: { hhmm = DayPlanEditor.hhmm($0) }), displayedComponents: .hourAndMinute)
            .font(.caption)
    }
}
