# BeyGram iOS — Аудит открытых PR и консолидация в DEV (2026-11-23)

## Исходное состояние
- Целевая ветка: `DEV` (`9cef81a9a1486cef1ece7c8c8d8b338528224eec`)
- Интеграционная ветка CI/Parity: `integration/parity-ci` (`953ac27f982ae2cf04b2cf391be75027d1148595`, строго +45 коммитов от `DEV`, `merge-base == DEV`)
- Открытых PR на момент аудита: **43**

## Классификация по фактическому содержимому
1. **Полностью присутствуют в `integration/parity-ci` (предки или эквивалентные патчи / более новые версии)**: 41 PR
   - Включая `BG Wave` (#65, #75, #77, #87, #88, #91, #118, #134), `BG Mix` (#59, #81, #93, #96, #98, #113), `Yandex` (#69, #84, #85, #110, #111), `Mihomo` (#86, #89, #90), `Stealth` (#92, #108, #115, #116, #117, #132), `Export` (#99, #109), `Diagnostics` (#100, #101, #102), `Regex/RE2` (#104, #105), `BG Push` (#95), `Music/BGMusicLibrary` (#79), `Parity docs` (#114), и `Music Recovery` (#127, #131).
2. **Содержит уникальные изменения, не вошедшие в `integration/parity-ci`**: 2 PR + 1 частично:
   - **PR #120** (`codex/119-cache-validation`, `d88505f486`): `BGYandexService.discardUnplayableFile(rowKey:)` и тесты декодера с `synthetic-tone.mp3`. **Интегрировано** (конфликт в `BGYandexAudioCheckTests.swift` разрешён с сохранением обоих тестов).
   - **PR #121** (`codex/119-playback-failure`, `4ee068c008`): `BGMixPlaybackRecovery.swift`, `BGMixFailureStreak`, тесты `BGMixPlaybackRecoveryTests.swift`, вызов `discardUnplayableFile` в `SharedMediaBGMix.swift` и интеграция в `SharedMediaPlayer.swift`. **Интегрировано** (конфликт в `submodules/BeyGramYandexMusic/BUILD` разрешён с сохранением всех тест-файлов; архитектура `SharedMediaBGMix` / `SharedMediaPlayer` из `fix/recovery-1008` и `fix/music-engine-1009` сохранена полностью).
   - **PR #122** (`codex/119-runtime-bridge`, `abd0dcbe77`): общий `BGYandexRuntime.shared` уже присутствует в `BeyGramYandexMusicController.swift` на `integration/parity-ci`; остальные изменения покрыты интеграцией #120 и #121.

## Полная таблица аудита (43 PR)

| PR | Ветка (`head`) | База (`base`) | Статус при аудите | Решение / Обоснование |
|---:|---|---|---|---|
| #59 | `claude/project-thread-7ckqig` | `DEV` | Music: BG Music settings, .bgmusic ZIP and JSON, Yandex pure logic (#49) | Устарел / замещён актуальной реализацией `BeyGramMusicUI` (`BeyGramMusicCenterViewControllerImpl`, `BeyGramDesign`, `BeyGramMusicSession`) в `DEV` и `parity-ci`. |
| #65 | `feature/ios-functional-parity-wave` | `DEV` | BG Wave на iOS: транспортно-независимое ядро (этап 1) и сборка libdatachannel (этап 1b) | Весь функционал BG Wave (Stage 1..Facade, включая threading note и UI contract docs) уже в `integration/parity-ci`. |
| #69 | `feature/ios-functional-parity-yandex` | `DEV` | Yandex Music: service layer for Android parity | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-2). |
| #75 | `feature/ios-functional-parity-music-wave-exports` | `DEV` | BeyGramMedia: export BG Wave adapter sources for BGWaveCore | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #77 | `feature/ios-bgwave-local-network-permission` | `DEV` | feat(bgwave): NSLocalNetworkUsageDescription with RU/EN texts | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #79 | `feature/bgmusic-library-share` | `DEV` | BeyGramMusicLibrary: local playlists and .bgmusic import, export and Open in layers | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-3). |
| #81 | `feature/ios-functional-parity-music-mediamanager` | `DEV` | BG Mix: MediaManager adapter for the music playlist | Замещён и расширен в `DEV` и `parity-ci` (`SharedMediaBGMix.swift`, `SharedMediaPlayer.swift`, `#127`, `#131`). |
| #84 | `feature/ios-yandex-links` | `feature/ios-functional-parity-yandex` | Yandex Music: parse Yandex links the app opens natively | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-3). |
| #85 | `feature/ios-yandex-playback` | `feature/ios-yandex-links` | Yandex Music: shared service and playable file for the player | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-4). |
| #86 | `feature/ios-functional-parity-mihomo-network` | `DEV` | Mihomo: restore the core after a network change | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #87 | `feature/ios-bgwave-stage3-adapters-output` | `feature/ios-functional-parity-music-wave-exports` | feat(bgwave): iOS adapters, listener output and host tap (stage 3) | Весь функционал BG Wave (Stage 1..Facade, включая threading note и UI contract docs) уже в `integration/parity-ci`. |
| #88 | `feature/ios-bgwave-stage4-session` | `feature/ios-bgwave-stage3-adapters-output` | feat(bgwave): listener session facade and failure hint (stage 4) | Весь функционал BG Wave (Stage 1..Facade, включая threading note и UI contract docs) уже в `integration/parity-ci`. |
| #89 | `feature/ios-functional-parity-mihomo-subscription` | `DEV` | Mihomo: send the installation ID and add a manual subscription refresh | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-2). |
| #90 | `feature/ios-functional-parity-mihomo-servers` | `DEV` | Mihomo: keep direct, reject and group entries out of the server list | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-3). |
| #91 | `feature/ios-bgwave-refusal-hint` | `DEV` | feat(bgwave): hint when Local Network may block BG Wave | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #92 | `feature/ios-functional-parity-stealth-upload-date` | `DEV` | Stealth: decide the scheduled send after the media is ready | Уже в `integration/parity-ci` (прямой предок, +0 коммитов). |
| #93 | `feature/ios-yandex-player-source` | `feature/ios-functional-parity-music-mediamanager` | BG Mix: play Yandex tracks through fileURL(for:) | Замещён и расширен в `DEV` и `parity-ci` (`SharedMediaBGMix.swift`, `SharedMediaPlayer.swift`, `#127`, `#131`). |
| #95 | `feature/bg-push-cold-start` | `DEV` | fix(ios): open BG Push links when the app starts from a link | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #96 | `feature/ios-bgmix-pcm-tap` | `DEV` | feat(bgmix): setPcmTap accessor for the BG Wave host tap | `setPcmTap` accessor уже в `integration/parity-ci` (`0576af6c5e`), вместе с актуальным `BGMixPlayer` из `#127`/`#131`. |
| #98 | `feature/ios-functional-parity-music-local-source` | `feature/ios-yandex-player-source` | Play local files from the BG Mix folder in the shared player | Замещён и расширен в `DEV` и `parity-ci` (`SharedMediaBGMix.swift`, `SharedMediaPlayer.swift`, `#127`, `#131`). |
| #99 | `feature/export-zip-container` | `DEV` | feat(ios): ZIP-контейнер для экспорта чата | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-3). |
| #100 | `feature/diagnostics-redaction` | `DEV` | Диагностика: редакция отчёта на устройстве (порт ReportPrivacy) | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #101 | `feature/diagnostics-event-log` | `feature/diagnostics-redaction` | Диагностика: журнал событий и сборка отчёта (поверх #100) | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-2). |
| #102 | `feature/diagnostics-device-info` | `DEV` | Диагностика: номер сборки, версия iOS и модель устройства | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #104 | `feature/regex-parity-fixtures` | `DEV` | Триггер-слова: общие регулярные фикстуры для паритета с Android | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #105 | `feature/regex-re2-bridge` | `feature/regex-parity-fixtures` | Add RE2 bridge for regex trigger words | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-2). |
| #108 | `claude/project-thread-gfrqkw-presence` | `DEV` | Stealth: apply hide-online at once when the setting changes | Уже в `DEV` и `parity-ci` (`d379794daa` + фикс `5873abd961` для `ImplicitStrongCapture` и periodic re-assert offline). |
| #109 | `feature/export-media-archive` | `feature/export-zip-container` | Export media files into the chat export ZIP | Уже в `integration/parity-ci` (`8b2be8b975`). |
| #110 | `feature/ios-yandex-download-validation` | `feature/ios-yandex-playback` | Check downloaded Yandex tracks before they are kept | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-6). |
| #111 | `feature/ios-yandex-player-contract` | `feature/ios-yandex-download-validation` | Add the Yandex track info and the wave queue for the player | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-6). |
| #113 | `claude/project-thread-m2g87b` | `feature/ios-functional-parity-music-local-source` | BG Mix: keep playing past one-item repeats and failed tracks | Замещён и расширен в `DEV` и `parity-ci` (`SharedMediaBGMix.swift`, `SharedMediaPlayer.swift`, `#127`, `#131`). |
| #114 | `feature/parity-doc-update` | `DEV` | docs: аудит паритета после слияний на DEV (ревизия 65b31a610) | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-1). |
| #115 | `claude/project-thread-gfrqkw-stealth-dispatch` | `DEV` | Stealth: set the scheduled date when the request is built | Уже в `integration/parity-ci` (прямой предок, +0 коммитов). |
| #116 | `claude/project-thread-gfrqkw-stealth-reasons` | `DEV` | Stealth: name the reason of each refusal and keep it for the chat | Уже в `integration/parity-ci` (прямой предок, +0 коммитов). |
| #117 | `claude/project-thread-gfrqkw-stealth-threadreads` | `DEV` | Stealth: gate thread and topic reads with hidden read receipts | Уже в `integration/parity-ci` (прямой предок, +0 коммитов). |
| #118 | `feature/ios-bgwave-controller` | `feature/ios-bgwave-stage4-session` | feat(bgwave): portable controller for one wave | Весь функционал BG Wave (Stage 1..Facade, включая threading note и UI contract docs) уже в `integration/parity-ci`. |
| #120 | `codex/119-cache-validation` | `feature/ios-yandex-download-validation` | Invalidate Yandex audio cache after AVFoundation rejects a file | **Интегрирован** (`d88505f486`): `discardUnplayableFile(rowKey:)` + тесты/фикстура. Конфликт в `BGYandexAudioCheckTests.swift` разрешён с сохранением обоих тестов. |
| #121 | `codex/119-playback-failure` | `claude/project-thread-m2g87b` | Retry BG Mix failures without replaying invalid Yandex cache | **Интегрирован** (`4ee068c008`): `BGMixPlaybackRecovery` + вызов `discardUnplayableFile` в `SharedMediaBGMix`. Конфликт в `BUILD` разрешён; сохранена архитектура `#127`/`#131`. |
| #122 | `codex/119-runtime-bridge` | `codex/119-audio-integration` | Share the process-wide Yandex runtime with Music UI | **Интегрирован полностью через #120/#121 + `parity-ci`**: `BGYandexRuntime.shared` уже в `BeyGramYandexMusicController.swift` на `parity-ci`, остальные 2 коммита интегрированы из #120 и #121. |
| #127 | `fix/recovery-1008` | `DEV` | fix(recovery-1008): restore Telegram & Yandex audio, fix My Wave queue and BeyGramRowView switches | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-6). |
| #131 | `fix/music-engine-1009` | `fix/recovery-1008` | fix(music-engine-1009): fix BG Mix audio/UI desync (#128), Lock Screen Now Playing (#129), Back button | Изменения уже присутствуют в `integration/parity-ci` (`git cherry`: +0/-11). |
| #132 | `claude/project-thread-gfrqkw-stealth-delayqueue` | `DEV` | Stealth: model the local delayed send queue | Уже в `integration/parity-ci` (прямой предок, +0 коммитов). |
| #134 | `feature/ios-bgwave-facade` | `feature/ios-bgwave-controller` | feat(bgwave): Objective-C session facade over the controller | Весь функционал BG Wave (Stage 1..Facade, включая threading note и UI contract docs) уже в `integration/parity-ci`. |
