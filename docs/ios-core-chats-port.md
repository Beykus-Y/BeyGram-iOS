# BeyGram Android → iOS: core chats parity (iteration 1)

This branch ports a real subset of Android BeyGram, not a static screen.

## Android source reference

- `domain/model/ChatPreview.kt` → `TelegramChatPreview`: id/title/preview/unread, main/archive order, pin, mute.
- `domain/model/ChatMessage.kt` → `TelegramChatMessage`: id/date/outgoing/text/send state.
- `ui/screens/chats/ChatsScreen.kt` → `BeyGramChatsView`: chat list, text search, filters (All, People, Groups, Unread), pinned section, archive entry.
- `ui/screens/chat/MessageBubbleLayout.kt` → `BeyGramTailBubble` and message metadata: 20pt main corners and 6pt sender tail.
- `ui/theme/Color.kt` → `BeyGramChatColors`: the Warm light/dark token subset and six fixed avatar colors.

## Real TDLib interactions

- Main/Archive `loadChats` and `getChats`, with `getChat` enrichment.
- `updateNewChat`, `updateChatPosition`, `updateChatLastMessage`, title/unread/mute updates.
- `openChat` / `closeChat`, initial `getChatHistory` and older-history paging.
- Text `sendMessage` via typed `InputMessageContent.inputMessageText`.
- `updateNewMessage`, `updateMessageContent`, sent/failed/deleted updates.

## Safety, limits, and QA

- No mock chats. Screens display actual TDLib data **only after authorization**.
- This does not claim a working login: the real-device code-delivery issue and QR auth remain separate (see PR #6).
- Media contents are represented as descriptive placeholders (photo/video/audio/etc.), not yet playable or downloadable.
- Text sending is a real TDLib command; needs end-to-end testing with an isolated Telegram test account. Do not use it to test large groups before validation.
- Call states, notifications/APNs, Mihomo and Telegram proxy integration, avatar file loading, rich formatting/reactions, read markers, folders and message context actions are not ported yet.
- Main order is based on TDLib list positions. A `getChats` bootstrap fills visible rows; incremental events remain the source of truth.
- Chat IDs and message IDs stay Int64; no JS floating-point conversion.
- Reinstalling/sideloading over the existing app must preserve the Keychain key and TDLib database.
- Test navigation and UI on iOS 26 with a signed IPA; macOS CI compile alone does not prove correct runtime behavior.
