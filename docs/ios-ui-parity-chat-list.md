# Android → iOS visual parity: chat list (Phase 1)

Reference Android DEV: `ui/screens/chats/ChatsScreen.kt`, `SwipeChatRow.kt`.
Parent issue: #19.

## Implemented
- Main chat list row uses Android 54dp avatar, 14dp spacing, 16sp title, 12sp time, 14sp preview and 20dp side inset.
- Unread chats color the timestamp with the active accent.
- TDLib's actual `last_message.is_outgoing` provides the Android-style `Вы: ` preview prefix.
- Real TDLib `sending_state` and `last_read_outbox_message_id` distinguish sending, failed, sent and read; `updateChatReadOutbox` updates the UI.
- Muted bell and unread count are placed on the second row, with a muted grayscale count.
- The archive is now a rounded `surface` card with 44pt icon and chat/unread summary, inspired by Android `ArchiveRow`.
- Pinned section is shown only for All filter with empty search, exactly as Android `ChatsScreen`.
- Search from list exposes an account-wide message-search action as in Android.
- Chip metrics are 34pt tall with matching paddings.
- Compact/Comfortable/Spacious row densities follow Android 6/10/14dp row vertical paddings and are persisted with `@AppStorage`.
- Existing real Telegram avatars from #18 are preserved.

## Deliberately not implemented in this PR
- Swipe-to-archive/read gestures and destructive chat actions: those require correct TDLib permission handling and confirmation.
- Self-profile header avatar, create-channel and Saved Messages shortcuts: they must be wired to real screens, not fabricated buttons.
- Main chat composer/bubble layout, message sender identity in groups, statuses for contact online presence, media-specific BubbleLayouts, complete theme engine.
- This phase is visual parity, not pixel identity between different system navigation/chrome.

## Tests
1. Compare Android and iPhone chat list with same account, Warm/Graphite and light/dark.
2. Observe incoming, outgoing, unread, pinned, archived, muted and failed-send previews.
3. Check one/double read marks as a message is read in another client.
4. Switch Compact/Comfortable/Spacious; verify rows adapt without truncating avatar or badges.
5. Search a chat, use message search, navigate back and switch filters.
6. Verify login/QR/2FA, media and navigation didn't regress.

Do not merge into Stable/main before iPhone visual review. CI proves compilation only.
