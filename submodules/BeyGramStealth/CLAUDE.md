# BeyGramStealth

Block B of the iOS plan (privacy and stealth, see the plan document «План переноса BeyGram на iOS»). Android reference in the BeyGram repo: `docs/conversation-architecture.md` (stealth sending, #541), `StealthSettingsStore.kt`, `TdStealthScheduler.kt`, `InteractionPolicy.kt`.

## What is hooked

- **Presence** (`account.updateStatus`): with `hideOnline`, the account is always reported offline. Account-wide only. A change
  applies at once: `BeyGramStealthStore` posts `didChangeNotification` after a real change, and `ManagedAccountPresence`
  evaluates again while the account is requested online (before, it waited for the next presence change or the 30-second
  refresh). What the server may still show as online is listed in `docs/stealth-audit.md`.
- **Typing and other chat activity** (`messages.setTyping`): with `hideTyping`, nothing is sent for the chat. Per-chat overrides apply.
- **Read receipts** (`messages.readHistory`, `channels.readHistory`, the sync of a chat's read state): with `hideReadReceipts`, the read state is not pushed. The sync treats it as done, so it is not sent later either. Known limitation: while the rule is on, mark-as-unread is not synced to the server. "Mark all chats as read" skips the chats the rule hides.
- **Thread and topic reads** (`messages.readDiscussion`, `messages.readSavedHistory`: a forum topic, a monoforum sub-chat, a comment thread): with `hideReadReceipts`, nothing is sent. The local read state still changes, and the server count is not fetched, since it would bring the unread count back. The per-chat mode is that of the chat the thread's messages live in (the forum, the monoforum channel or the group).

## Stealth sending

`BeyGramStealthHooks.sendDecision` is called by `beyGramStealthBatch` (`submodules/TelegramCore/Sources/BeyGram/BeyGramStealthSend.swift`). The public `enqueueMessages(account:peerId:messages:)` and `resendMessages` (`submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift`) call it. With `serverScheduledSend` on:

- A message the user did not schedule is sent as a Telegram scheduled message. The local copy gets the same `OutgoingScheduleInfoMessageAttribute` as a hand-scheduled message, so the send pipeline stores it in the scheduled namespace from the start (the `messageNamespace` choice in `EnqueueMessage.swift`), and the server's reply does not show it twice.
- A batch that cannot be scheduled (a secret chat, a Stars-paid message, a legacy lead under 15 s) is **refused: never sent at once, never dropped**. It is stored as failed messages in the same transaction (`beyGramStealthMarkFailed`), and the pending manager does not send failed messages. The chat shows the usual failed marker; the user resends the message (the resend follows the stealth rules again) or deletes it. Each refusal names its reason (`BeyGramStealthRefusal`: `secretChat`, `paidStars`, `leadTooShort`, `ephemeral`, `notRecorded`, `viewOnceOrLiveLocation`, `directMessages`), recorded per message in `BeyGramStealthRefusalRegistry` (UserDefaults `beygram.stealth.refusals.<accountPeerId>`, kept a week). `beyGramStealthRefusal(accountPeerId:messageId:)` reads it for the chat. The registry is keyed by the local message id, which Postbox can reuse after a deletion, so a reason means something only while its message is failed. The UI contract (dialog keys, actions, the states of a waiting message) is `docs/stealth-ui-contract.md`.
- `resendMessages(account:messageIds:sendNowConsent:)`: a resend is scheduled like a new send, and a refused batch stays failed and is not deleted. `sendNowConsent: true` sends now, outside stealth sending. No caller passes it yet: the UI must ask the user first.
- **The date is set at dispatch.** The enqueue-time date is only a placeholder. `beyGramStealthAtDispatch` (called by `PendingMessageManager` when the request is built, after the media upload) sets the chosen delay from the server clock at that moment, never less than the lead, and stores the same date in the same transaction, so the server's reply is recognised as the scheduled send. A batch of an album shares one clock reading, so its messages carry one date. The delay waits in `BeyGramStealthScheduleRegistry` (UserDefaults `beygram.stealth.schedules.<accountPeerId>`), keyed by message id. A message is rewritten only while its stored date is the one it was registered with, so a date the user picked, or an entry left by a deleted message, is never touched. A stealth message whose entry is missing keeps its stored date; the registry and the database share the app container, so this should not happen.

## Local delayed send (a model, not wired)

`Sources/BeyGramStealthDelayedSend.swift`: `BeyGramStealthDelayedSendQueue`, one file per account
(`delayed-send-<accountPeerId>.json` in a directory the caller passes; use one excluded from backup). It holds the text the user
delays by 1 to 3600 seconds and sends nothing itself. TelegramCore's dispatcher and the UI are not wired. The screen contract is
`docs/stealth-ui-contract.md`, section 10.

- States: `queued` waits for its time. `dispatching` is written before the request. `failed` carries a reason (`expired`,
  `network`, `server`). `uncertain` is a request that a restart or a lost connection interrupted, so it may already be on the server.
- A restart turns `dispatching` into `uncertain`, never into `queued`. Only the user sends an uncertain message again.
- A queued message older than 24 hours (`retentionMillis`) becomes `failed` with `expired`, and keeps its text. Android drops it
  instead. iOS keeps it, because the ТЗ asks that the text of a failed message can be restored.
- With "hide online" on, the messages due at load are held (`heldAtLoad()`) until the user sends them. A send would show the account online.
- A chat keeps its order, as on Android (`isDue`): a newer waiting message waits while an older message of its chat is held, in flight, uncertain or failed. An expired message does not hold the others back. `sendNow` bypasses the order.
- `sendNow` sends a queued message before its time, or sends a failed or uncertain one again. It sets `sendNowConsented`: the
  user's agreement to send past a stealth refusal of an automatic send.
- The cap is 50 messages per account. The times come from the device clock, because no server is involved. `reconcile` limits what a
  jump back does.
- iOS can suspend or end the app at any time. Due messages go out only while the app runs with a chat of the account open. Nothing
  here promises the exact time.
- The entry keeps the chat, the forum topic, the reply target and the silent flag, as Android does. It does not keep the formatting, which Android keeps as entities. Before a formatted message can be delayed, the wiring must decide how to store it, or refuse it.

Deliberate differences from Android (`data/delayed/DelayedSendQueue.kt`):

- Failed and uncertain messages are kept until the user sends or deletes them. Android removes them after 24 hours, so the cap of 50 can fill with them.
- `sendNow` restarts the 24 hours of the message it sends again. Android keeps the original time, since it removes failed messages after 24 hours, so a message it sends again is never older than that.
- `sendNowConsented` is kept on disk. Android keeps its explicit flag in memory only.
- `edit` changes the text in place and keeps the due time. Android's queue has no in-place edit; its `cancel` returns the text to the composer.

Tests: `Tests/BeyGramStealthDelayedSendTests.swift`, a host `swift_test` (listed in `BUILD`).

## Not covered yet

- **Standalone sends** (`standaloneSendMessage`, share and intent paths) do not pass the hook. The sideload build has no extensions, so they are not reachable there today.
- Story views, open-content receipts, live text drafts, the settings screen and the consent prompt (UI, outside this module). The local delayed send is a model only, see below.

## Rules

- **Master switch**: BeyGramKit feature `privacyPolicy`, off by default. With it off, every hook returns the upstream behaviour.
- **Per account**: `BeyGramStealthStore`, UserDefaults key `beygram.stealth.settings.<accountPeerId>`. BeyGramKit settings are shared across accounts, so they are not used for this.
- **Per chat**: a chat's own mode (`allow` or `block`; `inherit` uses the account setting) replaces the account setting for that chat, for read receipts and typing. This is Android's `ConfigurableInteractionPolicy` (`InteractionPolicy.kt`), where a chat override replaces the account's set. Presence has no per-chat mode.
- **Dependencies**: Foundation and BeyGramKit only. No Postbox, no TelegramCore.
- **Upstream hooks are short calls** into `BeyGramStealthHooks`. Hook sites:
  - `submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift` (created with the account's peer id in `Account.swift`): presence.
  - `submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift`: `requestActivity` (typing).
  - `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift`: `pushPeerReadState` (read receipts).
  - `submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkAllChatsAsRead.swift`: read receipts of "mark all chats as read".
  - `submodules/TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift` and `ReplyThreadHistory.swift`: thread and topic reads. The helpers take the account peer id for this.
  - `submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift` with `submodules/TelegramCore/Sources/BeyGram/BeyGramStealthSend.swift`: sending and resending.
- **Scheduled sends**: flags bit 10 goes together with the date in the request builder (`PendingMessageManager`), so a date is never sent without its flag.
- **Clock**: the server clock (`network.globalTime`), never the device clock. A date in the past means an immediate send.
- **Tests**: `Tests/BeyGramStealthTests.swift` and `Tests/BeyGramStealthDelayedSendTests.swift`, host `swift_test`s for the pure logic. The TelegramCore parts have no host test. The batch logic and the failed marker need a device check: the chat shows one message, and a refused send shows as failed and goes out only after a resend.
