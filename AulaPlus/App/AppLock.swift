import LocalAuthentication
import SwiftUI

/// Face ID / Touch ID lock for the whole app, with the device passcode as fallback.
@MainActor
@Observable
final class AppLock {
    static let shared = AppLock()

    enum Delay: Int, CaseIterable, Identifiable {
        case immediately = 0, oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900
        var id: Int { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .immediately: "Med det samme"
            case .oneMinute: "Efter 1 minut"
            case .fiveMinutes: "Efter 5 minutter"
            case .fifteenMinutes: "Efter 15 minutter"
            }
        }
    }

    private static let enabledKey = "lock.enabled"
    private static let delayKey = "lock.delay"
    private static let offeredKey = "lock.offered"

    private(set) var isEnabled: Bool = UserDefaults.standard.bool(forKey: AppLock.enabledKey) {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    var delay: Delay = Delay(rawValue: UserDefaults.standard.integer(forKey: AppLock.delayKey)) ?? .immediately {
        didSet { UserDefaults.standard.set(delay.rawValue, forKey: Self.delayKey) }
    }
    /// Starts locked on a cold start; AppModel clears it when nobody is logged in.
    private(set) var isLocked: Bool = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
    /// One-time "lock with Face ID?" question after the first login.
    var showOffer = false

    private var backgroundedAt: Date?
    private var authenticating = false
    private var isActive = false
    /// Ask once on launch and once per return from the background — never on every activation:
    /// the Face ID sheet itself makes the app inactive/active, so that would loop after a cancel.
    private var wantsPrompt = true
    /// No prompt before the app knows whether anyone is logged in (else Face ID could pop up over the login screen).
    private var knowsLogin = false

    // MARK: What this device offers

    private var biometry: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    /// Face ID, Touch ID or at least a passcode is set up.
    var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    var methodName: String {
        switch biometry {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: String(localized: "kode")
        }
    }

    var symbol: String {
        switch biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.fill"
        }
    }

    // MARK: Lifecycle

    func didEnterBackground(loggedIn: Bool) {
        backgroundedAt = .now
        isActive = false
        wantsPrompt = true
        // Lock before iOS takes the app-switcher snapshot.
        if isEnabled && loggedIn && delay == .immediately { isLocked = true }
    }

    func didBecomeActive(loggedIn: Bool) {
        isActive = true
        if isEnabled, loggedIn, let since = backgroundedAt, Date.now.timeIntervalSince(since) >= Double(delay.rawValue) {
            isLocked = true
        }
        backgroundedAt = nil
        promptIfNeeded()
    }

    /// Called when the login state is known or changes.
    func sync(loggedIn: Bool) {
        if !loggedIn || !isEnabled { isLocked = false }
        knowsLogin = true
        promptIfNeeded()
    }

    private func promptIfNeeded() {
        guard isLocked, isActive, knowsLogin, wantsPrompt, !Demo.isOn else { return }
        wantsPrompt = false
        Task { await unlock() }
    }

    func showLockedForDemo() { isLocked = true }

    // MARK: Actions

    private func authenticate(_ reason: String) async -> Bool {
        guard !authenticating else { return false }
        authenticating = true
        defer { authenticating = false }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = String(localized: "Brug kode")
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
    }

    func unlock() async {
        // Passcode removed from the phone: there is nothing left to unlock with.
        guard isAvailable else { isLocked = false; return }
        if await authenticate(String(localized: "Lås Aula+ op")) { isLocked = false }
    }

    /// Turning the lock on needs one successful check, so nobody locks themselves out by accident.
    @discardableResult
    func enable() async -> Bool {
        guard isAvailable, await authenticate(String(localized: "Slå lås til for Aula+")) else { return false }
        isEnabled = true
        return true
    }

    func disable() {
        isEnabled = false
        isLocked = false
    }

    func offerAfterLogin() {
        guard !isEnabled, isAvailable, !UserDefaults.standard.bool(forKey: Self.offeredKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
        showOffer = true
    }
}

/// The app's mark, shared by the login and lock screens.
struct AppMark: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(LinearGradient(colors: [Color.brand, Color.brand.opacity(0.6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Text(verbatim: "A+").font(.system(size: size * 0.42, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmLogout = false
    private let lock = AppLock.shared

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            LinearGradient(colors: [Color.brand.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                AppMark(size: 84)
                Text("Aula+ er låst").font(.title2.bold())
                Text("Lås op for at se beskeder, kalender og fravær.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label(String(localized: "Lås op med \(lock.methodName)"), systemImage: lock.symbol)
                        .font(.headline).frame(maxWidth: .infinity)
                        .foregroundStyle(Color.onBrand)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brand)
                .controlSize(.large)
                Button("Log ud", role: .destructive) { confirmLogout = true }
                    .font(.subheadline)
            }
            .padding(32)
        }
        .confirmationDialog("Log ud af Aula+?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log ud", role: .destructive) { Task { await app.logout() } }
        } message: {
            Text("Du skal logge ind med MitID igen.")
        }
    }
}

/// Hides content in the app switcher when the lock waits before locking.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            AppMark(size: 72)
        }
    }
}
