# iOS per-chat mute and unmute

Parent: #19 and #23. Based on the context menu from #22 and the swipe-row work in #24.

## Implementation
- A **Звук уведомлений** submenu on listed chats offers two explicit commands: **Выключить звук** and **Включить звук**.
- Read the existing TDLib `chat.notification_settings` and decode the full `ChatNotificationSettings` object from the exact pinned TDLibKit API.
- Build a replacement copying every independent field (mentions, pinned messages, preview, sound IDs, story settings, default flags).
- Override only `muteFor` and `useDefaultMuteFor` for the selected chat:
  - mute: a duration longer than 366 days, interpreted by TDLib as permanent;
  - unmute: duration 0, with `useDefaultMuteFor = false` so inherited global mute does not override explicit unmute.
- No blind defaults if decoding fails. Errors surface in the existing chat-list alert.
- Wait for `ok`, then render real `updateChatNotificationSettings` from TDLib. No local optimistic overrides.
- Both commands remain visible, including when global scope mute is inherited, avoiding a falsely inferred effective state from the per-chat `mute_for` field.

## Physical-device QA
1. Save custom notification sound/preview/mentions/stories in another Telegram client; mute/unmute in BeyGram and check other fields remain identical.
2. Mute and unmute private chats, groups, and channels.
3. Globally muted scope: force unmute one chat; verify exception works.
4. Already muted/unmuted chat: reapplying command must not corrupt settings.
5. Offline/error response must show an error and never change a local switch optimistically.
6. Verify `updateChatNotificationSettings` drives the muted icon; restart and cross-client synchronization.
7. Verify long-press menus remain accessible alongside the new swipe gestures.

## Limits
Current list `isMuted` displays per-chat `mute_for > 0`, not an independently fetched effective inherited global scope status. The menu therefore exposes both explicit actions and avoids a misleading single toggle label.

`main` remains untouched. Requires CI, review, and physical iPhone QA before merge to `DEV` in dependency order.
