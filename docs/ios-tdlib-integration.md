# TDLib for BeyGram iOS — integration contract

## Current status

The Swift code added in this stage is **not a TDLib binding**. It provides a configuration validator, explicit unavailable state and a UI status screen. Do not report Telegram authorization as working.

## Required native integration

1. Select a pinned TDLib source release/commit and build it for iOS arm64 and simulator architectures using Xcode/CMake; check licenses and required native dependencies.
2. Package the resulting binaries/headers as an XCFramework or another reproducible Xcode-compatible artifact. Android `libtdjni.so` is not usable on iOS.
3. Implement and test a Swift-compatible bridge for the exact TDLib C interface provided by that pinned build. Avoid guessing TDLib symbols and memory ownership rules.
4. Build a serialized client/event dispatcher with correct cancellation, authorization-state handling and session storage. Protect database encryption key and authentication state.
5. Handle `authorizationStateWaitTdlibParameters`, phone number, code, password, logout, error/retry flows using the actual TDLib schema of the pinned version.
6. Add integration tests on an isolated Telegram test account, never a user's existing production session.
7. Integrate background lifecycle and push notification design separately; Android foreground-service behavior cannot be carried over.

## Telegram credentials

`TelegramConfiguration` reads `TelegramAPIID` and `TelegramAPIHash` from the built application's Info.plist. The build currently does not inject these keys. Never commit real credentials or print them in CI logs. API ID/hash embedded in a client are extractable, so do not present them as a security boundary.

Before shipping, wire explicit configuration injection through XcodeGen and CI with validation, and verify that no secret signing material is published.

## Acceptance criteria for functional Telegram milestone

- Real iOS TDLib build pinned and reproducible in macOS CI.
- Swift bridge builds for device and simulator and passes smoke tests.
- Authorization state machine handles login/code/2FA and persists sessions.
- At least one real Telegram test chat loads and a message can be sent.
- Signed IPA installation tested on an iPhone.
