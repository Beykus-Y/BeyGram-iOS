# BeyGramStealth

Block B of the iOS plan (privacy and stealth, see the plan document «План переноса BeyGram на iOS»). Android reference in the BeyGram repo: `docs/conversation-architecture.md` (stealth sending, #541), `StealthSettingsStore.kt`, `TdStealthScheduler.kt`, `InteractionPolicy.kt`.

## What is hooked

- **Presence** (`account.updateStatus`): with `hideOnline`, the account is always reported offline. Account-wide only. A change
  applies at once: `BeyGramStealthStore` posts `didChangeNotification` after a real change, and `ManagedAccountPresence`
  evaluates again while the account is requested online (before, it waited for the next presence change or the 30-second
  refresh). What the server may still show as online is listed in `docs/stealth-audit.md`.
- **Typing and other chat activity** (`messages.setTyping`): with `hideTyping`, nothing is sent for the chat. Per-chat overrides apply.
- **Read receipts** (`messages.readHistory`, `channels.readHistory`, the sync of a chat's read state): with `hideReadReceipts`, the read state is not pushed. The sync treats it as done, so it is not sent later either. Known limitation: while the rule is on, mark-as-unread is not synced to the server. "Mark all chats as read" skips the chats the rule hides.

## Stealth sending

`BeyGramStealthHooks.sendDecision` is called by `beyGramStealthBatch` (`submodules/TelegramCore/Sources/BeyGram/BeyGramStealthSend.swift`). The public `enqueueMessages(account:peerId:messages:)` and `resendMessages` (`submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift`) call it. With `serverScheduledSend` on:

- A message the user did not schedule is sent as a Telegram scheduled message. The local copy gets the same `OutgoingScheduleInfoMessageAttribute` as a hand-scheduled message, so the send pipeline stores it in the scheduled namespace from the start (the `messageNamespace` choice in `EnqueueMessage.swift`), and the server's reply does not show it twice.
- A batch that cannot be scheduled (a secret chat, a Stars-paid message, a legacy lead under 15 s) is **refused: never sent at once, never dropped**. It is stored as failed messages in the same transaction (`beyGramStealthMarkFailed`), and the pending manager does not send failed messages. The chat shows the usual failed marker; the user resends the message (the resend follows the stealth rules again) or deletes it.
- `resendMessages(account:messageIds:sendNowConsent:)`: a resend is scheduled like a new send, and a refused batch stays failed and is not deleted. `sendNowConsent: true` sends now, outside stealth sending. No caller passes it yet: the UI must ask the user first.

## Not covered yet

- **Upload time.** A message with local media is scheduled at enqueue time (now plus the lead). If the upload takes longer than the lead, Telegram sees a date in the past and sends at once. Android uploads first and sets the date after (`TdStealthScheduler.resolve`). The iOS fix belongs in `PendingMessageManager`, where the request is built.
- **Thread and topic reads** (`messages.readDiscussion`, `messages.readSavedHistory`, `TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift`) are not gated: those helpers take no account peer id.
- **View-once media and live locations**: Android refuses them (`TdStealthScheduler.resolve`); iOS does not yet. Channel direct messages (monoforums) are not refused either.
- **Standalone sends** (`standaloneSendMessage`, share and intent paths) do not pass the hook. The sideload build has no extensions, so they are not reachable there today.
- Story views, open-content receipts, the delayed-send queue, live text drafts, the settings screen and the consent prompt (UI, outside this module).

## Rules

- **Master switch**: BeyGramKit feature `privacyPolicy`, off by default. With it off, every hook returns the upstream behaviour.
- **Per account**: `BeyGramStealthStore`, UserDefaults key `beygram.stealth.settings.<accountPeerId>`. BeyGramKit settings are shared across accounts, so they are not used for this.
- **Dependencies**: Foundation and BeyGramKit only. No Postbox, no TelegramCore.
- **Upstream hooks are short calls** into `BeyGramStealthHooks`. Hook sites:
  - `submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift` (created with the account's peer id in `Account.swift`): presence.
  - `submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift`: `requestActivity` (typing).
  - `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift`: `pushPeerReadState` (read receipts).
  - `submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkAllChatsAsRead.swift`: read receipts of "mark all chats as read".
  - `submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift` with `submodules/TelegramCore/Sources/BeyGram/BeyGramStealthSend.swift`: sending and resending.
- **Scheduled sends**: flags bit 10 goes together with the date in the request builder (`PendingMessageManager`), so a date is never sent without its flag.
- **Clock**: the server clock (`network.globalTime`), never the device clock. A date in the past means an immediate send.
- **Tests**: `Tests/BeyGramStealthTests.swift`, a host `swift_test` for the pure logic. The TelegramCore parts have no host test. The batch logic and the failed marker need a device check: the chat shows one message, and a refused send shows as failed and goes out only after a resend.
