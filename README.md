# Aula+

A faster, cleaner, unofficial iOS client for [Aula](https://www.aula.dk), built with SwiftUI.

- **I dag:** each child's presence (Komme/Gå), today's lessons, unread messages, new posts, upcoming important dates, holiday requests that still need an answer
- **Komme/Gå:** report a child sick (or undo it), register ferie/fri, edit drop-off/pick-up times and who picks up, per day
- **Beskeder:** search, unread/starred filters, star and delete with swipes, reply, start new threads with recipient search, older messages, attachments in Quick Look
- **Kalender:** a swipeable week strip, a colour per child, substitute-teacher badges, event details with RSVP, add any event to the iOS Calendar
- **Ugeplan:** Meebook and Min Uddannelse week plans, plus Min Uddannelse tasks (opgaver)
- **Mere:** posts (with comments), photo gallery with full-screen viewer and save, notifications feed, important dates, holiday requests, contacts (class lists with call/mail/message), secure documents and shared files
- **Notifications:** background refresh posts local notifications for new messages and posts; tapping one opens the item
- **Home-screen widget:** each child's status and unread count
- **Face ID lock**, **Danish and English** (follows the phone's language, or set it in Profile)
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

In Xcode, select your Team under **Signing & Capabilities** for both the **AulaPlus** and **AulaPlusWidget** targets, and then run it on your iPhone.

- A paid developer account is needed for the widget (it uses an App Group).
- With a free Apple ID, delete the `dependencies:` block under the `AulaPlus` target in `project.yml` and run `xcodegen generate` again. The app works without the widget, but expires after 7 days.

## How it works

| Piece | File |
|---|---|
| OIDC + PKCE login in a `WKWebView`, catching the `https://app-private.aula.dk?code=…` redirect | `Auth/LoginView.swift`, `Auth/PKCE.swift` |
| Token exchange and refresh, Keychain storage | `Auth/TokenStore.swift` |
| API client: `access_token` query param, CSRF header on POST, auto version bump on HTTP 410, refresh-and-retry on 401 or sub-codes 9/23 | `API/AulaAPI.swift` |
| Lenient JSON models (ids as int or string, lossy arrays) | `API/Models.swift`, `API/JSONHelpers.swift` |
| Stale-while-revalidate cache | `Cache/Loadable.swift`, `Cache/DiskCache.swift` |

The API knowledge comes from [nickknissen/aula](https://github.com/nickknissen/aula) and [scaarup/aula](https://github.com/scaarup/aula).

## Notes

- Some write calls (reply, new thread, RSVP, star/delete, comments, holiday answers) use request shapes from the decompiled official app ([eisbaw/aulalibre](https://github.com/eisbaw/aulalibre)). If Aula rejects one, the app shows Aula's error.
- Not done: attaching files to messages, EasyIQ/Docendo week plans, true push (background refresh is used instead).

## Disclaimer

This is an unofficial app, not affiliated with Aula, KOMBIT or Netcompany. It uses Aula's internal API, which can change without notice.
