# BeyGram iOS — outgoing photos and files

Based on Android's `MediaComposer.kt` and `OutgoingMediaContent.kt`.

## Implemented
- Native PhotosPicker for up to 10 image selections (iOS 16+).
- Native Files document picker, including security-scoped URL handling.
- Every attachment is staged inside the app's Caches directory before TDLib receives its local path.
- Photos are downsampled off the UI thread to at most 2560 px and encoded as JPEG under TDLib's 10 MB photo limit.
- A conservative initial 200 MB file cap prevents copying arbitrarily large documents before there is a fully tested upload progress/cleanup system.
- Inline attachment strip with name, size, remove button and per-message caption, based on Android composer.
- Uses TDLibKit's typed `InputFileLocal`, `InputPhoto`, `InputDocument`, `InputMessagePhoto`, `InputMessageDocument`.
- If more than one item is queued, each is sent as a separate message; the caption applies to the first. **Albums not implemented.**
- SendMessage's immediate response only confirms TDLib accepted the request; it does not mean the server has delivered it.
- Staged files are kept for up to 7 days; don't delete while TDLib upload might be pending. The cleanup helper will be wired to a later lifecycle stage.
- Existing reply target is used for selected attachments. Multi-file caption/reply semantics must be validated on a test account.

## Still missing
- Video picker / encoding profiles, media albums, voice recordings, send progress/error retry UI, custom photo editing, full streaming, arbitrary file sizes, share extension, APNs and Mihomo.
- Real-device QA requires authorization (the independent QR login PR remains outside this branch).

## iPhone QA
- Select a photo, cancel it, then select a different photo; verify no ghost attachments.
- Select PDF from Files, send with caption, verify file opens in official Telegram.
- Repeat in a chat with permissions for sending media disabled; TDLib must produce a visible error and keep the unsent attachment.
- Send two photos: they should appear as separate messages with caption only on the first.
- Send a photo while replying to another message and verify reply link.
- Test backgrounding during upload. UI success is not proof the upload was delivered.
- Don't delete/reinstall the app to test the upload pipeline: preserve TDLib local database.
