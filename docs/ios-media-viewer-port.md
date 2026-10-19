# BeyGram iOS — media viewing foundation (Android parity)

## Android source-of-truth
- `TdMediaMapper.kt` extracts `MessageMedia` and TDLib file IDs from photo/video/animation/document/audio/voice/video-note/sticker messages.
- `MediaFileStore.kt` registers historical snapshots once and treats `updateFile` as the newer source of truth.
- `MediaViews.kt` uses explicit download badges, local thumbnails, bounded image decode and a separate viewer.
- `MediaViewerPolicy.kt` enforces secret-media concealment and rights scoped to the visible item.

## Ported on iOS
- `TelegramMessageMedia`: photo, video, GIF/animation, document, music/audio, voice, video note, sticker. Includes caption, size, dimensions, duration, thumbnail, spoiler and secret flags.
- `TelegramMediaFile`: stores TDLib file ID, download/progress state and local completed path.
- Download via TDLib `downloadFile`; **only** use completed local TDLib files in UIImage/AVPlayer/QuickLook.
- `updateFile` refreshes progress and completion; stale message history snapshots cannot overwrite newer download state.
- Inline previews are fetched when visible; **full-size files require an explicit tap**.
- Native SwiftUI viewer for photos, AVPlayer for supported video/audio formats, QuickLook for downloaded documents.
- Downsample images off the main thread with ImageIO to reduce memory spikes.
- Android Warm/Graphite colors and chat bubble UI are preserved.

## Privacy/limitations
- No external image CDN or remote viewer endpoint.
- Secret and self-destructing media are **blocked** pending a dedicated iOS protected viewer; there is no unsafe regular share/open path.
- Spoiler thumbnails are concealed and not downloaded until the user reveals the spoiler.
- No save/share actions yet: those require exact per-message TDLib rights and explicit handling for protected chat content.
- Animated sticker TGS/WebM, streaming video/seek, special codecs, progressive photos, albums, Picture-in-Picture, waveform seeking and media sending are not in this stage.
- Unsupported codecs can fail in system AVPlayer. UX needs a tested codec-specific fallback later.
- Native iOS audio session, interruptions, media controls and background playback are deferred.
- TDLib must be authenticated; previous missing-code issue and QR login PR are independent.

## Device QA checklist
1. After login, open an ordinary chat and confirm photos render with preview/downloading state.
2. Tap to download and view a full photo; try a large file to check scroll responsiveness.
3. Download an MP4 video and verify play/pause, background closing.
4. Download a document and confirm local QuickLook works.
5. Verify secret and spoiler messages are concealed; don't test with sensitive personal media.
6. Revisit messages after download and confirm state isn't rolled back by history.
7. Uninstall/reinstall must never be used as a workaround for missing media; preserve existing Keychain database.
