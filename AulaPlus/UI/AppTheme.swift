import Observation
import SwiftUI

/// Selectable colour themes. Each has a brand colour, a second colour for gradients,
/// and a soft "wash" that tints the top of every screen.
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case apricot, ocean, forest, sunset, lavender, graphite

    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .apricot: return "Abrikos"
        case .ocean: return "Hav"
        case .forest: return "Skov"
        case .sunset: return "Solnedgang"
        case .lavender: return "Lavendel"
        case .graphite: return "Grafit"
        }
    }

    /// (light, dark) RGB for the brand colour. Dark variants are lifted for contrast on black.
    private var brandRGB: ((Double, Double, Double), (Double, Double, Double)) {
        switch self {
        case .apricot: return ((0.87, 0.40, 0.11), (1.00, 0.62, 0.35))
        case .ocean: return ((0.16, 0.40, 0.93), (0.36, 0.58, 1.00))
        case .forest: return ((0.10, 0.52, 0.36), (0.26, 0.76, 0.52))
        case .sunset: return ((0.90, 0.33, 0.22), (1.00, 0.50, 0.36))
        case .lavender: return ((0.45, 0.32, 0.88), (0.66, 0.56, 1.00))
        case .graphite: return ((0.24, 0.29, 0.37), (0.72, 0.77, 0.84))
        }
    }

    private var secondaryRGB: (Double, Double, Double) {
        switch self {
        case .apricot: return (1.00, 0.76, 0.40)
        case .ocean: return (0.20, 0.74, 0.95)
        case .forest: return (0.55, 0.80, 0.30)
        case .sunset: return (0.99, 0.66, 0.22)
        case .lavender: return (0.90, 0.45, 0.80)
        case .graphite: return (0.50, 0.58, 0.68)
        }
    }

    var brand: Color {
        let (l, d) = brandRGB
        return Color(UIColor { tc in
            let c = tc.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Text/icon colour on top of `brand`: dark on the light graphite dark-mode brand, else white.
    var onBrand: Color {
        let isGraphite = self == .graphite
        return Color(UIColor { tc in
            isGraphite && tc.userInterfaceStyle == .dark ? .black : .white
        })
    }

    var secondary: Color { Color(red: secondaryRGB.0, green: secondaryRGB.1, blue: secondaryRGB.2) }

    /// Child colours that would be confused with this theme's brand colour.
    var clashingChildColors: [Color] {
        switch self {
        case .apricot: return [.orange, .brown]
        case .ocean: return [.indigo]
        case .forest: return [.green, .mint, .teal]
        case .sunset: return [.orange, .brown]
        case .lavender: return [.purple, .indigo, .pink]
        case .graphite: return [.brown]
        }
    }

    /// Fixed (light) brand colour for gradients behind white text.
    var gradientStart: Color { Color(red: brandRGB.0.0, green: brandRGB.0.1, blue: brandRGB.0.2) }

    var gradient: LinearGradient {
        LinearGradient(colors: [gradientStart, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            WidgetWriter.update()
        }
    }
    private init() {
        let demo = UserDefaults.standard.string(forKey: "demoTheme")
        theme = AppTheme(rawValue: demo ?? UserDefaults.standard.string(forKey: "theme") ?? "") ?? .apricot
    }
}

extension Color {
    /// The current theme's brand colour. Reading it inside `body` tracks theme changes.
    @MainActor static var brand: Color { ThemeStore.shared.theme.brand }
    @MainActor static var brand2: Color { ThemeStore.shared.theme.secondary }
    @MainActor static var onBrand: Color { ThemeStore.shared.theme.onBrand }
}

/// Soft brand tint at the top of a screen fading into the grouped background.
struct ThemeBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = ThemeStore.shared.theme
        ZStack {
            Color.canvas
            LinearGradient(colors: [t.secondary.opacity(scheme == .dark ? 0.12 : 0.16),
                                    t.brand.opacity(scheme == .dark ? 0.05 : 0.04),
                                    .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
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
