# Android → iOS visual parity: conversation (Phase 2)

Parent: #19, depends on Phase 1 PR #20.

## Based on Android
- `ui/screens/chat/ChatScreen.kt` `ChatTopBar()` — 40dp photo, 17sp title and 13sp secondary line.
- `ui/screens/chat/MessageBubbleLayout.kt` — 292dp max width, 20/6 rounded corners, 12dp text inset, 8dp text-top, 6dp meta bottom, body/meta/footer separation.
- `MessageReactionChips` outside the bubble.
- `BubbleMeta`: read checkmarks derived from TDLib's actual `last_read_outbox_message_id`.

## iOS implementation
- 40pt actual TDLib avatar in the conversation toolbar; two-line title and chat type. Full last-seen/online status is still deferred until user and group presence sources are wired.
- 292pt maximum bubble width, 20/6 tail shape, text inset 12pt, time 12pt and 8pt item spacing.
- Photo/video/GIF messages with no caption show a timestamp overlay on the thumbnail, rather than a separate row beneath it.
- Reactions appear outside the message body as Android does; selected reactions keep accent color.
- Outgoing states: pending/failed, one tick for sent, two ticks for read when TDLib has a matching outbox watermark. No optimistic read receipts.
- Sticker and video-note bubble container is transparent.
- Existing reply, edit, audio/video viewer, media upload, QR/2FA and chat sessions are unchanged.

## Deliberately deferred
- Real presence subtitle, in-chat search, pinned message bar, dynamic background/wallpaper, sender captions, message quotes, bubble styles other than rounded, full custom video-note/voice players, swipe-to-reply.
- Pixel-level differences due to safe areas/keyboard/system toolbar must be judged on-device using paired screenshots.

## QA
1. In one private chat send short, long and multiline text; compare message widths and spacing.
2. Mark outgoing messages as read from another Telegram client; verify checkmarks update.
3. Play downloaded photo/video from media bubble; check the overlay timestamp doesn't swallow the tap.
4. Test reaction chips, long press context menu and reply/edit after the new layout.
5. Test dark/light Warm/Graphite and iPhone keyboard/safe area.
6. Compile for iPhone; smoke test the already-working login/QR/2FA, file sends and messages.

This is a visual-parity slice; it doesn't complete #19.
