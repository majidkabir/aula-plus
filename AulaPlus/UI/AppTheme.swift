import Observation
import SwiftUI

/// Selectable colour themes. Each has a brand colour, a second colour for gradients,
/// and a soft "wash" that tints the top of every screen.
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case ocean, forest, sunset, lavender, graphite

    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .ocean: return "Hav"
        case .forest: return "Skov"
        case .sunset: return "Solnedgang"
        case .lavender: return "Lavendel"
        case .graphite: return "Grafit"
        }
    }

    var brand: Color {
        switch self {
        case .ocean: return Color(red: 0.16, green: 0.40, blue: 0.93)
        case .forest: return Color(red: 0.10, green: 0.56, blue: 0.40)
        case .sunset: return Color(red: 0.93, green: 0.36, blue: 0.24)
        case .lavender: return Color(red: 0.47, green: 0.34, blue: 0.90)
        case .graphite: return Color(red: 0.25, green: 0.30, blue: 0.38)
        }
    }

    var secondary: Color {
        switch self {
        case .ocean: return Color(red: 0.20, green: 0.74, blue: 0.95)
        case .forest: return Color(red: 0.55, green: 0.80, blue: 0.30)
        case .sunset: return Color(red: 0.99, green: 0.66, blue: 0.22)
        case .lavender: return Color(red: 0.90, green: 0.45, blue: 0.80)
        case .graphite: return Color(red: 0.50, green: 0.58, blue: 0.68)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [brand, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    private init() {
        let demo = UserDefaults.standard.string(forKey: "demoTheme")
        theme = AppTheme(rawValue: demo ?? UserDefaults.standard.string(forKey: "theme") ?? "") ?? .ocean
    }
}

extension Color {
    /// The current theme's brand colour. Reading it inside `body` tracks theme changes.
    @MainActor static var brand: Color { ThemeStore.shared.theme.brand }
    @MainActor static var brand2: Color { ThemeStore.shared.theme.secondary }
}

/// Soft brand tint at the top of a screen fading into the grouped background.
struct ThemeBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = ThemeStore.shared.theme
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [t.brand.opacity(scheme == .dark ? 0.28 : 0.16),
                                    t.secondary.opacity(scheme == .dark ? 0.10 : 0.06),
                                    .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Standard themed screen background.
    func themedBackground() -> some View { background(ThemeBackground()) }
}

/// Row of theme swatches.
struct ThemePicker: View {
    private var store = ThemeStore.shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTheme.allCases) { t in
                Button {
                    withAnimation(.snappy) { store.theme = t }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(t.gradient).frame(width: 44, height: 44)
                            if store.theme == t {
                                Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().strokeBorder(store.theme == t ? t.brand : .clear, lineWidth: 2).padding(-4))
                        Text(t.name).font(.caption2.weight(store.theme == t ? .semibold : .regular))
                            .foregroundStyle(store.theme == t ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(t.name))
                .accessibilityAddTraits(store.theme == t ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: store.theme)
    }
}
