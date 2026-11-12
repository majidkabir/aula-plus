import SwiftUI

struct MessagesView: View {
    @Environment(AppModel.self) private var app
    @Environment(DataStore.self) private var data
    @State private var search = ""
    @State private var onlyUnread = false
    @State private var older: [ThreadSummary] = []
    @State private var nextPage = 1
    @State private var loadingOlder = false

    private var threads: [ThreadSummary] {
        var seen = Set<String>()
        let all = ((data.threads.value ?? []) + older).filter { seen.insert($0.id).inserted }
        return all.filter { t in
            if onlyUnread && t.isRead { return false }
            if let id = app.selectedChildId, let child = app.child(id), !t.regarding.isEmpty,
               !t.regarding.contains(where: { $0.localizedCaseInsensitiveContains(child.firstName) }) {
                return false
            }
            guard !search.isEmpty else { return true }
            return [t.subject, t.sender, t.preview].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ChildFilterBar().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    StaleBanner(error: data.threads.error, savedAt: data.threads.savedAt)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                .listSectionSeparator(.hidden)

                ForEach(threads) { t in
                    NavigationLink(value: t) { ThreadRow(thread: t) }
                }

                if search.isEmpty && !threads.isEmpty {
                    Button {
                        Task { await loadOlder() }
                    } label: {
                        HStack {
                            Spacer()
                            if loadingOlder { ProgressView() } else { Text("Hent ældre beskeder") }
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if threads.isEmpty {
                    if data.threads.isLoading { ProgressView() }
                    else { ContentUnavailableView(onlyUnread ? "Ingen ulæste beskeder" : "Ingen beskeder",
                                                  systemImage: "tray") }
                }
            }
            .searchable(text: $search, prompt: "Søg i beskeder")
            .navigationTitle("Beskeder")
            .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $onlyUnread) {
                        Image(systemName: onlyUnread ? "envelope.badge.fill" : "envelope.badge")
                    }
                    .toggleStyle(.button)
                }
            }
            .refreshable {
                older = []
                nextPage = 1
                await data.threads.refresh()
            }
            .task { await data.threads.load(maxAge: 30) }
        }
    }

    private func loadOlder() async {
        guard !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        if let page = try? await AulaAPI.shared.threads(page: nextPage) {
            older += page.threads
            nextPage += 1
        }
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(thread.isRead ? Color.clear : Color.accentColor)
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.sender.isEmpty ? "Aula" : thread.sender)
                        .font(.subheadline.weight(thread.isRead ? .regular : .bold))
                        .lineLimit(1)
                    Spacer()
                    Text(Fmt.listDate(thread.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if thread.isSensitive {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    Text(thread.subject)
                        .font(.subheadline.weight(thread.isRead ? .regular : .semibold))
                        .lineLimit(1)
                }
                if !thread.preview.isEmpty {
                    Text(thread.preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !thread.regarding.isEmpty {
                    Text(thread.regarding.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
