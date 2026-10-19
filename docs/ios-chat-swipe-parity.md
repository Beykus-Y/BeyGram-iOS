# Swipe gestures for chat list (iOS UI parity Phase 3b)

Parent: #19, #23. Depends on chat context actions PR #22.

## Implementation
- `BeyGramSwipeChatRow` wraps the custom `ScrollView/LazyVStack` row; no migration to `List` and no invalid use of `.swipeActions`.
- Swipe left to reveal two 84pt actions: read/unread and archive/restore, mirroring Android `SwipeChatRow.kt`.
- Swipe right beyond the threshold when the row is closed to toggle read/unread; swipe right when open to close.
- Vertical drags dominate unless horizontal travel is clearly larger (1.5x); gesture runs simultaneously with parent scrolling.
- One active/open swipe row, held by the parent `openSwipeChatID`.
- Tapping an open row closes the swipe; tapping a closed row navigates using `NavigationStack(path:)`.
- Existing long-press menu, permission-confirmed delete, archive view, real TDLib callbacks are unchanged.
- App respects Reduce Motion; accessibility action labels are included for supported rows.

## Manual QA (physical iPhone)
1. Scroll a list vertically, including near-diagonal gestures; no accidental actions or horizontal drift.
2. Swipe to reveal; tap read/unread and archive/restore; verify TDLib updates and cross-device state.
3. Swipe right to mark read/unread; check the unread filter and manually-marked-unread dot.
4. Open row A, swipe row B; only row B should remain open. Tap the open row to close, second tap to navigate.
5. Long press a row to open the previous context menu, including delete confirmation.
6. Try archive, search results outside main/archive, pinned chat, filters, empty chat, VoiceOver, Dynamic Type, RTL, Reduce Motion.
7. Force failure/offline conditions; row actions should surface errors without false local state.

## Merge order
1. PR #22 into `DEV` after CI/device QA.
2. Rebase/retarget this PR to `DEV`; review its isolated diff and build.
3. Keep `main` untouched. Mute/unmute still requires preserving all per-chat notification overrides; tracked in #23.
