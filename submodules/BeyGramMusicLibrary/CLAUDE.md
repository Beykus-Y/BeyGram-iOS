# BeyGramMusicLibrary

The local playlist library for `.bgmusic`: playlist records, their file store, the import and export layers, and the file
identifiers that Open in and Share use. It sits on `BeyGramMusicFormat`, which is pure Foundation, and it has no UI, no
UIKit, no Postbox and no TelegramCore. The music UI connects these entry points.

## Status: not compiled, not run

No macOS or Swift toolchain was available when this was written, so everything was checked by reading only. Before
relying on it, run:

    ./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMusicLibrary:BeyGramMusicLibraryTests

This module needs `BeyGramMusicFormat`, which has been in DEV since PR #68 merged. The app target does not link this
module yet, so the app build does not change until the UI links it.

## Files

- `Sources/BGMusicLibraryModel.swift`: `BGMusicLibraryPlaylist`, `BGMusicLibraryTrack`, `BGMusicLibrarySource`,
  `BGMusicLibrarySourceHint`, `BGMusicTrackAvailability`, the store protocol `BGMusicLibraryStore`, `BGMusicCoverChange`
  and `BGMusicLibraryError`.
- `Sources/BGMusicLibraryFileStore.swift`: `BGMusicLibraryFileStore`. It keeps `library.json` (schema 1) and
  `covers/<localId>/<file>`. Writes are atomic, and a lock guards each call. An unknown schema is refused and never
  overwritten.
- `Sources/BGMusicLibrary.swift`: `BGMusicLibrary`, with creation, `saveEdits` and deletion.
- `Sources/BGMusicLibraryImport.swift`: `previewImport(data:)` and `applyImport(_:action:)`.
- `Sources/BGMusicLibraryExport.swift`: `BGMusicExportOptions`, `exportManifest(for:options:)` and
  `exportFile(for:options:into:)`.
- `Sources/BGMusicIncomingFile.swift`: `BGMusicFileTypes` (the UTI, the MIME type and the extension) and
  `BGMusicIncomingFile.load(from:)`.

## Rules the layer keeps

- **Revision.** `saveEdits` grows the revision only when the content changes: title, description, author or tracks,
  compared without availability. Availability is local state, so setting it never makes a copy look edited. Section 10:
  an edited copy exports under its own id and revision, and an unchanged copy exports under its source id and revision.
- **Import.** `previewImport` saves nothing. `applyImport` accepts only the actions that fit the decision:
  - `newPlaylist` and `sameRevision`: add as a new playlist, or cancel.
  - `newerRevision`: update the copy that the preview names, add a separate copy, or cancel.
  - `olderRevision`: add a separate copy, or cancel. A file that is not newer never updates anything.
  A playlist made in the app is never overwritten by a file. Only a copy can be updated, and an update replaces that
  copy's content and cover, local edits included. The UI must say so before it applies an update.
- **Favorites** never take part in matching (the planner ignores them), and they cannot be deleted.
- **Refused files change nothing.** Unsupported (section 8), invalid, oversized and unreadable files throw before any
  save.
- **Limits.** `BGMusicIncomingFile.load` refuses a file over `BGMusicArchive.maxFileBytes` before it reads the file in
  full, and it checks the size again after the read.
- **Ids.** Local ids are ASCII letters, digits, `-` and `_`, at most 64 characters, because each one is a folder name.
  `BGMusicLibrary` makes new ids as lowercase UUIDs.
- **Export.** The manifest refuses a playlist title or a track title that is empty after cleaning, so `exportFile` throws
  for that playlist. The UI must check both fields before it exports.

## Threading

`BGMusicLibraryFileStore` locks each call. `BGMusicLibrary` adds no lock of its own, so a read followed by a save is two
calls and is not atomic as a pair. Run library work off the main thread in the app, and do not run two edits of one
playlist at once.

## What is wired and what is not

- Wired here: the library, the import and export layers, the file store, and the file identifiers.
- Not wired: the UI, and the app's open-URL and share handlers. Gemini connects those. The app's `Info.plist` declares the
  type in a separate commit of this PR (`CFBundleDocumentTypes` and `UTExportedTypeDeclarations`).
- When the app target links this module, check the framework export rules in `Telegram/CLAUDE.md`. This module uses no
  TelegramCore symbols, so it should need no export-list change.

## Rules

- No Postbox, no UIKit, no TelegramCore here. Keep the module Foundation only, on top of `BeyGramMusicFormat`.
- No user-facing text here. Errors are typed (`BGMusicLibraryError`), and the UI maps them through BeyGramL10n.
- Spec numbers in comments refer to `docs/formats/bgmusic-v1.md` in BeyGram.
