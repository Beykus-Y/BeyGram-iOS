# TDLib authorization regression (iOS)

## Observed on an iPhone with iOS 26

The first production-credential IPA launched correctly and switched between all four SwiftUI tabs, but TDLib rejected initialization before the phone-entry screen with:

> Valid api_id must be provided. Can be obtained at https://my.telegram.org

The release IPA's Info.plist contained the expected TelegramAPIID and TelegramAPIHash; CI also verified these before packaging.

## Root cause

`TelegramService` constructed `DTO(SetTdlibParameters(...))` without an encoder. `TDLibKit`'s default DTO uses `JSONEncoder()`, which preserves Swift property names such as `apiId`, `apiHash`, `databaseDirectory` and `phoneNumber`. TDLib JSON requests require `api_id`, `api_hash`, `database_directory`, `phone_number`.

The upstream TDLibKit generated API sets `encoder.keyEncodingStrategy = .convertToSnakeCase`, but we bypassed that generated API by using DTO directly.

## Fix

- Centralize outgoing requests in `TelegramRequestFactory` with snake_case encoding.
- Use it for TDLib parameters, phone number, verification code and cloud password.
- Perform an on-device preflight check of the serialized parameters before submitting them to TDLib. The check verifies fields by name without printing values.
- Preserve existing Keychain database key/session data; never uninstall or wipe app data as a workaround.

## Validation

- Swift standalone smoke test confirms `JSONEncoder.KeyEncodingStrategy.convertToSnakeCase` emits `api_id`, `api_hash`, `database_directory`, `use_message_database`.
- GitHub iOS CI must compile the fix, and a trusted DEV build must pass its credential-embedding checks.
- A real-device login retest remains necessary; no claim of successful login until observed.
