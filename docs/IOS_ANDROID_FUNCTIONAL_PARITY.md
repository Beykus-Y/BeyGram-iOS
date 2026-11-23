# Функциональный паритет BeyGram: iOS и Android

Аудит по коду, а не по README и описаниям Issues. Только чтение: ни одна функция здесь не реализована, и ничто
не компилировалось (в облачной сессии нет macOS, Xcode, Bazel и Swift). Каждое утверждение «работает» ниже
означает «так написано в коде», а не «проверено на устройстве».

## 1. Ревизии

| Что | Ревизия |
| --- | --- |
| iOS, ветка `DEV`, ревизия аудита | `122b02145ec2ac9f0543bf03d80fde201a30f7f6` (слияние PR #62). По ней сделаны вердикты §§2–11 |
| iOS, ветка `DEV`, актуальная | `65b31a610` (merge `integration/ios-functional-parity`: PR #64, #66, #67, #68, #69, #70, #73). Вердикты §§4–8 не пересчитаны, см. §12 |
| Android, ветка `DEV` (`Beykus-Y/BeyGram`) | `5139c0bf` |
| BG-Media, пин в iOS (`submodules/BeyGramMedia/BGMediaCore`) | В ревизии аудита `2368c132` на ветке `main`. На `DEV` сейчас `74d309d9`, тот же пин, что у Android (проверено `git ls-tree origin/DEV`) |
| BG-Media, пин в Android (`third_party/bg-media`) | `74d309d9` на ветке `dev` |
| Музыкальный PR #59 | голова `2176453507208ff3e53c32a02ff3df758023063e`, совпадает со снимком, уже перенесённым в `DEV` через #62. Новых коммитов нет, переносить нечего. Старая ветка не тронута. |

Фактическая находка на ревизии аудита: iOS собирал BG-Media с `main`, а Android с `dev`. Закрыто на `DEV` через PR #66: пин iOS теперь `74d309d9`, как у Android.
`dev` на 29 коммитов впереди `main` (в `main` есть 4 коммита, которых нет в `dev`: промоуты и слияния). Эти 29
коммитов содержат весь BG Wave (`include/bgmedia/wave/`, `src/wave/`, `adapters/wave_opus`, `adapters/wave_webrtc`),
`IPcmOutputTap` и ограничение памяти подготовки треков (`MixPcmBudget`, «bound prepared PCM to two deck slots»,
«cancel preparation cooperatively»). Ни того, ни другого на iOS нет.

## 2. Статусы

| Статус | Значение |
| --- | --- |
| Полностью | Код доходит до пользователя и покрывает то, что делает Android. |
| Частично | Работает, но часть сценариев Android отсутствует. Что именно, написано в строке. |
| Только интерфейс | Экран есть, под ним нет рабочей логики. |
| Только backend | Логика и модели есть, ни один экран и ни один вызов из приложения их не использует. |
| Отсутствует | Нет ни кода, ни заглушки. |
| Ограничена iOS | Объективное ограничение платформы или сборки без платного Apple ID. |

Правило аудита: наличие класса, кнопки или флага `BeyGramFeature` ничего не доказывает. Все флаги выключены по
умолчанию (`BeyGramSettings`, `submodules/BeyGramKit/Sources/BeyGramSettings.swift`).

## 3. Сводная таблица

| № | Функция | Статус на iOS | Приоритет |
| --- | --- | --- | --- |
| 1 | Единая музыкальная подсистема (очередь, состояние, фон) | Отсутствует на ревизии аудита. На `DEV` слиты PR #70 и #73 (по заголовкам), вердикт не пересчитан | P0 |
| 2 | BG Mix: воспроизведение и переходы | Частично (только экран с локальными файлами) | P0 |
| 3 | BG Beat: анализ BPM, beat map, кеш | Только backend внутри `BGMixPlayer`, наружу не выставлен | P0 |
| 4 | Яндекс.Музыка: вход и скачивание трека | Частично, UI только для входа | P0 |
| 5 | Яндекс.Музыка: библиотека, плейлисты, лайки, поиск альбомов и исполнителей, «Моя волна», тексты, обновление токена | Отсутствует | P0 |
| 6 | Формат `.bgmusic` | Только backend (парсер, писатель, тесты) | P1 |
| 7 | Музыка профиля | Telegram-слой есть в апстриме, BeyGram-часть отсутствует | P1 |
| 8 | BG Wave | Только интерфейс (проверка формы ссылки) | P1 |
| 9 | Stealth | Частично | P1 |
| 10 | Mihomo | Частично, ядро работает на устройстве | P2 |
| 11 | Триггер-слова | Частично | P2 |
| 12 | Экспорт чата | Частично | P2 |
| 13 | Диагностика и отчёт о проблеме | Частично | P2 |
| 14 | Проверка обновлений | Частично | P2 |
| 15 | Уведомления (BG Push) | Реализовано для iOS, у Android другой механизм | P2 |
| 16 | Внешний вид BeyGram | Частично | Gemini |
| 17 | BG Motion (маскот), эквалайзер, сон-таймер, кроссфейд без микса, silence trim | Отсутствует | вне ТЗ |

## 4. Музыка

### 4.1. Единая музыкальная подсистема — отсутствует на ревизии аудита (на `DEV` изменилось, см. §12)

**Android.** Один владелец состояния: `playback/PlaybackEngine.kt` (ExoPlayer под `Player`-обёрткой,
`createPlayer`, `playQueue`, `restoreQueue`). Сервис `playback/PlaybackService.kt` (тип `mediaPlayback`, `MediaSessionService`)
переживает экран. Очередь и позиция сохраняются: `playback/MusicSessionStore.kt`, `MusicSessionPersistence.kt`,
`MusicSessionRestorer.kt`. Перемешивание: `PlaybackShuffleOrder.kt`. Ошибки: `PlaybackErrorPolicy.kt`. BG Mix подключён к
движку как драйвер: `BgMixQueueDriver` владеет нативной сессией, движок владеет `PlaybackState`
(`BgMixAwareListener`, `bgMixActive()`).

**iOS.** Подсистемы нет. `BGMixViewController.mm` создаёт собственный `BGMixPlayer` в `init`, держит очередь в
`NSMutableArray *tracks` и вызывает `[self.player invalidate]` в `dealloc`. Закрытие экрана останавливает звук и
стирает очередь (подтверждено кодом). Очередь не сохраняется на диск. Громкость, позиция, длительность и метаданные
наружу не выдаются: публичный `BGMixPlayer.h` содержит 12 методов, из них состояние читает только
`isTransitionActive`.

**Что уже есть в Telegram-iOS и должно быть переиспользовано** (имена прочитаны в коде):

- `AccountContext/Sources/MediaManager.swift`: протокол `MediaManager` (`setPlaylist(_:type:control:)`,
  `playlistControl`, `musicMediaPlayerState`, `globalMediaPlayerState`, `audioSession: ManagedAudioSession`).
- `AccountContext/Sources/SharedMediaPlayer.swift`: протокол `SharedMediaPlaylist` (`state`, `control`, `setOrder`,
  `setLooping`), `SharedMediaPlaylistItem`, `SharedMediaPlayerControlAction` (`next`, `previous`, `playback`,
  `seek`, `setOrder`, `setLooping`, `setBaseRate`), `MediaManagerPlayerType.music`.
- `TelegramUI/Sources/MediaManager.swift`: `MediaManagerImpl` владеет `MPNowPlayingInfoCenter` и
  `MPRemoteCommandCenter` (строки около 278 и 298), экран блокировки и очередь команд уже здесь.
- `TelegramAudio/Sources/ManagedAudioSession.swift`: единая сессия, подписанная на
  `AVAudioSession.interruptionNotification` и `routeChangeNotification`.
- Фоновое аудио: в `Telegram/Telegram-iOS/Info.plist` есть `UIBackgroundModes: audio`.

**Что делает `BGMixPlayer` вместо этого** (чтение `BGMixPlayer.mm`, не проверено на устройстве):

- Сам ставит `AVAudioSession` в `Playback` и активирует (`ensureEngineRunning`), в обход `ManagedAudioSession`.
  Два владельца общей сессии. Прерывания (звонок, Siri), смена маршрута (Bluetooth, отключение наушников)
  не обрабатываются: `engineStarted` не сбрасывается, `AVAudioEngineConfigurationChangeNotification` не слушается.
- `MixSession::update()` вызывается из `CADisplayLink`. Пока приложение в фоне, display link не тикает, поэтому
  завершение подготовки следующего трека и запуск перехода, по чтению кода, не продвигаются при выключенном экране.
  Звук идёт (есть фоновый режим `audio`), но очередь не переключается. Это гипотеза для проверки на устройстве.
- `MPNowPlayingInfoCenter` и `MPRemoteCommandCenter` в модуле не используются, экрана блокировки у BG Mix нет.

### 4.2. BG Mix, BG Beat и ядро BG-Media — частично

Возможности ядра (`MixSession`, `include/bgmedia/mix/MixSession.hpp`, на пине `2368c132`):
`setTransitionType`, `setTransitionDuration`, `setAdaptive`, `setTempoRamp*`, `setTempoCurve`, `setPitchLock`,
`setQuality`, `setMixMode`, `setAggressiveness`, `setBassSwap`, `setPhraseBars`, `setAutoQueue`, `seekDeck`,
`jumpToPlannedTransition`, `cancelTransition`, `refreshPlan`, `snapshot()` (позиция, длительность, BPM, колода-мастер,
прогресс перехода, очередь со статусами, `preparingNext`).

| Возможность ТЗ | Android | iOS |
| --- | --- | --- |
| Анализ BPM, beat map, downbeat, структура | `media/bgbeat/*`, `bgbeat_jni.cpp`, `BgBeatManager`, `BgAnalysisRepository`, секции `BgBeatSection` | Внутри `BGMediaMixPreparation.cpp` (`prepareMixTrack`: `Analyzer`, `AnalysisCache`, `MixFeatureCache`). Результат не выдаётся наружу. Только backend |
| Кеш анализа | `bg_analysis_registry.cpp` | `.bgm` и `.bgf` в `cacheDirectory` экрана (`Documents/bgmix/cache`). Работает по коду |
| Подготовка следующего трека | `MixSession` + бюджет PCM (на `dev`) | `MixSession` (на `main`, без бюджета) |
| Автоподбор перехода, адаптив, Bass Swap | `BgMixSettingsStore`, `BgMixTransition.kt` | `setAdaptiveTransitions:`, `setBassSwap:` в `BGMixPlayer.h`. Тип перехода, tempo ramp, pitch lock, агрессивность, фразы, автоочередь не выставлены |
| Длительность перехода (авто и ручная) | `setTransitionDuration` | `setTransitionDuration:`, 0 = авто. Есть |
| Состояние активного перехода | `BgMixStatus` (`transitionActive`, `transitionProgress`, `transitionType`, `preparingNext`, `lastError`, память) | Только `isTransitionActive` |
| Seek | `BgMixPlayer.seek`, `nativeSeek` | Нет в `BGMixPlayer.h` |
| Источники аудио | Telegram-файлы, Яндекс, `LazyTrackResolver`, `BotTrackResolver` | Только локальные файлы, скопированные в `Documents/bgmix` |
| Метаданные, обложки, позиция | `PlaybackItem`, `ProviderArtwork`, `updateArtwork` | Нет. В очереди хранится только имя файла |

**Риски `BGMixPlayer.mm` и `BGMediaMixPreparation.cpp`, найденные чтением:**

- `decodeWithAVFoundation` читает файл целиком одним `AVAudioPCMBuffer` (`frameCapacity = file.length`) и копирует
  в `out.samples`; потом `PcmTrack::fromAudio` ещё раз копирует и ресемплирует. Для стереотрека 10 минут при
  44,1 кГц одна копия float32 весит около 212 МБ, копий в момент подготовки несколько. Ядро на `dev` ограничивает
  подготовку (`MixPcmBudget`), но iOS его не использует и пин `main` его не содержит.
- Подготовка идёт в рабочем потоке `MixSession` (хорошо), но `AVAudioFile` декодируется без чанков и без отмены.
- Render-блок не захватывает `self`, не аллоцирует и использует заранее выделенный `scratch` (подтверждено кодом).
  Порядок `invalidate` корректен: сессия, затем остановка `AVAudioEngine`, затем `_engine.reset()`.
- Сборка `BeyGramMedia/BUILD` перечисляет исходники ядра явно, список взят с `main`. Любое повышение пина до `dev`
  потребует обновить этот список (добавляются `src/wave/*`, новые файлы mix).

Вывод: на iOS есть рабочее ядро плюс минимальная обвязка, пригодная для демонстрации. До уровня Android не хватает
публичного API состояния, единого владельца, интеграции с `MediaManager` и обновления пина ядра.

### 4.3. Яндекс.Музыка — частично

**Android** (`data/yandex/`, `playback/YandexTrackResolver.kt`, `data/music/provider/*`):
`YandexApi.search` (треки), `likedTrackIds`, `tracksByIds`, `setDisliked`, `playlists`, `likedPlaylists`,
`likedAlbums`, `album`, `playlistTracks`, `lyrics` (LRC, `domain/lyrics/SyncedLyrics.kt`), `audio`;
`YandexAuth.refresh` (grant `refresh_token`); `YandexSessionStore`; «Моя волна»: `YandexWave`, `YandexWaveFeedback`,
`YandexWaveResume`, `YandexWaveRouter`, `YandexWaveSettings`, `YandexMusicProvider.waveStart/waveNext/waveFeedback`;
ключ `ym:` (`YANDEX_TRACK_KEY_PREFIX` в `MusicProvider.kt`).

**iOS** (`submodules/BeyGramYandexMusic/Sources`, 963 строки):

| Что | Состояние |
| --- | --- |
| Device OAuth (`BGYandexDeviceFlow`, `BGYandexAuthFlow`) | Есть. UI: `BeyGramYandexMusicController` (вход, выход) |
| Keychain (`BGYandexTokenStore`) | Есть. Хранится и `refreshToken` |
| Обновление токена | **Нет.** `BGYandexService.validAccessToken()` возвращает nil для истёкшего токена, `refreshToken` не используется. В комментарии: «Refresh ... is not implemented yet». На Android это есть |
| Профиль (`BGYandexAPI.account`) | Есть (uid, имя, Plus). Не показывается на экране |
| Поиск | Только треки (`search`). Исполнители, альбомы отсутствуют. Ни один экран не вызывает `search` |
| Скачивание (`audioLink`, `BGYandexTrackResolver.localFile`) | Есть: подписанная ссылка, MP3 в кеше, повтор. Ничей экран не воспроизводит результат |
| Медиатека, лайки, плейлисты, «Моя волна», тексты | Отсутствуют на ревизии аудита. По сообщению коммита `62a67ed79` на `DEV` подключены профиль, поиск, лайки, плейлисты, «Моя волна», тексты и воспроизведение в BG Mix. Не пересчитано по коду |
| Обработка ошибок (`BGYandexClient.map`) | 401 → `sessionExpired`, 404 → `notFound`, 429 → `rateLimited` (`BGYandexRequestGate`, Retry-After), 403 и 5xx → `unavailable`. Истечение ссылок: повтор в резолвере. Покрывает базовую часть |
| Ключи `ym:` | Парсер ключа есть только в `BeyGramMusicFormat` (`BGMusicTrackKey.yandex`), резолвер принимает голый `trackId` |
| OAuth client id и secret | Читаются из `Info.plist` (`BGYandexClientId`, `BGYandexClientSecret`). В репозитории не найдено ни подстановки этих ключей в сборку (`.github/workflows/build.yml`, `Telegram/`, `build-system/`), ни самих значений. По коду, на CI-сборке `credentials.isConfigured` ложно и источник скрыт. Проверить на устройстве |

Исправление к исходной постановке: «DEV уже содержит API-клиент» верно только для аккаунта, поиска треков и ссылки
на аудио; это около 15% поверхности Android-клиента.

### 4.4. Формат `.bgmusic` — только backend на ревизии аудита (на `DEV` PR #68 добавляет слой импорта и экспорта, см. §12)

**Android:** `data/music/bgmusic/` (`BgMusicReader`, `BgMusicWriter`, `BgMusicExporter`, `BgMusicImportPlanner`,
`BgMusicImportDecision`, `BgMusicLibraryMapping`, `BgMusicSources`, `BgMusicStrictJson`), спецификация
`docs/formats/bgmusic-v1.md`, UI `ui/screens/bgmusic/BgMusicChatCard.kt` и `BgMusicExportSheet.kt`.
В `AndroidManifest.xml` нет `intent-filter` для `.bgmusic`: импорт на Android идёт через карточку в чате и
разбор файла, а не через системное меню. Требование ТЗ «импорт из системного меню "Поделиться"» шире Android.

**iOS:** `submodules/BeyGramMusicFormat` (1766 строк с тестами): `BGMusicArchive.read/write`, `BGMusicInflate`,
`BGMusicManifest.decode/jsonData/normalized`, `BGMusicJSON`, `BGMusicTrackKey`. Лимиты зеркалят Android
(4 МБ, манифест 2 МБ, обложка 1 МБ, до 8 записей, имя до 100 символов, в `BGMusicArchive`). Защита в `BGMusicArchive.read`: дубли записей (`duplicateEntry`), вложенные архивы (`nestedArchiveSignature`), имена с `..` и
каталоги, лимит распаковки (`BGMusicInflate`, тест `testInflateRefusesOutputAboveLimit`). Тесты в коде есть, запускать их не могли.
Пользовательских путей нет: модуль никем не импортируется (`grep BeyGramMusicFormat` вне `submodules/BeyGram*`
ничего не находит); в `Telegram/Telegram-iOS/Info.plist` нет `CFBundleDocumentTypes` и `UTExportedTypeDeclarations`
для `.bgmusic`; нет библиотеки треков, в которую можно импортировать; нет экспорта и нет UI.

### 4.5. Музыка профиля — частично, и не в BeyGram-коде

**Android** (`docs/profile-music.md`): `TdProfiles.kt`, `TdProfileAudios.kt`, `ui/screens/profile/ProfileMusic.kt`,
`ProfileMusicModel.kt`, действие «В профиль» в `MusicPlayerSheet.kt`. В документе Android прямо записано, что
настройка приватности `userPrivacySettingShowProfileAudio` в UI Android не добавлена.

**iOS.** Апстрим Telegram-iOS уже содержит серверный слой: `TelegramCore/Sources/TelegramEngine/Peers/SavedMusic.swift`
(`ProfileSavedMusicContext`, `addMusic`, `removeMusic`, `savedMusicIds`, `keepSavedMusicIdsUpdated`),
`TelegramEnginePeers.swift` (`addSavedMusic`, `removeSavedMusic`), чтение
в `PeerInfoData.swift`, приватность `inputPrivacyKeySavedMusic` в `UpdatedAccountPrivacySettings.swift` и в
`SelectivePrivacySettingsController.swift`. Статус по пунктам ТЗ: чтение списка профиля, добавление и удаление
собственных треков, приватность реализованы апстримом; изменение порядка в `SavedMusic.swift` как отдельного метода
я не нашёл (нужна проверка по `PeerInfo`). Воспроизведение идёт через общий плеер Telegram.
BeyGram-части нет и не нужна для базового сценария. Нужна только интеграция с будущей общей подсистемой
(п. 4.1), чтобы профильные треки играли через тот же владелец состояния.

## 5. BG Wave — только интерфейс

**Android.** `media/bgwave/` (16 файлов): `BgWaveController`, `BgWaveHub`, `BgWaveLink` (`bg://wave/v1/`,
`https://beygram.beykus.fun/#bgwave-v1.`, `MAX_LINK_CHARS = 4096`), `BgWaveSessionNative`, `BgWaveHostTap`,
`BgWaveTapProcessor` (захват PCM хоста), `BgWaveListenerAudio` + `BgWaveListenerService` (слушатель, сервис
`mediaPlayback`), `BgWaveStats`, `BgWaveNetworkWatcher`, `BgWaveStealthConsent`, `BgWaveCard*` (карточка в чате,
`ui/screens/chat/BgWaveCard.kt`), нативный слой `bgwave_session_jni.cpp`, ядро в BG-Media `dev`:
`WaveAudioPipeline`, `WaveJitterBuffer`, `OpusWaveCodec` (libopus), `WebRtcWaveTransport` (libdatachannel,
DTLS-SRTP, STUN, без TURN), `WaveSignaling` (бинарный v1, SDP-подмножество). Fallback через звонок Telegram
(`IExternalCallTransport`) описан в ядре, но в `docs/BG_WAVE.md` назван фазой 2.

**iOS.** `BGWaveViewController.mm`: поле, в которое вставляется ссылка, и `BGWaveLinkLooksValid` проверяет только
префикс и длину (4096). Сессию создать или принять нельзя. Подтверждено кодом и `BeyGramMedia/CLAUDE.md`.

**Что объективно мешает** (не «ограничено iOS» целиком, а набор причин):

1. На ревизии аудита пин BG-Media был на `main` и не содержал ни `wave/`, ни адаптеров. С PR #66 пин на `dev` (`74d309d9`, см. §1). Список исходников в `BeyGramMedia/BUILD` после этого не проверен: нужно выяснить, есть ли в нём `src/wave/*`.
2. `libdatachannel`, `libjuice`, `libsrtp` в `third-party/` отсутствуют. Есть `opus`, `ogg`, `boringssl`, `webrtc`.
   Решение «взять libdatachannel и собрать под iOS через Bazel» или «писать транспорт поверх WebRTC Telegram»
   (`submodules/TgVoipWebrtc`) ещё не принято. Wire-контракт (SDP-подмножество, DTLS fingerprint) совместим с
   обычным WebRTC; транспортная часть выбирается отдельно.
3. Захват PCM хоста: на Android через `IPcmOutputTap` на `MixEngine`. На iOS понадобится тот же тап в
   `BGMixPlayer` render-блоке (realtime-безопасно, без аллокаций). Реализуемо, но требует пина `dev`.
4. Слушатель: `AVAudioEngine` или `AVAudioSourceNode` с jitter buffer из ядра. Фон: `UIBackgroundModes: audio`
   есть; `NWPathMonitor` вместо `BgWaveNetworkWatcher`.
5. Signaling через сообщения Telegram: на Android инвайты видны как карточка в чате
   (`PreparedChatTimeline`, `TdWaveServiceText*`). На iOS нужен хук в рендер сообщений апстрима.

Этап «перенос транспортно-независимого ядра» (п. 1 и 3 из списка) делается без Mac-проверки только до уровня
«компилируется по Bazel-цели»; настоящая проверка требует двух устройств.

## 6. Stealth — частично

**Android** (`StealthSettings` в `data/settings/StealthSettingsStore.kt`): `hideTyping`, `noReadReceipts`,
`noContentOpen`, `hideOnline`, `noStoryViews`, `warnRiskyActions`, `serverScheduledSend`,
`scheduledSendDelaySeconds`, `chats` (режимы по чатам), `failClosed`. Серверная отложенная отправка:
`data/tdlib/TdStealthScheduler.kt` (без молчаливого перехода на обычную отправку; `StealthScheduleUnavailableException`).
Диалоги: `StealthSendGuard` и `StealthScheduleFallback` (предлагает «отправить сейчас»), `StealthRiskGuard`,
`ViewOnceStealthGate`, `StealthSettingsScreen`, `StealthPresets`. Локальная очередь: `data/delayed/DelayedSendQueue.kt`,
`DelayedSendOutbox.kt`, `DelayedSendPolicy.kt` (только простой текст, TTL 24 часа, до 50 сообщений на аккаунт,
статусы `Queued/Dispatching/Failed/Uncertain`, без повторной отправки неопределённого). Ответ из уведомления:
`notifications/StealthReplyPolicy.kt`. Прочитанность историй: `StoryViewerScreen`.

**iOS** (`submodules/BeyGramStealth`, хуки в `TelegramCore`, экран `SettingsUI/.../BeyGramPrivacyController.swift`):

| Сценарий | Статус |
| --- | --- |
| Скрыть статус набора | Есть: `ManagedLocalInputActivities`, `BeyGramStealthHooks.allows(.typing)` |
| Скрыть подтверждения прочтения | Есть: `SynchronizePeerReadState` |
| Скрыть онлайн | Есть: `ManagedAccountPresence` |
| Ключи хранения | Совпадают с Android (`no_read_receipts`, `hide_online`, `hide_typing`, `scheduled_send`, `scheduled_send_delay`, `chats`) |
| Несколько аккаунтов | Настройки по `accountPeerId` (`BeyGramStealthStore`). Логика по аккаунтам подтверждена кодом |
| Серверная отложенная отправка | Есть, включена в `enqueueMessages` (`EnqueueMessage.swift`, вызов `beyGramStealthPreparedMessages` около строки 762) |
| Режимы по чатам | Модель есть (`chatModes`, `BeyGramStealthChatMode`), **ни один экран их не меняет**. Только backend |
| Истории (`noStoryViews`) | Есть: хук в `_internal_markStoryAsSeen`, переключатель в настройках приватности. Сделано 2026-11-23 на `integration/parity-ci`, не собрано |
| `failClosed` при нечитаемом хранилище | Есть: вся защита включена, отправка по расписанию, сбрасывается первой записью. Сделано 2026-11-23 на `integration/parity-ci`, не собрано |
| Не открывать контент (view-once), предупреждение о рискованных действиях | Отсутствуют (нет полей `noContentOpen` и `warnRiskyActions`). Согласие на одноразовые медиа нужно делать в просмотрщике |
| Локальная очередь отложенной отправки | Модель есть (`BeyGramStealthDelayedSend.swift`), не подключена к отправке и к UI |
| Ответ из уведомления (`StealthReplyPolicy` на Android) | Не сравнивалось: на iOS BG Push открывает приложение по `beygram://` |

**Потеря сообщения закрыта PR #64 на `DEV`** (слит 2026-11-20 18:20Z, по описанию PR; код в этой правке не перечитан). Ниже описано состояние на ревизии аудита. **Подтверждённая потеря сообщения.** `BeyGramStealthSettings.sendDecision` возвращает `.refused`, если сообщение
нельзя запланировать (секретный чат, платное сообщение, задержка меньше 15 секунд). `beyGramStealthPreparedMessages`
тогда возвращает `nil`, а `enqueueMessages` отвечает `.single(Array(repeating: nil, count: messages.count))`: сообщение не
создаётся, не отправляется и не ставится в очередь. В пределах этого хука нет ни уведомления пользователя, ни
выбора «изменить способ отправки» или «отправить обычным способом». Как вызывающий код трактует `nil`-идентификаторы
в чате, я не проверял, поэтому нельзя исключить, что какой-то экран что-то покажет, но рассчитывать на это нельзя.
На Android это решено явно: `StealthScheduleFallback.offer` и «fail closed» с подтверждением.

Дополнительно: `sendDecision` проверяет `isSchedulable` только по секретным чатам и `PaidStarsMessageAttribute`.
Вложения, альбомы, голосовые и кружки Android планирует отдельно (сначала загружает файл, затем фиксирует дату,
см. комментарий `TdStealthScheduler.resolve`). На iOS медиа проходит через
`opportunisticallyTransformOutgoingMedia`, а дата фиксируется заранее, поэтому для долгой загрузки возможна
публикация сразу. Это вывод из чтения порядка вызовов, проверить можно только на устройстве.

## 7. Mihomo — частично, ядро работает на устройстве

**Android:** `data/vpn/*` (`VpnBackend`, `MihomoProxyService`, `MihomoCoreBridge`, `SubscriptionClient`,
`MihomoProfileNormalizer`, `TelegramAutoSelector`, `VpnNetworkMonitor`, `MihomoProbeCoordinator`, `ProxyRetry`),
документ `docs/vpn-mihomo.md`. Автоподбор запускается после устойчивого `Connecting` TDLib и смены сети, заголовок
`X-BeyGram-HWID` при загрузке подписки, пробы параллельные с ограничением.

**iOS:** Go-ядро `submodules/BeyGramProxy/core` (mihomo v1.19.32), `MihomoProxyController`, `MihomoCoreClient`,
`SubscriptionFetcher`, `LoopbackCredentials`, `BeyGramMihomoRuntime`, экран `BeyGramMihomoController`.

| Пункт ТЗ | Статус |
| --- | --- |
| Подписки: ввод, загрузка | Есть. Одна подписка, один раз при сохранении. Заголовка HWID нет |
| Обновление конфигурации | Нет периодического или ручного «обновить» без повторного ввода ссылки. Проверить в UI |
| Группы серверов | Одна группа `BeyGram Telegram` |
| Ручной и автоматический выбор | Есть (`selectNode`, `setAutoSelect`) |
| Массовая проверка задержек | Есть (`measureDelays`), последовательно, по 5 с на узел. PR #67 (слит на `DEV`, по заголовку) выносит пробы из блокировки ядра и очереди контроллера; не перечитано |
| Проверка доступности Telegram | Тест задержки узла по `https://web.telegram.org/` (`defaultTestURL` в `bridge.go`). Это же делает Android. Реального состояния соединения Telegram как триггера нет |
| Автовосстановление | Watchdog раз в 20 секунд: проверка узла, выбор самого быстрого, перезапуск ядра при отказе. На Android триггер другой: устойчивое `Connecting` и смена сети |
| Смена Wi-Fi и мобильной сети | Отсутствует (`NWPathMonitor` нигде в модуле не используется) |
| Фон | **Ограничена iOS.** Ядро внутри процесса, без Network Extension. При приостановке процесса loopback-вход останавливается. Описано в `BeyGramProxy/README.md` |
| Trojan всегда с TLS | Известное расхождение с Android (README модуля) |

Не трогать: Go-ядро и мост. Изменения возможны только в Swift-слое (`MihomoProxyController`).

## 8. Остальные функции BeyGram

| Функция | Android | iOS | Статус iOS |
| --- | --- | --- | --- |
| Триггер-слова | `domain/triggers/TriggerWords.kt` (режимы, области, **RE2-регулярка**, `TriggerWordsCodec`), `notifications/TriggerAlerts.kt` | `BeyGramTriggerWords` (матчер `wholeWord`/`anywhere`), `…Telegram` (подписка на сообщения, локальные уведомления), `…UI` (экран) | Частично: нет regex-режима и областей. Регулярка линейного времени на iOS невозможна через `NSRegularExpression` |
| Экспорт чата | `data/export/ChatExportStreamer.kt` (JSON и HTML, ZIP с `media/`, SAF) | `BeyGramChatExport` (writer JSON и HTML), `…Telegram`, `…UI` (выбор папки) | Частично: медиа и ZIP отсутствуют (в `chatExportMessage` берутся только вид медиа) |
| Диагностика, `/report` | `diagnostics/report/*` | `BeyGramDiagnostics`, `BeyGramReportUI` (бот, nonce, Bearer) | Частично: основной поток есть (`BugReportFlow`, `BugReportClient`, nonce как Bearer). Сравнение полноты снимка и редактора приватности с `ReportSnapshot`/`ReportPrivacy` Android не проводилось |
| Проверка обновлений | `data/update/*` | `BeyGramUpdates` (GitHub releases) | Частично. Установка обновления на iOS невозможна без App Store |
| Уведомления | Foreground-сервис TDLib | BG Push (PWA + Web Push, `BeyGramKit/BeyGramPush.swift`, `AppDelegate` ловит `beygram://`) | Другой механизм. Из-за отсутствия платного Apple ID нативный APNs недоступен. Клиентская часть в IPA ещё не проверена |
| Внешний вид | `docs/design-system-v2.md` | `BeyGramAppearance` (стиль `telegram` / `beygram`) | Частично. Принадлежит Gemini |
| BG Motion (маскот) | `media/bgmotion/*` | нет | Отсутствует, вне ТЗ |
| Эквалайзер, сон-таймер, silence trim, кроссфейд без микса | `playback/Equalizer*`, `SilenceAnalyzer`, `sleep timer` | нет в BeyGram-коде | Не сравнивалось с возможностями апстрима |
| Мульти-аккаунт, блокировка по PIN, формы, форумы | своё | апстрим Telegram-iOS | Не сравнивались: реализованы самим Telegram |

## 9. Исправления в исходных оценках

1. Ветка PR #59: новых коммитов нет, переносить нечего.
2. «DEV уже содержит API-клиент Яндекс.Музыки»: только `account`, `search` (треки), `audioLink`. Нет обновления
   токена, медиатеки, плейлистов, лайков, альбомов, исполнителей, текстов песен и «Моей волны». Поэтому цель
   «Реализовать по аналогии с Android» включает ~85% объёма, а не доводку.
3. «Яндекс: подстановка client id и secret»: в сборке не найдена; по коду источник скрыт без них.
4. BG-Media: пин на `main`, у Android на `dev`, разрыв в 29 коммитов. Закрыто на `DEV` через PR #66: пин `74d309d9`, как у Android. Всё, что завязано на «общее ядро», нужно
   сначала выровнять по пину.
5. «Музыка профиля»: основной Telegram-слой уже есть в апстриме iOS. Дублировать в BeyGram не нужно.
6. «Импорт .bgmusic из системного "Поделиться"»: на Android такого пути нет (нет `intent-filter`), импорт идёт из
   чата. Для iOS это новое, а не паритетное требование.
7. Stealth: потеря сообщения подтверждена в `enqueueMessages`. Закрыто PR #64 (слит на `DEV`, по его описанию). Режимы по чатам существуют в модели, но не в UI.
8. Mihomo: смена сети не отслеживается (`NWPathMonitor` не используется), триггера по `Connecting` TDLib нет.
9. BG Mix, поправка 2026-11-23: сеттеры ядра (тип перехода, tempo ramp, pitch lock, агрессивность, фразы, автоочередь, адаптив, Bass Swap) на Android не вызываются. `bgmix_jni.cpp` вызывает только `setPcmTap`, а `BgMixSettingsStore` хранит один переключатель `bgmix_enabled`. Значит, ядро работает со своими умолчаниями на обеих платформах, и это не разрыв паритета. Строки §4.2 про «Seek», «Состояние активного перехода» и «Автоподбор» читать с этой поправкой: `seekToPosition:` в `BGMixPlayer.h` есть, а `BGMixSnapshot` отдаёт `transitionActive`, `transitionProgress`, `preparingNext` и `lastError`.
10. Стелс, 2026-11-23: истории (`noStoryViews`) и `failClosed` сделаны на `integration/parity-ci`, без сборки и без устройства. Осталось: `noContentOpen` с согласием на view-once, `warnRiskyActions`, режимы по чатам в интерфейсе, подключение локальной очереди.

## 10. Рекомендуемый порядок

Зависимости между потоками:

1. **Пин BG-Media до `dev` и обновление `BeyGramMedia/BUILD`** блокирует и BG Wave, и ограничение памяти BG Mix. Пин сделан (PR #66, слит); обновление `BUILD` не проверено.
   Это первое. Без Mac-проверки компиляции безопасно делать только вместе с Gemini.
2. **Музыкальное ядро (п. 4.1–4.2)** блокирует Яндекс (воспроизведение, переходы), `.bgmusic` (библиотека) и
   профильную музыку. Публичный интерфейс, который ждёт Gemini: наблюдаемое состояние (очередь, трек, позиция,
   длительность, BPM, переход) и команды (`play`, `pause`, `next`, `previous`, `seek`, `setOrder`, `setLooping`).
   Предпочтительный путь: `SharedMediaPlaylist` для очереди Telegram и `MediaManager.setPlaylist` с типом `.music`,
   а `BGMixPlayer` как источник PCM внутри; решение и контракт принимает поток музыкального ядра.
3. **Stealth: отказ без потери сообщения** (сделано в PR #64, слит; остаётся UI) независим и мал. Он снимает единственный подтверждённый риск потери
   пользовательских данных. Делается раньше остальных P1.
4. **Яндекс**: обновление токена, затем библиотека и плейлисты, затем «Моя волна», затем тексты. Все модели в
   `BeyGramYandexMusic`, чтобы Gemini получил Swift-API без экранов.
5. **`.bgmusic`**: нужен существующий контейнер библиотеки; без него импорт нечем завершить.
6. **BG Wave**: после пункта 1, выбор транспорта отдельным решением владельца.
7. **Mihomo**: `NWPathMonitor` и обновление подписки, не трогая Go-ядро.

## 10.1. Что требует Mac и устройства

Проверка на симуляторе или iPhone нужна для: фонового продвижения очереди BG Mix, прерываний аудио, расхода памяти
на длинных треках, того, что экран делает с `nil` из `enqueueMessages`, публикации медиа при stealth, подстановки
ключей Яндекса в сборке. Пока этого нет, соответствующие пункты в документе остаются гипотезами из чтения кода.

## 11. Что в аудит не вошло

- Каждый экран Android по отдельности и локализация (Gemini).
- Поведение апстрима Telegram-iOS без правок BeyGram.
- Юридическая сторона лицензий (в `BeyGramProxy/README.md` она оставлена владельцу).

## 12. Что изменилось на DEV после ревизии аудита

Проверено 2026-11-20 по GitHub (состояние и время слияния PR) и по истории `origin/DEV`. Код по слияниям в этой правке не перечитан, поэтому вердикты §§4–8 остаются от ревизии аудита, пока их не пересчитают по коду. Заголовки PR и сообщения коммитов ниже — слова авторов, а не проверка поведения.

**Слитые PR (GitHub, UTC):**

- #64 «Stealth: keep refused sends as failed messages», 18:20:12. Относится к §6, §9 п. 7, §10 п. 3.
- #66 «BG Mix: pin BG-Media dev, bound track PCM», 18:20:12. Относится к §1, §4.2 (бюджет PCM), §5 п. 1, §10 п. 1.
- #67 «Mihomo: run delay probes off the core lock and off the controller queue», 18:20:12. Относится к §7 (задержки).
- #68 «BeyGramMusicFormat: align .bgmusic reader, add import and export layer», 18:20:12. Относится к §4.4.
- #70 «BG Mix: public player API with state snapshot and observers», 18:20:14. Относится к §4.2 (публичный API состояния).
- #73 «BG Mix: shared player, interruptions and background driver», 18:20:15. Относится к §4.1 и §4.2.

**Слияние в DEV без закрытия PR на GitHub:** #69 «Yandex Music: service layer for Android parity» есть в истории DEV (merge `3ba4f7e59`). При проверке PR был открыт. Относится к §4.3.

**Коммиты без PR в заголовке:** `62a67ed79` «feat(yandex-music): connect live BGYandexService profile, search, likes, playlists, My Wave, lyrics, and BG Mix playback». По сообщению коммита таблица §4.3 о медиатеке, лайках, плейлистах, «Моей волне» и текстах устарела. Пересчитать по коду. В сообщении merge упомянуты «updates fix» и «Yandex OAuth»: коммиты в этой правке не разобраны.

**Закрыто без слияния:** #78 «Yandex: refresh the access token with the refresh token». Вердикт §4.3 «обновление токена: нет» для `DEV` остаётся верным, пока не слит другой PR.

**Открытые PR при проверке (по заголовкам):**

- Музыка и Яндекс: #59 (черновик, настройки BG Music, `.bgmusic`, чистая логика Яндекса), #79 (библиотека, локальные плейлисты, импорт и экспорт `.bgmusic`), #81 (адаптер MediaManager для плейлиста BG Mix), #84 (разбор ссылок Яндекса), #85 (общий сервис Яндекса, воспроизводимый файл), #93 (треки Яндекса через `fileURL(for:)`), #98 (локальные файлы папки BG Mix в общем плеере), #110 (проверка скачанных треков Яндекса).
- BG Wave: #65 (черновик, транспортно-независимое ядро, libdatachannel), #75 (исходники адаптера для BGWaveCore), #77 (NSLocalNetworkUsageDescription, RU/EN), #87 и #88 (адаптеры и фасад сессии), #91 (подсказка при блокировке локальной сети), #96 (`setPcmTap` для тапа хоста). Закрыты без слияния: #76, #80, #82 (по заголовкам повторяют #77).
- Mihomo: #86 (восстановление ядра после смены сети), #89 (ID установки и ручное обновление подписки), #90 (прямые, отклонённые и групповые записи вне списка серверов).
- Стелс (ведёт другой тред): #92 (дата отложенной отправки после готовности медиа), #108 (скрытый онлайн сразу при смене настройки).
- Экспорт, триггеры, диагностика: #99 (ZIP-контейнер), #109 (медиа в ZIP поверх #99), #104 и #105 (фикстуры триггеров и RE2), #100–#102 (диагностика).
- BG Push: #95 (открытие ссылок при холодном старте).

## 13. Находки по сборке 1005

Раздел не заполнен. В репозиториях BeyGram-iOS и BeyGram поиск по «build 1005» и «сборка 1005» не дал ни одного совпадения, а в данных этой задачи находок по сборке 1005 нет. Чтобы не выдумывать, оставлено пустым. Для заполнения нужны номер сборки и платформа (iOS или Android), что проверяли и где найдена проблема: экран, лог, шаги воспроизведения.
