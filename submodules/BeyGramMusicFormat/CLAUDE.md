# BeyGramMusicFormat

Pure Foundation model of the `.bgmusic` v1 snapshot format: text cleaning, strict JSON, the manifest, the ZIP container
with a DEFLATE reader, the import decision and planner, export naming and identity, and the track keys shared with
Android. No UIKit, no Postbox. The spec is `docs/formats/bgmusic-v1.md` in the Android repository (BeyGram); section
numbers below refer to it. The Android implementation is `app/src/main/java/com/beykus/beygram/data/music/bgmusic/`.

## Status: not compiled, not run

No macOS toolchain was available when this code and its tests were written, and there is no Swift toolchain on the
Linux host either. Everything here was checked by reading only. Before relying on it, run:

    ./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMusicFormat:BeyGramMusicFormatTests

Tests live in `Tests/BGMusicFormatTests.swift` (older, pre-existing) and `Tests/BGMusicPipelineTests.swift`. The
pipeline tests build ZIP files byte by byte, so they can declare sizes that do not match the bytes.

## Files

- `Sources/BGMusicText.swift`: section 7 cleaning. Single-line fields turn each line break into one space. Descriptions
  keep at most two LF in a row.
- `Sources/BGMusicJSON.swift`: `BGMusicStrictJSON`, RFC 8259 with duplicate keys refused (compared by UTF-8 bytes, as
  Android compares them), nesting capped at 16, and a leading BOM dropped.
- `Sources/BGMusicManifest.swift`: manifest model, `decode` (read rules) and `normalized()` / `jsonData()` (write rules).
- `Sources/BGMusicArchive.swift`: ZIP reader and writer. Exact names for `manifest.json` and the covers; duplicates
  ignore case. Sizes are counted while the bytes are inflated, never taken from the header.
- `Sources/BGMusicInflate.swift`: raw DEFLATE. Over-limit output throws `.overflow`, kept apart from `.corrupt`.
- `Sources/BGMusicImport.swift`: `BGMusicFileReader.read(Data)`, `BGMusicImportDecision`, `BGMusicLocalPlaylistRef`,
  `BGMusicImportPlanner`.
- `Sources/BGMusicExport.swift`: `BGMusicExportIdentity`, `BGMusicFileNaming`, `BGMusicPackage` (`make`, `writeFile`),
  `BGMusicExportSummary`.
- `Sources/BGMusicTrackKey.swift`: `ym:` and `bot:` row keys (unchanged).

## Read rules that now match the spec and the Android reader

- A broken `audio_hash` is dropped. It does not refuse the file. The hash must be `sha256:` plus 64 lowercase hex.
- Source hints: broken and unknown ones are dropped, a leading `@` is accepted, and at most eight valid hints are kept.
  Hints are never a reason to refuse a file.
- `artist` and `album` are required but may be empty. `description` may be missing or null, but any other non-string
  is `badField`. `author` must be an object with a name.
- Limits: manifest 2 MiB (`manifestTooLarge`), cover 1 MiB (`coverTooLarge`), total uncompressed 4 MiB (`tooLarge`).
  The archive's declared sizes are checked only after the bytes are read, as Android does.
- `playlist_id` and track `id` are ASCII hex only. `Character.isHexDigit` also accepts fullwidth digits, so it is not
  used.

## Known differences from Android (reason codes only, both platforms refuse the file)

- The spec says the nested-archive signature check covers any entry. iOS applies it to every entry, including the
  manifest and the cover. Android applies it only to unknown entries. So a manifest that starts with `PK\x03\x04` gives
  `badEntryName` here and `badJson` on Android.
- Android writes the manifest as DEFLATE, while this writer always writes STORED. Both are valid for readers.
- Android's reader streams local headers, while this one reads the central directory. The two agree on valid archives.

## Functional layer and what is not wired

- Implemented as pure functions: reading a file, the import decision (`newPlaylist`, `sameRevision`, `newerRevision`,
  `olderRevision`), matching against a library of `BGMusicLocalPlaylistRef`, export identity, file names, writing, and
  an export summary for the sheet that shows what the file carries (section 9).
- Not implemented: there is no local playlist store in the iOS app. DEV has no library model for BeyGram playlists to
  import into or export from. Import and export screens, and the "Open in" / share-sheet entry points (a UTI and a
  document type for `application/vnd.beygram.music+zip`, `.bgmusic`), need that library first. They belong to the music
  core work and to the UI work that Gemini is doing.
- The Yandex Music bridge (`BeyGramYandexMusic`) is separate. Its track rows use the `ym:` keys from `BGMusicTrackKey`.

## Profile music (audit, no code changes in this module)

- Backend, in TelegramCore, `Sources/TelegramEngine/Peers/SavedMusic.swift`: `ProfileSavedMusicContext(account:peerId:)`.
  It reads any peer's list through `users.getSavedMusic` (32 per page, cached per peer), adds with `account.saveMusic`
  (`afterId` gives the position, so a nil `afterFile` moves to the front), removes with `account.saveMusic` and
  `unsave`, and keeps the saved-id set current through `account.getSavedMusicIds`.
- Privacy: `PrivacySettings.savedMusic` and `UpdatedAccountPrivacySettings.swift` (`inputPrivacyKeySavedMusic`).
- Consumers: `PeerInfoData.swift`, `AttachmentFileController`, `AccountContext/MediaManager.swift`. The profile strip
  picks its track with `PeerInfoProfileMusic.swift`.
- Android: the profile screen is `ui/screens/profile/ProfileMusic.kt`. Its changes go through TDLib profile-audio calls
  in `data/tdlib/TdProfiles.kt` (`removeProfileAudio`, `moveProfileAudioToFront`).
- Yandex tracks cannot go on the profile. The server takes only documents (`inputDocument`), so they stay separate.
- What remains is UI, which belongs to Gemini. No gap in the backend was found in the code reviewed.

## Rules

- Do not add a Postbox import here. This module stays pure.
- Keep the spec numbers in comments. A rule that differs from the spec or from Android is a bug, unless it is listed
  under "Known differences" above.
