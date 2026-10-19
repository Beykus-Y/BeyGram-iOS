# Android → iOS chat list actions (UI parity Phase 3a)

Parent: #19. Source of truth: Android BeyGram's `ChatActionsSheet` and TDLib updates.

## Implemented
- Long press on a listed chat: context menu for archive / unarchive, pin / unpin, mark unread / read.
- Delete for self only, and only if TDLib's `can_be_deleted_only_for_self` allows it. Explicit destructive confirmation; `revoke: false` safeguards other participants.
- `ViewMessages(forceRead: true, messageSourceChatList)` to mark the latest message read in a closed chat, then `ToggleChatIsMarkedAsUnread(false)`. Manual unread marks use `ToggleChatIsMarkedAsUnread(true)`.
- Unread filter and badges now include `is_marked_as_unread`, not just the positive counter.
- All list actions use typed requests from the project's pinned TDLibKit version and wait for TDLib `ok` + updates; no synthetic/local optimistic state.
- Errors are shown in a chat-list alert rather than hidden in the conversation's error banner.

## Deliberately not implemented
- Horizontal swipe interactions: list is a custom `ScrollView`/`LazyVStack`, where native `swipeActions` is tied to `List`. Implement and test a dedicated gesture row separately without hijacking vertical scroll or `NavigationLink`.
- Mute/unmute: do not overwrite the many fields of `ChatNotificationSettings` without safely preserving per-chat overrides and default mute semantics.
- Delete for everyone, exit group, channel owner/admin operations. Each needs separate permission rules and explicit UX.
- Server-side real-time QA cannot be performed by CI; it requires a logged-in iPhone.

## Test matrix (physical iPhone)
1. Long press a private and group chat: menu opens, normal tap still opens chat.
2. Archive and unarchive chat; check sorting, counters, archive card and restart persistence.
3. Pin/unpin from main and archive; check position updates and Telegram's pinned-chat limit error.
4. Mark an unread chat read; check counter and cross-device sync. Then mark a read chat unread; check dot/filter and cross-device sync.
5. Delete an eligible private chat, first cancel confirmation (must remain), then confirm; check other account retains history.
6. Offline/connection failures: no fake success, visible TDLib error.
7. Search-only chat should never allow a destructive/list-specific menu until loaded into a main/archive list.
8. Warm/Graphite, light/dark, large text, VoiceOver focus.

## Build gate
- macOS GitHub Actions: physical iPhone target, unsigned archive (without production API credentials in PR jobs).
- Review CI and iPhone QA before merge to DEV. Production main unchanged.
