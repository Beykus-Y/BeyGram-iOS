# BeyGram: iOS porting plan

## Direction

The iOS app is a native SwiftUI client sharing a product specification with Android, not a Kotlin APK conversion. Keep current Android sources unchanged until the iOS port can stand independently.

## Phases

1. **Bootstrap:** SwiftUI shell, CI, unsigned IPA, reproducible build.
2. **TDLib integration:** obtain iOS-compatible library build, define Swift/C++ bridging, handle log/security paths; do not reuse Android JNI.
3. **Authentication & session:** Telegram login, 2FA, session persistence, logout without accidental data loss.
4. **Core messaging:** chat list, messages, send/edit/delete, photos/media, progress/errors, state restoration.
5. **BeyGram features:** theme engine, message geometry, privacy, proxy/subscription UX, diagnostics.
6. **iOS background behavior:** APNs and extensions (where appropriate), app life cycle, permission flows. Android persistent-service assumptions are invalid on iOS.
7. **Distribution:** Apple Developer credentials, provisioning/signing, TestFlight/Ad Hoc strategy, tagged signed IPA releases.

## Cross-platform change management

An imported copy does not track its source as a GitHub fork. Use the Android repo as a documented upstream reference; no blind merge into the iOS app. Copying shared documentation or assets may be automated later with validation. New features should receive platform-specific issues and PRs.

## Release safety

- Unsigned IPA is not a standard installable iPhone release.
- Build success does not imply TDLib functionality or device testing.
- Never publish signing keys, Telegram credentials or private profiles.
- Do not automatically ship changes from one platform to the other without review.
