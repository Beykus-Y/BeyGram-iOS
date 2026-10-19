# BeyGram iOS: video sender + media albums

Reference implementation: Android BeyGram `OutgoingMediaContent.kt`, `MediaComposer.kt`.

## Video from Photos
- PhotosPicker now supports both images and videos.
- A CoreTransferable FileRepresentation copies the video from the Photos provider before its temporary URL expires.
- The video is passed by **local file URL**, never copied into Data in RAM.
- AVFoundation reads actual duration, width and height, accounting for orientation.
- AVAssetExportSession creates a compatible H.264 MP4 file and optimizes it for playback over the network.
- Initial limits: 350 MB input, 200 MB encoded output. Oversized/unsupported media is rejected with a visible message.
- TDLib InputVideo receives duration/dimensions, local path, streaming-enabled flag.
- Staged upload files remain available for TDLib's asynchronous upload after sendMessage returns.
- The PhotosPicker intermediate file is deleted after preparation, the final staged MP4 is not deleted on TDLib acceptance.

## Albums
- 2–10 photos and/or videos: sendMessageAlbum, a genuine Telegram grouped message.
- One caption on the first media item.
- All media in the album use show_caption_above_media=false; no paid/custom media in this phase.
- All referenced file paths are checked before sending.
- Failure keeps the queue for retry; the app never silently falls back to multiple sendMessage calls.
- Single photo/video and documents still use sendMessage.
- Album response must include the expected number of messages.

## Pending QA
- Test 1 image, 1 video, 2 photos, 1 photo+1 video, 10 photos.
- Long/vertical video, iPhone HEVC original requiring H.264 conversion, big video limit, and memory use.
- Incoming media progress with updateFile and sendSucceeded/sendFailed.
- Network failure and retry without deleting staged files.
- Audio focus, playback, PiP and background upload require later work.
- Real-device Telegram login still gated by separate QR auth PR #6.

Xcode compilation only validates the client implementation, not actual Telegram delivery. Do not ship this as Stable without device testing.
