# Telegram avatars — Android BeyGram parity

## Implementation
- Parse TDLib `ChatPhotoInfo.small` (160×160 JPEG) from each chat and the user's `profile_photo.small` from contacts.
- Avoid downloading big/full-size photo variants in rows.
- Reuse TDLib's `downloadFile`, `updateFile` and `TelegramMediaFile` cache state; no external image host or URLSession calls.
- SwiftUI's `BeyGramLocalMediaImage` downsamples the completed local image off the main thread.
- The visual fallback remains a deterministic colored circular avatar with the chat/contact initials. Missing or failed downloads must not make a row disappear.
- Avatar photos update when TDLib delivers `updateChatPhoto` or `updateUser`.
- Use the component in chats, contacts and global message-search result cards.
- Only local `is_downloading_completed` paths are displayed; paths are never logged.

## QA after successful Telegram login
1. Confirm chat and contact photos match the official Telegram (no random placeholders for existing avatars).
2. Scroll through 100+ chats; verify smoothness and absence of simultaneous full-resolution decodes.
3. Change a profile photo in another client; verify TDLib update changes the avatar file.
4. Open an account without a photo; verify initials remain centered.
5. Toggle Warm/Graphite and light/dark themes.
6. Disable the network during an avatar download; no crash or repeated tight retry loop.
7. Inspect memory usage and disk cache; verify all downloads remain within TDLib files directory.

This change does **not** implement large profile-photo viewers, photo-history galleries or user stories.
