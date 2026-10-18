# TDLib integration — BeyGram iOS

## Implemented in this iteration

- TDLibKit pinned to git revision `3996b5f55bee434a2694d6384b8a7ff320f3efaf`, which depends on TDLibFramework `1.8.68-ab8d769f` (XCFramework distributed via SwiftPM).
- An actual TDLibClientManager and client, with serial update dispatch in the upstream library.
- `authorizationStateWaitTdlibParameters` initialization with database encryption key from Keychain (after-first-unlock, this-device-only).
- `authorizationStateWaitPhoneNumber`, `authorizationStateWaitCode`, `authorizationStateWaitPassword`, `authorizationStateReady` handling.
- SwiftUI login UI. Unsupported email/registration/QR/Premium states show an explicit non-success message.
- Trusted GitHub runs inject Telegram API credentials via generated xcconfig. PR runs never inject credentials.

## Remaining functional acceptance work

- **CI must pass:** xcodebuild must resolve and link the pinned binary XCFramework for arm64 iPhone.
- **Real device test:** actual login on an isolated Telegram test account; not claimed merely from CI compilation.
- Chat list, chat history, send/edit/delete, media, image cache, call UI, notifications, proxies, performance.
- Security: test preservation of encryption key and database across signed sideload updates, and ensure no session reset after entitlement/signature changes.
- For email/QR/authentication-method changes, implement corresponding TDLib API methods and verify actual returned TDLib states.

## Auth state model

The TDLibKit wrapper receives JSON updates on one manager thread and serializes updates per client. BeyGram's main-actor service forwards only authorization updates into SwiftUI. Other message/chat updates are ignored for now, not misrepresented as implemented.

To protect local data, the service checks for an existing nonempty database directory before ever generating a new key. It will fail clearly rather than silently corrupt or reset sessions.

## Credentials

API ID/hash are not secret after distributing an IPA; they are included in the Info.plist of trusted builds. The CI does not print their values deliberately. `TELEGRAM_API_ID` must be a positive decimal number; `TELEGRAM_API_HASH` must be 32 hex characters.

Workflow output is an unsigned development IPA; Sideloadly can perform local signing. No paid Apple Developer account is required for this build method.
