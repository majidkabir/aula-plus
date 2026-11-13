import CryptoKit
import Foundation
import Security

/// PKCE (S256) values plus OAuth state for one login attempt.
struct PKCE {
    let verifier: String
    let challenge: String
    let state: String

    static func make() -> PKCE {
        let verifier = randomURLSafe(byteCount: 32)
        return PKCE(verifier: verifier,
                    challenge: challenge(for: verifier),
                    state: randomURLSafe(byteCount: 16))
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes).base64URLEncoded()
    }

    var authorizeURL: URL {
        var c = URLComponents(url: AulaConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: AulaConfig.clientID),
            .init(name: "scope", value: AulaConfig.scope),
            .init(name: "redirect_uri", value: AulaConfig.redirectURI),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return c.url!
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Recent login attempts (state → PKCE verifier), kept for 30 minutes.
///
/// Aula's login can come back with the state of an earlier attempt (or none) after the
/// MitID round trip, e.g. when the app was restarted while you were in the MitID app.
/// The code is still bound to its own PKCE challenge, so we exchange it with the verifier
/// of the attempt it belongs to instead of failing; a wrong verifier is rejected by Aula.
enum LoginAttempts {
    private static let key = "login.attempts"
    private static let maxAge: TimeInterval = 30 * 60

    private struct Attempt: Codable { let state: String; let verifier: String; let at: Date }

    private static func load() -> [Attempt] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Attempt].self, from: data) else { return [] }
        return list.filter { Date.now.timeIntervalSince($0.at) < maxAge }
    }

    private static func save(_ list: [Attempt]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(list.suffix(5))), forKey: key)
    }

    static func add(_ pkce: PKCE) {
        save(load() + [Attempt(state: pkce.state, verifier: pkce.verifier, at: .now)])
    }

    /// Verifiers to try: the one matching `state` first, then the others, newest first.
    static func verifiers(for state: String?) -> [String] {
        let list = load().reversed()
        let matched = list.filter { $0.state == state }.map(\.verifier)
        return matched + list.filter { $0.state != state }.map(\.verifier)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
