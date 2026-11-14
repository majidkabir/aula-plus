import SwiftUI

/// Design tokens shared by every screen ("playful": warm cream, rounded type, soft big cards).
enum Theme {
    static let cardRadius: CGFloat = 24
    static let rowRadius: CGFloat = 16
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        func ui(_ v: UInt32) -> UIColor {
            UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        self.init(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    /// Screen background: warm cream (light), warm near-black (dark).
    static let canvas = Color(light: 0xFFF6EC, dark: 0x16110D)
    /// Card surface on top of `canvas`.
    static let card = Color(light: 0xFFFFFF, dark: 0x251E19)
    /// Quiet fill for chips, inputs and inner boxes.
    static let cardSoft = Color(light: 0xF6E8D9, dark: 0x352B23)
    /// Warm secondary text.
    static let inkSoft = Color(light: 0x8E705A, dark: 0xB9A594)
    /// Soft warm shadow under cards (none in dark mode).
    static let cardShadow = Color(UIColor { $0.userInterfaceStyle == .dark
        ? .clear : UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 0.09) })
}

extension View {
    /// Standard card surface: white, big round corners, soft warm shadow.
    func cardStyle(padding: CGFloat = Theme.pad) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: .cardShadow, radius: 14, x: 0, y: 6)
    }

    /// A card tinted with a child's (or any) colour: pastel fill, no shadow.
    func pastelCard(_ color: Color, padding: CGFloat = Theme.pad) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Color.card)
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(color.opacity(0.16))
            }
            .shadow(color: .cardShadow, radius: 14, x: 0, y: 6)
    }
}

/// `List` on the warm canvas, every row on a card-coloured (or clear) background.
struct ThemedList<Content: View>: View {
    var rowBackground: Color = .card
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }.listRowBackground(rowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(ThemeBackground())
    }
}

/// `Form` on the warm canvas with card-coloured rows.
struct ThemedForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Group { content }.listRowBackground(Color.card)
        }
        .scrollContentBackground(.hidden)
        .background(ThemeBackground())
    }
}

/// Section title with an SF Symbol and an optional count badge.
struct SectionTitle: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var count: Int? = nil
    var tint: Color = Color.brand

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(title).font(.title3.weight(.heavy))
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small coloured capsule naming a child.
struct ChildTag: View {
    let name: String
    let color: Color
    var body: some View {
        Text(name)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Coloured rounded square behind an SF Symbol (Settings-style list icon).
struct IconTile: View {
    let systemImage: String
    let color: Color
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Initials in a circle, used when there is no photo.
struct InitialsAvatar: View {
    let name: String
    var color: Color = .gray
    var size: CGFloat = 32
    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// One week switcher used everywhere: ‹  Uge 46 · 9.–15. nov.  ›
struct WeekSwitcher: View {
    @Binding var date: Date

    private var start: Date { Week.start(of: date) }
    private var end: Date { Calendar.week.date(byAdding: .day, value: 6, to: start) ?? start }

    var body: some View {
        HStack(spacing: 4) {
            Button { shift(-7) } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
                    .background(Color.cardSoft, in: Circle())
            }
            .accessibilityLabel(Text("Forrige uge"))
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text("Uge \(Week.isoWeek(date).week)").font(.headline)
                Text("\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onTapGesture { date = .now }
            Spacer(minLength: 0)
            Button { shift(7) } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
                    .background(Color.cardSoft, in: Circle())
            }
            .accessibilityLabel(Text("Næste uge"))
        }
        .font(.body.weight(.semibold))
        .sensoryFeedback(.selection, trigger: Week.key(date))
    }

    private func shift(_ days: Int) {
        date = Calendar.week.date(byAdding: .day, value: days, to: date) ?? date
    }
}
