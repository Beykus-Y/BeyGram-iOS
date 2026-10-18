# BeyGram iOS

Native SwiftUI port of BeyGram for iPhone.

## Current functionality

- SwiftUI app shell and BeyGram color palette
- TDLibKit (pinned commit `3996b5f`, TDLib `1.8.68-ab8d769f`) linked through Swift Package Manager
- Telegram configuration injected into Info.plist from CI or a local xcconfig
- TDLib initialization and local database encryption key stored in iOS Keychain
- Telegram phone number → code → two-step password authorization UI
- Explicit explanation for unsupported alternative authorization states

**Not yet implemented:** chat list, message history/sending, media, QR/email/registration login, background pushes, proxies. The code has not been validated on a real iPhone. Telegram credentials are packaged into trusted branch/release builds, not PR builds.

## CI build and installing

`.github/workflows/ios.yml` builds an **unsigned IPA** on macOS. The IPA is an Actions artifact; tags `ios-v*` publish it as GitHub prerelease. For your own device, sign with Sideloadly or another compatible sideloading utility. Apple paid Developer certificate secrets are not required for unsigned CI output.

The repository secrets `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` are used on trusted push/workflow_dispatch runs. They are intentionally NOT used by PR workflows, so the PR's IPA has no functioning Telegram API configuration.

Telegram API ID/hash embedded in a client can be extracted; keep signing keys and private certificates separate and never place them in the repository.

## Local macOS build

1. Install Xcode and `brew install xcodegen`.
2. Copy `ios/TelegramCredentials.xcconfig.example` to `ios/TelegramCredentials.xcconfig` and set your API ID/hash.
3. From `ios/`, generate and build:

```sh
xcodegen generate --spec project.yml
xcodebuild -project BeyGramIOS.xcodeproj -scheme BeyGramIOS \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -xcconfig TelegramCredentials.xcconfig CODE_SIGNING_ALLOWED=NO build
```

## Development policy

Do not delete/reinitialize TDLib data during normal installation updates. The encryption key is kept in the device's Keychain and never committed. If the database exists but its key is lost, the app refuses an automatic reset. This is especially important with sideload reinstalls.

Android source code is retained for reference; do not blindly merge Kotlin runtime changes into Swift.

## Licensing

TDLibKit and TDLibFramework: MIT. TDLib native core: Boost Software License 1.0. Original BeyGram GPL-3.0 licensing remains.
