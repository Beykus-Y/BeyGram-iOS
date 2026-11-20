# Stealth sending: UI and state contract

This is the contract between the stealth state and the chat UI. The state and the API are in `submodules/BeyGramStealth` and in
`submodules/TelegramCore/Sources/BeyGram/BeyGramStealthSend.swift`. The screens, the strings and the Mac build belong to the UI
work (Gemini). This document changes no UI file.

Status: the state and the API are written and checked by reading only. They are not compiled and not run on a device (section 7).

## 1. Settings

Stored per account in UserDefaults (`beygram.stealth.settings.<accountPeerId>`). Read with
`BeyGramStealthStore.shared.settings(accountPeerId:)`, changed with `BeyGramStealthStore.shared.update(accountPeerId:_:)`.
The whole feature sits behind the BeyGramKit feature `privacyPolicy`, which is off by default. With it off, nothing changes.

| Setting | Field | Default | Notes |
|---|---|---|---|
| Hide read receipts | `hideReadReceipts` | off | Account default. A per-chat override applies. |
| Hide online | `hideOnline` | off | Account-wide. Applies at once when it changes once PR #108 is in. Before that it waits for the next presence refresh. |
| Hide typing | `hideTyping` | off | Account default. A per-chat override applies. |
| Scheduled sending | `serverScheduledSend` | off | Sends the messages the user did not schedule as server-scheduled. |
| Delay | `scheduledSendDelaySeconds` | 15 | Choices in `BeyGramStealthSettings.scheduleDelayChoices` (15, 30, 60, 120). Never below `minimumServerLeadSeconds` (15). |
| Per chat | `chatModes[peerId]` | inherit | `allow`, `block` or `inherit`. Presence has no per-chat override. |

The stored keys match the Android app (`StealthSettingsStore.kt`): `no_read_receipts`, `hide_online`, `hide_typing`,
`scheduled_send`, `scheduled_send_delay`, `chats`.

Example:

```swift
BeyGramStealthStore.shared.update(accountPeerId: accountId) { $0.serverScheduledSend = true }
```

## 2. States of an outgoing message

A message is in exactly one of these states:

1. **Sent as before.** Stealth is off, or the user picked a date. Nothing to show.
2. **Waiting for stealth dispatch.** The message has a date (`Message.scheduleTime` is set) and is in the scheduled namespace,
   so Telegram does not publish it yet. Until its request is built, the date is the enqueue-time placeholder. At dispatch the
   date becomes the chosen delay counted from the server clock, and the stored message is updated to match. A waiting message
   is not failed.
3. **Failed, refused by stealth.** The message has the `Failed` flag, and `beyGramStealthRefusal(accountPeerId:messageId:)`
   returns a reason. The chat shows the dialog for that reason (section 3) and offers the actions in section 4.
4. **Failed, not by stealth.** The `Failed` flag and no reason. Show the usual failed state, and no stealth dialog.

Open point: a waiting message is in the scheduled namespace. In Telegram iOS scheduled messages are listed apart from the chat
history, so the message may appear only in the scheduled list until it is published. This needs a device check. The product
decides how a waiting message is shown.

## 3. Refusal reasons and dialogs

`BeyGramStealthRefusal` raw values are stored with the message, so they must not change.

| Reason | Raw value | When | Key (`localizationKey`) | Russian | English |
|---|---|---|---|---|---|
| Secret chat | `secretChat` | the chat is a secret chat | `BeyGram.Stealth.Refusal.SecretChat` | Отложенная отправка недоступна в секретных чатах. Отправьте сообщение сейчас или удалите его. | Stealth sending is not available in secret chats. Send the message now or delete it. |
| Paid message | `paidStars` | the message is paid (Stars) | `BeyGram.Stealth.Refusal.PaidStars` | Платное сообщение нельзя отправить по расписанию. Отправьте его сейчас или удалите. | A paid message cannot be sent on a schedule. Send it now or delete it. |
| Short lead | `leadTooShort` | the chosen delay is under 15 s | `BeyGram.Stealth.Refusal.LeadTooShort` | Задержка меньше 15 секунд: Telegram опубликовал бы сообщение сразу. Выберите задержку не меньше 15 секунд и отправьте снова. | The delay is under 15 seconds, so Telegram would publish the message at once. Choose a delay of at least 15 seconds and send again. |
| Ephemeral | `ephemeral` | an ephemeral (bot) send | `BeyGram.Stealth.Refusal.Ephemeral` | Для этого сообщения отложенная отправка недоступна. Отправьте его сейчас или удалите. | Stealth sending is not available for this message. Send it now or delete it. |
| Not recorded | `notRecorded` | the scheduled date could not be recorded | `BeyGram.Stealth.Refusal.NotRecorded` | Не удалось подготовить отложенную отправку, сообщение не отправлено. Попробуйте снова. | The delayed send could not be prepared, so the message was not sent. Try again. |

