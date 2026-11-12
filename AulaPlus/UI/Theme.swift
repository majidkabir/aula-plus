import SwiftUI

/// Design tokens shared by every screen.
enum Theme {
    static let cardRadius: CGFloat = 18
    static let rowRadius: CGFloat = 12
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12
}

extension View {
    /// Standard card surface used on grouped backgrounds.
    func cardStyle(padding: CGFloat = Theme.pad) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
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
            Text(title).font(.title3.weight(.bold))
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
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Coloured rounded square behind an SF Symbol (Settings-style list icon).
struct IconTile: View {
    let systemImage: String
    let color: Color
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
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
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
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
