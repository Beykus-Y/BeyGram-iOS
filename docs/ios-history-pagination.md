# Automatic iOS chat history pagination

Parent roadmap: #10. Based on conversation parity PR #21 (target branch `feature/ios-ui-parity-conversation-v1`).

## Motivation
Prior UI required "Показать более ранние сообщения" to load each history page. Worse, its generic `.onChange(of: messages.count)` always `scrollTo(messages.last)`, which jumps to the bottom when older messages are prepended.

## Implementation
- Replace the manual paging button with an unobtrusive progress indicator.
- Load the next TDLib `GetChatHistory` page when the oldest row reaches the viewport after the initial conversation positioning.
- Reuse `TelegramConversations.loadOlder`'s existing loading/exhausted guards, rather than issuing parallel requests.
- On successful prepend, anchor the scroll to the previous first message instead of scrolling to the latest.
- Apply initial scroll-to-bottom only once on a regular chat; center a global-search target message if provided.
- On subsequently arriving messages, scroll to bottom only when the previous last message was visible. Reading an older part of the chat must not drag the user down.
- No mutation of stored sessions, TDLib cache, QR/2FA, or outgoing media.

## Acceptance tests (real iPhone)
1. Open a long chat: starts at the latest message; no load-more button.
2. Scroll to top: old history loads automatically, prior oldest message remains around top rather than jumping to bottom.
3. Keep paging several times: no duplicate IDs, no unbounded simultaneous TDLib requests, no permanent loading when exhausted.
4. While reading near the top, receive a new message from another client: scroll position remains stable.
5. While near bottom, send/receive a message: bottom autoscroll remains useful.
6. Open a global-search result near the middle: initial message centers; no forced jump to bottom.
7. Network error while loading older history: normal error path; retry after scrolling away and back.
8. Test Warm/Graphite, light/dark, large text and keyboard opening.

## Merge order
1. Land #21 in `DEV` after CI and real-iPhone visual QA.
2. Retarget this PR from #21 feature branch to `DEV`; only merge after CI and the acceptance tests above.
3. `main` unaffected.
