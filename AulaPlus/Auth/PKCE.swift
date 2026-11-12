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
