# iOS login: code delivery diagnostics

## Reported real-device behavior

The iOS app reached `authorizationStateWaitCode` after successfully accepting the phone number, but no code was observed in the user's Telegram client. This state does **not** prove actual delivery.

## TDLib contract (pinned 1.8.68-ab8d769f)

`authorizationStateWaitCode` carries `code_info` (`AuthenticationCodeInfo`):

- `type`: delivery method (Telegram message, SMS, call, Fragment, Firebase, etc.).
- `next_type`: potential next delivery method; may be null.
- `timeout`: seconds before another code request is allowed.
- `phone_number`: phone number being authenticated. Do not log or display it unmasked.

`resendAuthenticationCode` is only valid when `next_type` exists and the timeout has elapsed. The server may still reject the request.

## New UI

- Show the specific method returned by Telegram; don't always say "code from Telegram".
- If `next_type` is known, expose a timer and a request button only after the delay.
- Treat null `next_type` as no known resend option (do not blindly spam).
- Preserve the existing session/database; do not log code, phone, API hash, encryption key.
- If the delivery type is `authenticationCodeTypeFirebaseIos` or Android, explain that this client cannot fulfill the official-app Firebase challenge.

## QA

1. Confirm UI reports the method actually returned by TDLib.
2. Request retry only after timeout; validate response and next update.
3. Confirm wrong/expired code errors remain visible.
4. Verify the current signed IPA can be updated over the prior version without wiping Keychain or TDLib data.
5. Do not claim server-side code delivery when only `authorizationStateWaitCode` has been observed.
