# Aula+

A faster, cleaner, unofficial iOS client for [Aula](https://www.aula.dk), built with SwiftUI.

- **I dag:** each child's presence (Komme/Gå), today's lessons, unread messages and new posts on one screen
- **Beskeder:** threads with search, an unread filter, and messages shown oldest-first like a chat; opening a thread marks it read in Aula
- **Kalender:** a swipeable week strip, colour per child, substitute-teacher badges
- **Ugeplan:** Meebook and Min Uddannelse week plans
- **Opslag:** posts with search and attachments
- **Offline-first:** every screen opens instantly from the on-disk cache, then refreshes in the background
- **Login:** MitID through Aula's own OIDC flow (PKCE). Tokens stay in the Keychain and refresh silently.

Your data only travels between your phone and Aula's servers. There is no backend.

## Run it

You need a Mac with Xcode 16+.

```bash
brew install xcodegen
git clone https://github.com/majidkabir/aula-plus.git
cd aula-plus
xcodegen generate
open AulaPlus.xcodeproj
```

In Xcode, open **AulaPlus target → Signing & Capabilities**, pick your Team, and then run it on your iPhone.
A free Apple ID works, but the app expires after 7 days. A paid developer account gives you a year, or TestFlight.

## How it works

| Piece | File |
|---|---|
| OIDC + PKCE login in a `WKWebView`, catching the `https://app-private.aula.dk?code=…` redirect | `Auth/LoginView.swift`, `Auth/PKCE.swift` |
| Token exchange and refresh, Keychain storage | `Auth/TokenStore.swift` |
| API client: `access_token` query param, CSRF header on POST, auto version bump on HTTP 410, refresh-and-retry on 401 or sub-codes 9/23 | `API/AulaAPI.swift` |
| Lenient JSON models (ids as int or string, lossy arrays) | `API/Models.swift`, `API/JSONHelpers.swift` |
| Stale-while-revalidate cache | `Cache/Loadable.swift`, `Cache/DiskCache.swift` |

The API knowledge comes from [nickknissen/aula](https://github.com/nickknissen/aula) and [scaarup/aula](https://github.com/scaarup/aula).

## Not yet

- Replying to or writing messages
- Older messages in long threads (only the first page loads)
- EasyIQ / Docendo week plans
- Push notifications (needs a small server that polls Aula)

## Disclaimer

This is an unofficial app, not affiliated with Aula, KOMBIT or Netcompany. It uses Aula's internal API, which can change without notice.
