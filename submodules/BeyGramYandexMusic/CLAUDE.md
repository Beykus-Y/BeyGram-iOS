# BeyGramYandexMusic

Yandex Music as a second source, Android-compatible (`app/src/main/java/com/beykus/beygram/data/yandex/` in BeyGram).
Off by default: needs the `yandexMusic` flag, a configured OAuth pair, and the accepted warning.

- The OAuth pair comes from the Info.plist keys `BGYandexClientId` and `BGYandexClientSecret`, filled in by the build from a
  local secrets file. Never commit them. Empty means the source stays hidden.
- All requests go through `BGYandexClient` (one queue, 250 ms gap, whole-queue pause after 429). The URLSession transport
  ignores system proxies, because Android sends Yandex requests directly.
- Track rows use `ym:<trackId>[:<albumId>]` (`BGMusicTrackKey`). A row holds no file until it is played; the signed link is
  requested each time and never stored. Files live in `Application Support/beygram/yandex`.
- Tokens are in the Keychain (`BGYandexTokenStore`). Refresh is not implemented: an expired token means signing in again.
- Not implemented: likes, playlists, waves, lyrics. Not verified against the live service: nothing here has been run.
