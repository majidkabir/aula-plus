import Foundation

struct Tokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpiringSoon: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

/// Raw OIDC token endpoint answer.
private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
}

enum AuthError: LocalizedError {
    case notLoggedIn
    case stateMismatch
    case missingCode
    case tokenEndpoint(Int)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return String(localized: "Du er ikke logget ind.")
        case .stateMismatch: return String(localized: "Login blev afbrudt (state passede ikke). Prøv igen.")
        case .missingCode: return "Aula sendte ingen login-kode tilbage."
        case .tokenEndpoint(let code): return "Aula login fejlede (HTTP \(code))."
        }
    }
}

/// Owns the OIDC tokens: Keychain persistence, proactive and forced refresh.
/// Concurrent refreshes are coalesced into one request.
actor TokenStore {
    static let shared = TokenStore()
    private static let key = "tokens"

    private var tokens: Tokens?
    private var refreshTask: Task<Tokens, Error>?

    init() {
        tokens = Keychain.load(Tokens.self, key: Self.key)
    }

    var hasTokens: Bool { tokens != nil }

    func store(_ new: Tokens) {
        tokens = new
        Keychain.save(new, key: Self.key)
    }

    func clear() {
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        Keychain.delete(key: Self.key)
    }

    /// A non-expired access token, refreshing first if needed.
    func accessToken() async throws -> String {
        guard let t = tokens else { throw AuthError.notLoggedIn }
        if !t.isExpiringSoon { return t.accessToken }
        return try await refresh().accessToken
    }

    /// Refresh regardless of expiry (used after 401 / session-expired answers).
    @discardableResult
    func refresh() async throws -> Tokens {
        if let task = refreshTask { return try await task.value }
        guard let refreshToken = tokens?.refreshToken else {
            clear()
            throw AuthError.notLoggedIn
        }
        let task = Task { try await Self.requestTokens(form: [
            "grant_type": "refresh_token",
            "client_id": AulaConfig.clientID,
            "refresh_token": refreshToken,
        ], keepRefreshToken: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let new = try await task.value
            store(new)
            return new
        } catch AuthError.tokenEndpoint(let code) where (400..<500).contains(code) {
            // Refresh token rejected: a real logout. Network errors are rethrown
            // as-is so being offline never logs the user out.
            clear()
            throw AuthError.notLoggedIn
        }
    }

    /// Exchange the authorization code from the MitID login for tokens.
    func exchange(code: String, verifier: String) async throws {
        let new = try await Self.requestTokens(form: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": AulaConfig.clientID,
            "redirect_uri": AulaConfig.redirectURI,
            "code_verifier": verifier,
        ], keepRefreshToken: nil)
        store(new)
    }

    private static func requestTokens(form: [String: String], keepRefreshToken: String?) async throws -> Tokens {
        var req = URLRequest(url: AulaConfig.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = formEncode(form).data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AuthError.tokenEndpoint(status) }
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Tokens(accessToken: r.access_token,
                      refreshToken: r.refresh_token ?? keepRefreshToken,
                      expiresAt: Date().addingTimeInterval(r.expires_in ?? 3600))
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
    }
}
