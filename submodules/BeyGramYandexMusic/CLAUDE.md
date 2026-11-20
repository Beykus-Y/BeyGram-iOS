# BeyGramYandexMusic

Yandex Music as a second source, Android-compatible (`app/src/main/java/com/beykus/beygram/data/yandex/` in BeyGram).
Off by default: needs the `yandexMusic` flag, a configured OAuth pair, and the accepted warning.

- The OAuth pair comes from the Info.plist keys `BGYandexClientId` and `BGYandexClientSecret`, filled in by the build from a
  local secrets file. Never commit them. Empty means the source stays hidden.
- All requests go through `BGYandexClient`: one queue, 250 ms gap, whole-queue pause after 429, the Android client header
  and `User-Agent: okhttp/4.12.0`. The URLSession transport ignores system proxies, because Android sends Yandex requests
  directly.
- Sessions (`BGYandexService`): tokens are in the Keychain (`BGYandexTokenStore`), never in UserDefaults or logs. A token
  about to expire (5 minutes) is refreshed with `grant_type=refresh_token`, once for all callers. A refused refresh
  (400 to 403) ends the session, and so does a token the service refuses after one refresh. Sign-in, sign-out and a
  refused refresh move the sign-in generation; a request that started under another generation drops its result.
- Track rows use `ym:<trackId>[:<albumId>]` (`BGMusicTrackKey`). A row holds no file until it is played; the signed link is
  requested each time and never stored. Files live in the folder the service is given; the screens pass `Application Support/beygram/yandex`. Full tracks need an account
  with a subscription (`hasPlus`); previews are never played as full tracks.
- Downloads are checked before they are kept (`BGYandexAudioCheck`): a 2xx answer must start with an ID3 tag or an MPEG
  frame, carry no text, JSON, XML or HTML type, be at least 8 KB, and match its Content-Length (not compared when the body
  was encoded). A refused body is deleted and reported to `BGYandexTrackResolver.onRejectedDownload`, which gets sizes, the
  first bytes and the media type, never the link, token or path. The track gets one fresh link, then `invalidFile`. A
  cached file gets the same check (size and start only) before it plays; one that fails is downloaded again.
- Public surface for the screens (Gemini owns the screens): `search`, `likedTracks`, `likedTrackIds`, `setLiked`,
  `setDisliked`, `playlists`, `likedPlaylists`, `playlistTracks`, `playlistByUuid`, `likedAlbums`, `album`, `lyrics`
  (`BGYandexLyrics`, kept 10 minutes when found, 1 minute when it failed), `localFile` (the resolver), and
  `makeWave(seeds:)`, which returns a `BGYandexWaveSession` (`first`, `more`, `sendFeedback`, `feedbackEvent(for:)`,
  `likeFeedback`, `givenIds`, `restore`). `BGYandexListenTracker` turns player states into radio listening events. `BGYandexLink.target(from:)` gives what a Yandex
  Music address opens natively (album, track, track in album, playlist); any other address stays a web link. `BGYandexRuntime.shared` is the one service of the app: playback and the screens must use
  it, and the new controller still builds its own instance. `BGYandexService.playableFile(rowKey:)` gives the player a local
  file for a `ym:` row, or a `BGYandexPlaybackError` (`notSignedIn`, `subscriptionRequired`, `unavailable`, `rateLimited`,
  `network`, `invalidFile`).
- Radio: calls run one at a time; the queue hint is the last 50 tracks; two empty batches in a row stop a request for now;
  a session the service forgets or ends is replaced by a new one with the same seeds. The seed `user:onyourwave` is the one
  verified against the service. The diversity seeds and the `track:`, `artist:`, `album:` and `playlist:` formats are
  Android's and are not checked on the live service.
- Player contract (Foundation only, no UI): `BGYandexTrackInfo` is what the player shows for a `ym:` row. Its title is nil when
  Yandex sent none, never a file name; it also has the artists, album, duration, cover URL, availability and liked state.
  `BGYandexWaveQueue` keeps the radio a few tracks ahead of the player: it refills when three or fewer remain, pauses 30 s
  after a failed or empty refill, starts each track's file once in advance (`prepare`), and reports started, finished and
  skipped tracks and likes as radio events. It takes a `BGYandexWaveSource`, which `BGYandexWaveSession` conforms to. Dislike
  is not a radio event here: its endpoint is unverified.
- Unverified: the dislike endpoint and form, and the answer shape of the refresh. Not in Android, so not built: artist and
  album search. Yandex tracks cannot be forwarded, added to a profile or exported to `.bgmusic`.
- Status: written and statically checked (delimiter balance, cross-file references, a line-by-line trace of the unit
  tests against the code). Not compiled: the authoring environment has no Swift toolchain. Not run on the live service and
  not device-verified. Unit tests: `Tests/BGYandexTests.swift`, `Tests/BGYandexAudioCheckTests.swift`, `Tests/BGYandexTrackInfoTests.swift` and `Tests/BGYandexWaveQueueTests.swift`, host `swift_test` target `BeyGramYandexMusicTests`.