The keys are distinct, and a BeyGramStealth test checks it. The UI adds the strings to the app's localization in both languages.

## 4. Actions for a refused message

- **Resend** (`resendMessages(account:messageIds:sendNowConsent: false)`). The message goes through the stealth rules again. If
  the cause remains (a secret chat, for example), it is refused again with the same reason. The reason on the message is updated.
- **Send now** (`resendMessages(account:messageIds:sendNowConsent: true)`). It sends outside stealth, so the message is visible
  at once. Call it only after the user confirms in a dialog that says so. Never call it without that confirmation.
- **Delete.** The usual delete. Stealth never sends a refused message.

A refused message is never sent at once by stealth, and never dropped.

## 5. API

| Call | Module | Use |
|---|---|---|
| `BeyGramStealthStore.shared.settings(accountPeerId:)` | BeyGramStealth | read the settings |
| `BeyGramStealthStore.shared.update(accountPeerId:_:)` | BeyGramStealth | change the settings |
| `BeyGramStealthRefusal`, `localizationKey` | BeyGramStealth (public) | the reason and its dialog key |
| `beyGramStealthRefusal(accountPeerId:messageId:)` | TelegramCore (public) | the reason of a refused message, or nil |
| `resendMessages(account:messageIds:sendNowConsent:)` | TelegramCore (public) | resend, section 4 |

The UI imports `BeyGramStealth` for the types. A new public TelegramCore symbol that TelegramUI uses must go into the TelegramCore
export list, `Telegram/framework_exported_symbols.bzl` (the rule is in `Telegram/CLAUDE.md`), or the release link fails. That
applies to `beyGramStealthRefusal` the first time the UI calls it.

Presence (`hideOnline`), typing and read receipts are already hooked (`submodules/BeyGramStealth/CLAUDE.md`). The UI only changes
their settings.

## 6. Limits the UI must respect

- Thread and topic reads (`readDiscussion`, `readSavedHistory`) follow the read-receipt rule of the chat they belong to. With the rule on, nothing is sent, and the local read state still changes. The UI shows nothing new for this.
- The local delay queue is not built. The UI must not offer a delay that happens on the device.
- Secret chats and paid messages are refused, not scheduled. View-once media and live locations are not refused yet (Android
  refuses them). Channel direct messages (monoforums) are not refused yet.
- A reason is keyed by the local message id, which Postbox can reuse after a deletion. Show a stealth dialog only for a message
  that is failed now.
- What a waiting message does across a force quit is not verified on a device.

## 7. Checks on a device (Gemini)

1. Hide online on: the account shows offline at once, without waiting for the 30 s refresh (needs PR #108).
2. Scheduled sending with a 15 s delay, and a photo or video that takes more than 15 s to upload: the message is published at the
   chosen delay, not at once.
3. Secret chat with scheduled sending on: the message is failed with the secret-chat dialog. Resend gives the same reason.
4. Paid message: failed with the paid-message dialog.
5. A message scheduled by hand keeps the date the user chose.
6. An album sent with scheduled sending: all its messages carry one date.
7. A refused message: "Send now" sends it only after the confirmation.

## 8. Build notes

- `BeyGramStealth` is built with `-warnings-as-errors`.
- Host tests: `//submodules/BeyGramStealth:BeyGramStealthTests`, run with `./build-input/bazel-9.2.0-darwin-arm64 test` on macOS.
- The TelegramCore parts have no host test. They need the device checks in section 7.

## 9. Open points for the product owner

- How a waiting message is shown: in the chat, in a banner, or in the scheduled list.
- Whether the delay choices (15, 30, 60, 120 s) are the ones to offer.
