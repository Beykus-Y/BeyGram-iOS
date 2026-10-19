# BeyGram iOS — global Telegram message search

This stage complements chat-name search (#16). It is an actual TDLib integration, not a filter over currently loaded message bubbles.

## Data source and behavior
- TDLib `SearchMessages` searches account-wide messages. The upstream API **excludes secret chats**.
- Initial request has `offset: ""`, `limit: 40`; subsequent pages pass through TDLib's opaque `next_offset` unchanged.
- Combined `chat_id` and `message_id` form each result's identity, preventing collisions across chats.
- A 400ms SwiftUI debounce avoids issuing a request on every keystroke.
- Revision tokens discard late results from a previous query; leaving the screen invalidates pending results.
- Errors are shown rather than represented as an empty search response.
- The search UI loads missing chat metadata via `getChat`, not fabricated titles.
- Selecting a hit opens the chat with `getChatHistory(fromMessageId:, offset: -28, limit: 60)`; if the target is in the returned history, SwiftUI scrolls it to the center.
- No search term or result is sent to third-party APIs or logged by BeyGram.

## Deliberate limits
- Does not search secret chats, because TDLib's global endpoint does not include them.
- Does not implement local full-text indexing or an external backend.
- Does not claim that searching old messages proves they were delivered successfully.
- Deep context navigation may need an additional fallback when Telegram returns a different history window.
- Media contents show generic message labels if there is no searchable text.
- Real-account testing still depends on the QR-code login path.

## QA
1. Test queries matching different chats; confirm no cross-chat result collisions.
2. Type `abc`, delete, quickly type `xyz`; older results must never reappear.
3. Search old messages, navigate and verify approximate surrounding history with original message visible.
4. Load several pages; no repeated cursor or duplicated results.
5. Cancel a search while the request is in flight; no stale results after closing.
6. Test two-word queries, punctuation and non-Latin text.
7. Compare secret-chat behavior with documented TDLib exclusion.
