import Foundation

/// Endpoints and OIDC client values used by the official Aula mobile app.
/// Source: nickknissen/aula docs/aula-authentication.md (captured from the Android app).
enum AulaConfig {
    static let authBase = "https://login.aula.dk"
    static let authorizeURL = URL(string: "\(authBase)/simplesaml/module.php/oidc/authorize.php")!
    static let tokenURL = URL(string: "\(authBase)/simplesaml/module.php/oidc/token.php")!
    static let logoutURL = URL(string: "\(authBase)/auth/logout.php")!

    static let redirectURI = "https://app-private.aula.dk"
    static let redirectHost = "app-private.aula.dk"

    /// Level 3 (full MitID) client.
    static let clientID = "_99949a54b8b65423862aac1bf629599ed64231607a"
    static let scope = "aula-sensitive"

    static let apiBase = "https://www.aula.dk/api/v"
    /// Starting API version. Bumped automatically on HTTP 410 and remembered.
    static let defaultAPIVersion = 25

    static let csrfCookie = "Csrfp-Token"
    static let csrfHeader = "csrfp-token"

    static let minUddannelseAPI = "https://api.minuddannelse.net/aula"
    static let meebookAPI = "https://app.meebook.com/aulaapi"

    enum Widget {
        static let meebook = "0004"
        static let muUgeplan = "0029"
        static let muSSO = "0023"
    }
}
