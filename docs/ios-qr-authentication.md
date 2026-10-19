# QR authentication for BeyGram iOS

## Motivation

On iOS 26, TDLib accepted the phone number and returned `authorizationStateWaitCode` with code type `authenticationCodeTypeTelegramMessage`, but no code appeared in the user's official Telegram service chat. `next_type` was null. Do not assume Telegram delivered a code just because TDLib entered that state.

## Implementation

Pinned TDLib 1.8.68 supports `requestQrCodeAuthentication(otherUserIds: [])` from `authorizationStateWaitPhoneNumber` or, when no pending authorization query exists, from `authorizationStateWaitCode` and certain other authorization states.

- The user can select **Войти через QR-код** from phone, code or password screens.
- TDLib sends `authorizationStateWaitOtherDeviceConfirmation` with a temporary `tg://login?token=...` URL.
- Swift generates a QR image on-device using CoreImage, without calling web services.
- New authorization-state updates replace the QR image when TDLib rotates the token.
- A second device with an existing Telegram session scans it through **Telegram → Settings → Devices → Link Desktop Device**.
- TDLib then transitions to `authorizationStateReady` or another authorization state such as password required.

## Security

The QR URL is a login bearer token. Never print it in console, include it in screenshots, persist it, send it to external QR generators or collect it in telemetry. The view only renders it locally.

## Important limitations

- A second logged-in device is needed to scan a QR on the phone displaying BeyGram.
- TDLib may reject a QR switch if another auth request is currently pending; preserve and show the server error.
- QR sign-in success is not confirmed by compilation alone; test on a real iPhone and a second Telegram device.
- Do not wipe the existing TDLib local database or Keychain.
