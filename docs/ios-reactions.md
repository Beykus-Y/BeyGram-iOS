# BeyGram iOS — emoji reactions

Android reference: `data/tdlib/TdMessageReactions.kt`, `ui/screens/chat/MessageReactions.kt`.

- Parse reaction summary from each message's `interaction_info.reactions`.
- Render emoji reaction counts and chosen state inside conversation bubbles.
- Handle TDLib `updateMessageInteractionInfo` to update counts while the chat is open.
- Preserve reactions on partial `updateMessageContent` events.
- Fetch `getMessageAvailableReactions` when opening a message action sheet; use only the server-provided allowed basic emoji list.
- `addMessageReaction` and `removeMessageReaction` for emoji only. A chosen reaction can be removed directly from its chip.
- Skip premium/custom/paid reactions until subscription checks and custom emoji rendering are ported.
- No optimistic count changes; reflect results only after TDLib updates.
- Server errors are presented in the existing chat error banner.

QA:
1. Open a chat with multiple reactions; compare counts to Telegram.
2. Toggle your chosen reaction, ensure it disappears on TDLib update.
3. Open action sheet for a message that disallows reactions; no emoji should be offered.
4. Verify no reaction leakage when switching between messages and chats.
5. Message edits should not erase reaction counters on the client.
6. Real-device confirmation deferred until login is functional.
