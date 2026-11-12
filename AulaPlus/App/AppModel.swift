import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase { case launching, loggedOut, loggedIn }

    private(set) var phase: Phase = .launching
    private(set) var loginNotice: String?

    /// Profile, children, widgets. Cached so the app opens offline.
    let session: Loadable<Session>

    private init() {
        session = Loadable(key: "session") { try await AulaAPI.shared.bootstrap() }
    }

    /// nil = all children.
    var selectedChildId: Int?

    var children: [Child] { session.value?.children ?? [] }

    var visibleChildren: [Child] {
        guard let id = selectedChildId else { return children }
        return children.filter { $0.id == id }
    }

    func child(_ id: Int) -> Child? { children.first { $0.id == id } }

    func start() async {
        let hasTokens = await TokenStore.shared.hasTokens
        phase = hasTokens ? .loggedIn : .loggedOut
        if hasTokens { await session.load() }
    }

    func didLogin() async {
        loginNotice = nil
        await AulaAPI.shared.reset()
        phase = .loggedIn
        await session.refresh()
    }

    func sessionExpired() {
        guard phase == .loggedIn else { return }
        loginNotice = "Din Aula-session er udløbet. Log ind med MitID igen."
        phase = .loggedOut
    }

    func logout() async {
        await TokenStore.shared.clear()
        await AulaAPI.shared.reset()
        DiskCache.clear()
        DataStore.shared.reset()
        session.forget()
        selectedChildId = nil
        phase = .loggedOut
    }
}
