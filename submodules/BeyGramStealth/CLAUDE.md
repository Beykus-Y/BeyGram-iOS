# BeyGramStealth

Block B of the iOS plan (privacy and stealth, see the plan document «План переноса BeyGram на iOS»). Android reference in the BeyGram repo: `docs/conversation-architecture.md` (stealth sending, #541), `StealthSettingsStore.kt`, `TdStealthScheduler.kt`, `InteractionPolicy.kt`.

## What is hooked

- **Presence** (`account.updateStatus`): with `hideOnline`, the account is always reported offline. Account-wide only.
- **Typing and other chat activity** (`messages.setTyping`): with `hideTyping`, nothing is sent for the chat. Per-chat overrides apply.
- **Read receipts** (`messages.readHistory`, `channels.readHistory`, the sync of a chat's read state): with `hideReadReceipts`, the read state is not pushed. The sync treats it as done, so it is not sent later either. Known limitation: while the rule is on, mark-as-unread is not synced to the server.

## Not hooked yet: stealth sending

`BeyGramStealthHooks.sendDecision` and `BeyGramStealthSettings.sendDecision` exist and are tested, but no TelegramCore file calls them, so `serverScheduledSend` has no effect yet. Hooking them at send time is unsafe. `applySentGroupMessages` (`submodules/TelegramCore/Sources/State/PendingMessageManager.swift`) and `applyUpdateMessage` (`submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift`) choose the stored namespace from the local message's own `scheduleTime`, which a send-time hook does not set. Read in code, so the reply to a scheduled send would be stored as an ordinary Cloud message with the future date, and it could show twice once the server publishes it. Not checked on a device.

The follow-up must give the local message its scheduled state before the reply is applied (or pass the decided date into both functions), then check on a device that the chat shows one message. Secret chats return before any send hook (`sendSecretMessageContent`), so they need their own refusal there.

## Not yet

The settings screen (waits for the BeyGram settings section), the delayed-send queue, view-once and live-location gates, story views, open-content receipts, a consent prompt for refused sends. Read receipts that do not go through the chat's read sync are not gated yet: "mark all chats as read" (`TelegramEngine/Messages/MarkAllChatsAsRead.swift`), and thread and topic reads (`messages.readDiscussion`, `messages.readSavedHistory` in `TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift`). Live text drafts are not gated; their stop action is not gated either (it can only end an activity that was already started).

## Rules

- **Master switch**: BeyGramKit feature `privacyPolicy`, off by default. With it off, every hook returns the upstream behaviour.
- **Per account**: `BeyGramStealthStore`, UserDefaults key `beygram.stealth.settings.<accountPeerId>`. BeyGramKit settings are shared across accounts, so they are not used for this.
- **Dependencies**: Foundation and BeyGramKit only. No Postbox, no TelegramCore.
- **Upstream hooks are short calls** into `BeyGramStealthHooks`. Current hook sites:
  - `submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift`, created with the account's peer id in `Account.swift`: presence.
  - `submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift`: `requestActivity` (typing).
  - `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift`: `pushPeerReadState` (read receipts).
- **Scheduled sends** (for the follow-up): flags bit 10 must go together with `scheduleDate`. The caller sets both from `.scheduled(date)`, so a date is never sent without its flag.
- **Clock**: the server clock (`network.globalTime`), never the device clock. A date in the past means an immediate send.
- **Tests**: `Tests/BeyGramStealthTests.swift`, a host `swift_test` for the pure logic.
