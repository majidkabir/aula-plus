import QuickLook
import SwiftUI

/// Stable colour per child, used across calendar, cards and avatars.
enum Palette {
    static let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .indigo, .red]
    static func color(for childId: Int, in children: [Child]) -> Color {
        let i = children.firstIndex { $0.id == childId } ?? abs(childId)
        return colors[i % colors.count]
    }
}

struct ChildAvatar: View {
    let child: Child
    var size: CGFloat = 40
    @Environment(AppModel.self) private var app

    var body: some View {
        let color = Palette.color(for: child.id, in: app.children)
        AsyncImage(url: child.pictureURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(String(child.firstName.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(color.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(color, lineWidth: 2))
    }
}

/// Horizontal "Alle / Emma / Noah" chips shown at the top of each tab.
struct ChildFilterBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        if app.children.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: String(localized: "Alle"), color: .accentColor, selected: app.selectedChildId == nil) {
                        app.selectedChildId = nil
                    }
                    ForEach(app.children) { child in
                        chip(title: child.firstName,
                             color: Palette.color(for: child.id, in: app.children),
                             selected: app.selectedChildId == child.id) {
                            app.selectedChildId = child.id
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .sensoryFeedback(.selection, trigger: app.selectedChildId)
        }
    }

    private func chip(title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? color : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Small banner shown when the data on screen is from cache and a refresh failed.
struct StaleBanner: View {
    let error: String?
    let savedAt: Date?

    var body: some View {
        if let error {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                VStack(alignment: .leading, spacing: 2) {
                    Text(error).lineLimit(2)
                    if let savedAt {
                        Text("Viser data fra \(savedAt.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AttachmentList: View {
    let attachments: [Attachment]
    @State private var preview: URL?
    @State private var loading: Attachment?
    @State private var error: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(attachments, id: \.self) { a in
                    Button { open(a) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: a.isLink == true ? "link" : Self.icon(for: a.name))
                                .frame(width: 22)
                            Text(a.name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            if loading == a { ProgressView().controlSize(.small) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(a.url == nil || loading != nil)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .font(.subheadline)
            .quickLookPreview($preview)
        }
    }

    private func open(_ a: Attachment) {
        guard let url = a.url else { return }
        if a.isLink == true { openURL(url); return }
        loading = a
        error = nil
        Task {
            defer { loading = nil }
            do { preview = try await AulaAPI.shared.download(url, suggestedName: a.name) }
            catch { self.error = String(localized: "Kunne ikke hente \(a.name).") }
        }
    }

    static func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "gif": return "photo"
        case "mp4", "mov": return "film"
        case "doc", "docx", "pages": return "doc.text"
        case "xls", "xlsx", "numbers": return "tablecells"
        default: return "paperclip"
        }
    }
}

enum Fmt {
    static func listDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return String(localized: "I går") }
        if let days = cal.dateComponents([.day], from: d, to: .now).day, days < 7 {
            return d.formatted(.dateTime.weekday(.wide)).capitalized
        }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}
