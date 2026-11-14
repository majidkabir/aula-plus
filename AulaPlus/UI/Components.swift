import QuickLook
import SwiftUI

/// Stable colour per child, used across calendar, cards and avatars.
enum Palette {
    /// Child colours never include the brand blue, so a child is never confused with a selected control.
    static let all: [Color] = [.orange, .teal, .pink, .purple, .green, .indigo, .mint, .brown,
                               Color(light: 0x2BA38E, dark: 0x4CC9B0), Color(light: 0x7A5AF0, dark: 0xA08BFF)]
    /// Child colours minus the ones that clash with the current theme.
    @MainActor static var colors: [Color] {
        let clash = ThemeStore.shared.theme.clashingChildColors
        return all.filter { !clash.contains($0) }
    }
    /// Same colour for the same name on every launch (for people without a child colour).
    static func stable(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return all[sum % all.count]
    }

    @MainActor static func color(for childId: Int, in children: [Child]) -> Color {
        let i = children.firstIndex { $0.id == childId } ?? abs(childId)
        return colors[i % colors.count]
    }
}

/// My own picture from Aula, or my initials.
struct MeAvatar: View {
    var size: CGFloat = 32
    @Environment(AppModel.self) private var app

    var body: some View {
        let name = app.session.value?.displayName ?? ""
        let initials = InitialsAvatar(name: name, color: ThemeStore.shared.theme.gradientStart, size: size)
        if let url = app.session.value?.pictureURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { initials }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initials
        }
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
                    chip(title: String(localized: "Alle"), color: Color.brand, onColor: Color.onBrand, selected: app.selectedChildId == nil) {
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

    private func chip(title: String, color: Color, onColor: Color = .white, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(selected ? color : Color.cardSoft, in: Capsule())
                .foregroundStyle(selected ? onColor : Color.primary)
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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kunne ikke opdatere").font(.subheadline.weight(.semibold))
                    Text(error).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    if let savedAt {
                        Text("Viser data fra \(savedAt.formatted(.relative(presentation: .named))). Træk ned for at prøve igen.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
            .accessibilityElement(children: .combine)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.cardStyle() }
}

struct AttachmentList: View {
    let attachments: [Attachment]
    @State private var preview: URL?
    @State private var loading: Attachment?
    @State private var error: String?
    @Environment(\.openURL) private var openURL

    private var photos: [Media] { attachments.compactMap(\.media) }
    private var files: [Attachment] { attachments.filter { $0.media == nil } }

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !photos.isEmpty { PhotoGrid(photos: photos) }
                ForEach(files, id: \.self) { a in
                    Button { open(a) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: a.isLink == true ? "link" : Self.icon(for: a.name))
                                .frame(width: 22)
                            Text(a.name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            if loading == a { ProgressView().controlSize(.small) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.cardSoft, in: RoundedRectangle(cornerRadius: 10))
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

/// Photos attached to a post or message, shown inline; tap to open them in the photo viewer.
struct PhotoGrid: View {
    let photos: [Media]
    var maxShown = 6
    @State private var viewing: Media?
    @Environment(AppModel.self) private var app

    var body: some View {
        let shown = Array(photos.prefix(maxShown))
        let extra = photos.count - shown.count
        Group {
            if shown.count == 1, let m = shown.first {
                tile(m, extra: 0).aspectRatio(4 / 3, contentMode: .fit)
            } else {
                let cols = shown.count == 2 || shown.count == 4 ? 2 : 3
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols), spacing: 4) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                        tile(m, extra: i == shown.count - 1 ? extra : 0).aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fullScreenCover(item: $viewing) { start in
            MediaViewer(items: photos, start: start, children: app.children)
        }
    }

    private func tile(_ m: Media, extra: Int) -> some View {
        Button { viewing = m } label: {
            Color.cardSoft
                .overlay {
                    CachedImage(key: "t\(m.id)", url: m.thumbURL ?? m.fullURL, maxPixel: photos.count == 1 ? 900 : 400, fallbacks: m.thumbFallbacks) {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
                .overlay {
                    if m.isVideo {
                        Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white).shadow(radius: 3)
                    }
                }
                .overlay {
                    if extra > 0 {
                        Color.black.opacity(0.45)
                        Text("+\(extra)").font(.title2.weight(.bold)).foregroundStyle(.white)
                    }
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.title ?? String(localized: "Billede"))
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
