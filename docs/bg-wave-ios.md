# BG Wave на iOS: этапы, что проверено, задания

Дата: 2026-11-20. Ветка: `feature/ios-functional-parity-wave` (от `origin/DEV`). Аудит, на который опирается план:
`docs/IOS_ANDROID_FUNCTIONAL_PARITY.md` (draft PR #63), раздел 5 и порядок в разделе 10.

## 1. Что проверено и чем

Пометки: **написано** (код в репозитории), **статически** (прочитано и сверено с ядром и Android), **скомпилировано**
(компилятор, без Bazel и без iOS), **прогон** (тесты выполнены), **устройство** (не делалось).

| Часть | Написано | Статически | Скомпилировано | Прогон | Устройство |
|---|---|---|---|---|---|
| `BGWaveCore/BGWaveInvite` (ссылки `bg://wave/v1/` и https, лимит 4096, TTL и сдвиг часов) | да | да | Linux, g++ 13.3, `-Werror` | 4 золотых инвайта в обеих формах и отказы: прошли | нет |
| `BGWaveCore/BGWaveSession` (Host и Listener поверх `WaveAudioPipeline`) | да | да | Linux, g++ 13.3, `-Werror` | Offer, Answer, PCM, Live, End и повтор End: прошли | нет |
| BG-Media wave core на dev `74d309d` (тот же коммит, что `BGMEDIA_PINNED_COMMIT` в Android) | нет (чужой код) | да | Linux, CMake core-only | `wave.*`: 20 из 20 прошли | нет |
| Bazel-цели `BGWaveCore` и `BGWaveCoreTests` | да | да | **нет** (на Linux нет Bazel и Xcode) | **нет** | нет |
| Opus-адаптер для iOS | нет | нет | нет | нет | нет |
| P2P-транспорт (WebRTC) на iOS | нет | нет | нет | нет | нет |
| Вывод слушателя и тап хоста на AVAudioEngine | нет | нет | нет | нет | нет |
| Telegram: карточка приглашения, отправка и приём через TDLib | нет | нет | нет | нет | нет |

Золотые инвайты взяты из `BG-Media/tests/fixtures/wave_v1` (их создаёт канонический кодек ядра, Android читает те же
байты). Значения ожидаются по `tests/fixtures/wave_v1/README.md`. Контрольная порча: при сдвиге часов в тесте
появляются 33 провала и код выхода 1, значит проверки работают.

**Честно о проверке:** на iOS ничего не компилировалось. Bazel-цели не проверены, и сессия не запускалась на
устройствах. Проверка «на Linux» относится только к переносимому C++.

## 2. Зависимости

1. **Пин BG-Media и список исходников** (поток «Единое музыкальное ядро и BG Media», ветка `claude/project-thread-hij0di`):
   пин `BGMediaCore` на `dev` `74d309d`, семь файлов `src/wave/*` в `srcs` цели `BGMediaCore`, и
   `visibility = ["//submodules/BeyGramMedia:__subpackages__"]` вместо `//visibility:private`. Без этого цели
   `BGWaveCore` не линкуются. Этот PR пин не трогает.
2. **Транспорт** (решение владельца, раздел 4).
3. **Захват PCM хоста**: тап `IPcmOutputTap` в render-блоке `BGMixPlayer`. Это тоже работа потока музыкального ядра.

## 3. Этапы

### Этап 0. Пин и исходники ядра
Владелец: поток музыкального ядра. Пин на `dev` тянет 29 коммитов (в том числе BG Mix: `MixPcmBudget`, `checkpoint`).
Параметры новых методов имеют значения по умолчанию, поэтому существующие вызовы в `BGMixPlayer.mm` должны компилироваться.
Это проверяет Gemini на Mac.

### Этап 1. Транспортно-независимое ядро (этот PR)
- `BGWaveCore/BGWaveInvite`: декодирование и кодирование инвайтов в обеих формах. Ссылка длиннее 4096 символов
  отбрасывается до декодирования. Нулевое или отрицательное время означает часы (сбой нельзя обойти передачей `0`).
  Ошибки возвращаются короткими фиксированными кодами, без содержимого полезной нагрузки.
- `BGWaveCore/BGWaveSession`: Host или Listener поверх `bgmedia::wave::WaveAudioPipeline`. Кодек и транспорт
  передаются снаружи. Исходящие инвайты (https-форма, как Android после `BgWaveLink.toHttps`) выдаются через
  `pollOutboundInvite()`. Входящие разбираются в `acceptInvite()`: Offer и Answer, а Cancel и End завершают сессию.
  Есть `startOffer`, `reconnect`, `stop(emitEnd)`, `process`, `pushHostPcm`, `pullListenerPcm`, `state`, `route`,
  `stats`, `diagnosticsSummary`, `lastError`.
- Тесты `BGWaveCore/Tests/BGWaveCoreTests.cpp`: золотые инвайты, отказы (истёк срок, сдвиг часов, пустая ссылка,
  чужая схема, плохой base64url, слишком длинная ссылка), полный обмен Offer → Answer → Live → End с повтором и
  проверкой, что слушатель без сессии отклоняет чужой инвайт.
- Файлы: `BGWaveCore/BUILD` (`cc_library` и `cc_test`, зависимость `//submodules/BeyGramMedia:BGMediaCore`),
  раздел в `submodules/BeyGramMedia/CLAUDE.md`. `BGWaveViewController.mm`, `PublicHeaders` и `BUILD` самой
  `BeyGramMedia` не трогаем.

### Этап 2. Opus и аудио на iOS (нужен Mac)
- Opus: `adapters/wave_opus/src/OpusWaveCodec.cpp` под iOS-цель поверх `//third-party/opus:opus` (в репозитории
  libopus 1.5.1, публичная видимость). Адаптер написан под libopus 1.5.2, нужна проверка API. Профиль: 48 кГц,
  стерео, 20 мс, 128 кбит/с (диапазон 48–160), in-band FEC, PLC.
- Слушатель: `AVAudioEngine` с `AVAudioSourceNode`. Render-блок не захватывает `self`, ничего не выделяет и
  вызывает `pullListenerPcm`.
- Хост: `IPcmOutputTap` в render-блоке `BGMixPlayer` вызывает `onPcmRendered` (realtime-безопасно).
- Проверка: round-trip Opus-кодека на macOS (тест), прогон `BGWaveCoreTests`, сборка. Устройство пока не нужно.

### Этап 3. Транспорт (решение владельца)
Варианты перечислены в разделе 4. Сама реализация после решения: адаптер `WebRtcWaveTransport` под выбранный стек,
ICE через STUN без TURN. При `P2PFailed` нужна фаза 2 (звонок Telegram, `IExternalCallTransport`), это отдельное решение.
Проверка: два устройства, Android ↔ iOS, в обе стороны. Одного симулятора мало.

### Этап 4. Telegram и интерфейс (Gemini)
- Отправка инвайтов через TDLib как скрытая ссылка (`text-url`). Отправка под режимом stealth требует
  `sendNowConsent`, это согласуется с потоком Stealth.
- Приём: хук в рендер сообщений апстрима, карточка приглашения в чате (аналог Android `BgWaveCard`).
- `BGWaveViewController`: заменить тело `BGWaveLinkLooksValid` на `beygram::wave::decodeInvite` и показывать кнопки
  «Присоединиться» и «Отмена». Сам файл не переписываем, меняется одна функция.
- Фон: `UIBackgroundModes: audio` уже есть. Вместо `BgWaveNetworkWatcher` использовать `NWPathMonitor`.

## 4. Решение о транспорте (ждёт владельца)

Аудит (раздел 5 и пункт 6 раздела 10 parity-документа): транспорт «выбирается отдельно», это решение владельца. Варианты:

- **A. libdatachannel на iOS** (рекомендую). Тот же стек, что на Android: `WebRtcWaveTransport` использует
  `rtc::OpusRtpPacketizer`, RTCP и libjuice. Нужны новые сборки libdatachannel, libjuice, libsrtp и OpenSSL или
  BoringSSL в `third-party`. Аргумент: ТЗ запрещает менять архитектуру BG Wave, а здесь она сохраняется полностью.
- **B. WebRTC Telegram** (`third-party/webrtc`, `TgVoipWebrtc`). Меньше новых библиотек, но медиа пойдёт через
  libwebrtc, а не через jitter buffer и пакетизатор ядра. Это уже другая архитектура, и доступ к сырым RTP в
  публичном API не проверен.
- **C. Отложить P2P.** Делаем этапы 2 и 4 (Opus, аудио, инвайты, UI), P2P позже.

## 5. Задания для Gemini (Mac)

1. Дождаться PR потока музыкального ядра и подтянуть `feature/ios-functional-parity-wave`
   (или `DEV`, когда тот PR в него вольётся).
2. Прогон host-теста. Ожидаемо: строка `BGWaveCoreTests: all checks passed` и код выхода 0.
   ```
   ./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMedia/BGWaveCore:BGWaveCoreTests --test_output=all
   ```
   Если падает, приложить лог целиком, а не пересказ.
3. Полная сборка по CLAUDE.md (`Make.py … build`, цель `Telegram/Telegram`). `BGWaveCore` пока не подключён к приложению,
   поэтому сборка не скомпилирует его. Смысл проверки: пин BG-Media на `dev` и новые `src/wave/*` не ломают
   `BGMixPlayer.mm` и `BGMediaMixPreparation.cpp`.
4. Только после этапа 2: round-trip Opus на macOS.
5. Не заявлять компиляцию или работу на iOS без лога этой команды. До прогона отмечать статус как «не проверено».

## 6. Ограничения и риски

- **Протокол v1 не заморожен.** В README фикстур сказано, что окончательная заморозка требует проверки реальным SDP
  и круга Telegram `text-url`. До заморозки формат инвайтов нельзя менять без согласования с Android.
- **Размер ссылки.** Инвайт с тремя кандидатами, как в Offer из фикстуры, занимает 302 символа в https-форме. Потолок
  ядра: 2048 байт полезной нагрузки, около 2,8 тыс. символов base64. Это ниже лимита 4096.
- **Исправления ядра.** Ветки `fix/wave-*` аудита уже в `dev`: `fix/wave-jitter-and-pipeline-audio`,
  `fix/wave-signaling-and-security`, `fix/wave-webrtc-and-opus`, `fix/wave-cmake-and-docs`. Это проверено по графу коммитов.
  Тесты ядра на Linux прошли, но транспорт на iOS не проверен.
- **Лимит NAT.** TURN нет. Симметричный NAT и CGNAT дают `P2PFailed`, поэтому фаза 2 остаётся нужной.
- **Не делать:** не переписывать `BGWaveViewController.mm` целиком; не править пин и `BUILD` `BeyGramMedia` из этого PR;
  не писать в `BGMediaCore` из iOS-репозитория (это только чтение, см. `submodules/BeyGramMedia/CLAUDE.md`).
