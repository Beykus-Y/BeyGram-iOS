# Stealth audit: who can show the account as online

Scope: the iOS client as it stands in DEV after PR #64, PR #92 (open) and this PR. Read in code. Nothing here is
checked on a device yet.

## Writers of the online status (client)

| Source | Where | What it does | Hidden by "hide online" |
| --- | --- | --- | --- |
| `Account.shouldKeepOnlinePresence` (input) | `TelegramUI/Sources/SharedWakeupManager.swift:1150` | true while the app is in the foreground and the account is the primary one | input, not a write |
| `Account.shouldKeepOnlinePresence` set to false | `TelegramUI/Sources/ApplicationContext.swift:858`, `SharedWakeupManager.swift:1197` | presence is not wanted | input, not a write |
| `ManagedAccountPresence` | `TelegramCore/Sources/State/ManagedAccountPresence.swift` | the only caller of `account.updateStatus`: offline false while online is wanted, offline true otherwise; repeated every 30 s while online | yes, the request is offline when hidden |
| `Network.isUserOnline`, then `NetworkEngineSession.setOnline` | `TelegramCore/Sources/Network/Network.swift`, `MTProtoRustEngine/Sources/MTProtoRustEngine/RustNetworkSession.swift` | selects the keepalive timing of the Rust engine; sends no presence request | no, the flag still follows the app state |
| `messages.setTyping` | `TelegramCore/Sources/State/ManagedLocalInputActivities.swift:189` | typing activity | yes, per chat (`hideTyping`, chat overrides) |
| `messages.setTyping` (stop draft) | `TelegramCore/Sources/State/TypingDraftStop.swift:98` | ends a draft activity that was already sent | no, it only ends an activity that was started |
| `messages.readHistory`, `channels.readHistory` | `TelegramCore/Sources/State/SynchronizePeerReadState.swift:258` | read receipts | yes, per chat (`hideReadReceipts`) |
| `messages.readHistory` through "mark all as read" | `TelegramCore/Sources/TelegramEngine/Messages/MarkAllChatsAsRead.swift:28` | read receipts | yes, hidden chats are skipped |
| `messages.readDiscussion`, `messages.readSavedHistory` | `TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift` | thread and topic reads | no, open gap (see below) |

## Server side

The server can mark the account online by itself. Requests such as sending a message, reading, typing or receiving
updates may count as activity, and the server's own last-seen logic is not visible to the client. The client can only
avoid its own explicit writes. "Hide online" therefore promises that BeyGram itself does not ask for the online status.
It does not promise that no other request will show the account as online for a while.

To check on a device before any wider claim: turn hide online on, send a message from the hidden account, and watch
the status shown to another account for five minutes.

## Lifecycle checks

- Launch and return from the background: the foreground flag reaches `shouldKeepOnlinePresence`. With hide online on,
  the request is offline. Before this PR, a change made while the account was online took up to 30 seconds to apply
  (the 30-second refresh was the first evaluation); see "Gaps" below.
- Opening chats: no presence write. History and read requests follow the rules in the table.
- Account switching: only the primary account can be requested online (`primary && inForeground`), and each account
  has its own presence manager.
- Server-scheduled messages: the server publishes them. Whether the server marks the sender as online at publish time
  is not known and is not checked.

## Gaps and decisions

1. Fixed in this PR: a change of "hide online" applies at once. `BeyGramStealthStore` posts
   `didChangeNotification` after a real change, and `ManagedAccountPresence` evaluates presence again while the account
   is requested online.
2. Open: thread and topic reads (`messages.readDiscussion`, `messages.readSavedHistory`) are not gated yet.
3. Open: `Network.isUserOnline` keeps the keepalive timing of an online account while the account is hidden. Changing
   it could affect how incoming messages reach a backgrounded app, so it needs a device measurement first.
