# BeyGram iOS — Android message actions parity

## Implemented

This branch follows Android `TdConversationActions.kt`, `MessageContextDialog.kt` and `MessageBubbleLayout.kt` but uses native SwiftUI / TDLibKit.

- Lazy visible-message read tracking: each message is reported to TDLib `viewMessages` only when its SwiftUI bubble actually appears; updates are batched with a short debounce.
- A message-scoped action sheet calls `getMessageProperties` for that message id, not for the previous selection.
- Copy text (when allowed), reply to the original message, edit plain text, delete only for self or for all users according to TDLib permissions.
- Reply preview and edit composer state can be cancelled. Real TDLib `sendMessage` reply information is attached to outgoing text.
- A destructive delete confirmation is required; the server ultimately validates each request.
- Errors are surfaced in the existing conversation error area.

## Boundaries

- Not yet implemented: quote-selected-text, forward, multi-message selection, scheduled/edit media, reactions, markdown/HTML formatting tools, topic-specific reply targets.
- The app must have a fully authorized TDLib session; compile-time green CI does not imply server permission testing.
- The base branch is media-viewer PR #11, so merge #11 first. Preserve local database and Keychain.

## QA

- Open private chat: scroll messages; only visible bubbles should generate read updates.
- Test reply to own and incoming messages; check reply target in official Telegram.
- Test editing self-sent text; verify updateMessageContent reflects server result.
- Verify actions sheet respects rights in channels, groups and private chats.
- Test delete for self vs everyone; require confirmation and inspect real TDLib error messages.
- Closing a chat cancels pending read batches; opening another chat must not reuse previous message permissions.
