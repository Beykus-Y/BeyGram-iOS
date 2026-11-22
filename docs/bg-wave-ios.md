# BG Wave на iOS: этапы, что проверено, задания

Дата: 2026-11-20. Ветка: `feature/ios-functional-parity-wave` (от `origin/DEV`), PR #65 (draft). Аудит, на который опирается план:
`docs/IOS_ANDROID_FUNCTIONAL_PARITY.md` (draft PR #63), раздел 5 и порядок в разделе 10.

## 1. Что проверено и чем

Пометки: **написано** (код в репозитории), **статически** (прочитано и сверено с ядром и Android, либо проверено скриптом
по исходникам), **собрано** (компилятор или линковщик, без Bazel и без iOS), **прогон** (тесты выполнены),
**устройство** (не делалось).

| Часть | Написано | Статически | Собрано | Прогон | Устройство |
|---|---|---|---|---|---|
| `BGWaveCore/BGWaveInvite` (ссылки `bg://wave/v1/` и https, лимит 4096, TTL и сдвиг часов) | да | да | Linux, g++ 13.3, `-Werror` | 4 золотых инвайта в обеих формах и отказы: прошли | нет |
| `BGWaveCore/BGWaveSession` (Host и Listener поверх `WaveAudioPipeline`) | да | да | Linux, g++ 13.3, `-Werror` | Offer, Answer, PCM, Live, End и повтор End: прошли | нет |
| BG-Media wave core на dev `74d309d` (тот же коммит, что `BGMEDIA_PINNED_COMMIT` в Android) | нет (чужой код) | да | Linux, CMake | `wave.*`: 20 из 20 | нет |
| libdatachannel 0.22.5 с libjuice, usrsctp, plog в `third-party/libdatachannel` | да | да | синтаксис: 58 файлов C++ и 20 файлов libjuice с флагами `BUILD`, 23 файла usrsctp с Linux-флагами (Darwin-флаги проверяются только на Mac) | таблица ниже | нет |
| Bazel-цели `BGWaveCore`, `BGWaveCoreTests`, `libdatachannel` | да | да | **нет** (на Linux нет Bazel и Xcode) | **нет** | нет |
| Opus-адаптер для iOS | нет | нет | нет | нет | нет |
| Вывод слушателя и тап хоста на AVAudioEngine | нет | нет | нет | нет | нет |
| Telegram: карточка приглашения, отправка и приём через TDLib | нет | нет | нет | нет | нет |

Прогоны транспорта на Linux (g++ 13.3, Debug, BG-Media dev `74d309d`, libdatachannel из `third-party/libdatachannel`):

| Конфигурация | `wave.` | `wave_real.` |
|---|---|---|
| OpenSSL 3.0.13 (системный), libsrtp внутри libdatachannel | 20 из 20 | 9 из 9 |
| BoringSSL из `third-party/boringssl`, libsrtp внутри libdatachannel | 20 из 20 | 9 из 9 |
| BoringSSL, переименование `rtc` → `bgrtc`, libsrtp внутри libdatachannel | 20 из 20 | 9 из 9 |
| BoringSSL, `bgrtc`, libsrtp из WebRTC (`third-party/webrtc/libsrtp`), **выбрана для iOS** | 20 из 20 | 9 из 9 |

`wave_real` включает in-process P2P: DTLS-SRTP с Opus и проверку подмены отпечатка. Прогоны на BoringSSL проверяют
DTLS-путь libdatachannel на Linux. На iOS этот путь не проверен.

Что это доказывает и что нет: это переносимый C++ и сам транспорт (libdatachannel, ICE, DTLS-SRTP, Opus RTP) на Linux.
Это не доказывает работу с iOS-компилятором и линковщиком, в Bazel-правилах и на устройстве. Для BoringSSL и libsrtp из
репозитория на Linux понадобились вспомогательные файлы вне репозитория: заголовок с версией OpenSSL, которого нет в
дереве BoringSSL (CMake читает версию из `opensslv.h`), и сборка 17 файлов libsrtp из WebRTC с определениями из
`libsrtp_config`. В репозиторий они не попали.

Золотые инвайты взяты из `BG-Media/tests/fixtures/wave_v1` (их создаёт канонический кодек ядра, Android читает те же
байты). Значения ожидаются по `tests/fixtures/wave_v1/README.md`. Контрольная порча: при сдвиге часов в тесте появляются
33 провала и код выхода 1, значит проверки работают.

**Честно о проверке:** на iOS ничего не компилировалось. Bazel-цели не проверены, и сессия не запускалась на устройствах.
Linux-результаты относятся только к переносимому C++ и транспорту на Linux.

## 2. Зависимости

1. **Пин BG-Media и список исходников.** Поток «Единое музыкальное ядро и BG Media»: PR #66 (ветка
   `claude/project-thread-hij0di`, в DEV, не слит). Пин `BGMediaCore` на `dev` `74d309d`, семь файлов `src/wave/*` в `srcs`
   цели `BGMediaCore`, `visibility = ["//submodules/BeyGramMedia:__subpackages__"]`. До его слияния цели `BGWaveCore` не
   линкуются. Этот PR пин и `BUILD` самой `BeyGramMedia` не трогает.
2. **Транспорт (решение владельца, раздел 4).** Вендоринг `third-party/libdatachannel` (этот PR), BoringSSL
   `//third-party/boringssl:ssl` и `:crypto`, libsrtp WebRTC `//third-party/webrtc/libsrtp:srtp_public` (новая цель
   в этом PR, в `BUILD` WebRTC), libopus `//third-party/opus:opus`. Каждая библиотека в приложении одна.
3. **Адаптер транспорта** `adapters/wave_webrtc/src/WebRtcWaveTransport.cpp` лежит в сабмодуле BG-Media. Bazel-цель, которая
   его компилирует, может ссылаться на его файлы, только если пакет их экспортирует. Экспорт делает
   `submodules/BeyGramMedia/BUILD`, это файл потока музыкального ядра. Нужен запрос ему: filegroup или `exports_files`
   для `BGMediaCore/adapters/wave_webrtc/**` и `adapters/wave_opus/**`, видимость `//submodules/BeyGramMedia:__subpackages__`.
4. **Захват PCM хоста**: тап `IPcmOutputTap` в render-блоке `BGMixPlayer`. Это работа потока музыкального ядра.

## 3. Этапы

### Этап 0. Пин и исходники ядра
Владелец: поток музыкального ядра. Пин на `dev` тянет 29 коммитов (в том числе BG Mix: `MixPcmBudget`, `checkpoint`).
Параметры новых методов имеют значения по умолчанию, поэтому существующие вызовы в `BGMixPlayer.mm` должны компилироваться.
Это проверяет Gemini на Mac.

### Этап 1. Транспортно-независимое ядро (PR #65)
- `BGWaveCore/BGWaveInvite`: декодирование и кодирование инвайтов в обеих формах. Ссылка длиннее 4096 символов отбрасывается
  до декодирования. Нулевое или отрицательное время означает часы (сбой нельзя обойти передачей `0`). Ошибки возвращаются
  короткими фиксированными кодами, без содержимого полезной нагрузки.
- `BGWaveCore/BGWaveSession`: Host или Listener поверх `bgmedia::wave::WaveAudioPipeline`. Кодек и транспорт передаются
  снаружи. Исходящие инвайты (https-форма, как Android после `BgWaveLink.toHttps`) выдаются через `pollOutboundInvite()`.
  Входящие разбираются в `acceptInvite()`: Offer и Answer, а Cancel и End завершают сессию. Есть `startOffer`, `reconnect`,
  `stop(emitEnd)`, `process`, `pushHostPcm`, `pullListenerPcm`, `state`, `route`, `stats`, `diagnosticsSummary`, `lastError`.
- Тесты `BGWaveCore/Tests/BGWaveCoreTests.cpp`: золотые инвайты, отказы (истёк срок, сдвиг часов, пустая ссылка, чужая схема,
  плохой base64url, слишком длинная ссылка), полный обмен Offer → Answer → Live → End с повтором и проверкой, что слушатель
  без сессии отклоняет чужой инвайт.
- Файлы: `BGWaveCore/BUILD` (`cc_library` и `cc_test`), раздел в `submodules/BeyGramMedia/CLAUDE.md`.
  `BGWaveViewController.mm`, `PublicHeaders` и `BUILD` самой `BeyGramMedia` не трогаем.

### Этап 1b. Транспорт: сборка подготовлена (этот PR)
- `third-party/libdatachannel/`: libdatachannel v0.22.5, libjuice v1.5.9, usrsctp `ebb18ad`, plog `e21baec`. Исходники
  совпадают с коммитами, которые берёт Android через BG-Media (`third-party/libdatachannel/README.md`: пины, лицензии,
  правила). Файлы не изменены.
- `third-party/libdatachannel/BUILD`: цели `plog`, `libjuice`, `usrsctp`, `libdatachannel`, нативные `cc_library` без CMake.
  Списки исходников взяты из графа сборки Linux (`ninja -t commands`): 101 файл, все существуют.
- `third-party/webrtc/libsrtp/BUILD`: новая цель `srtp_public` (только заголовок и зависимость от `:libsrtp`). Одна копия
  libsrtp на бинарник.
- Проверено статически и на Linux: синтаксис файлов с флагами `BUILD` (см. таблицу в разделе 1); сборка и прогоны из таблицы
  выше; переименование пространства `rtc` в `bgrtc` (в тестовом бинарнике на Linux 12025 символов `bgrtc::` и ни одного `rtc::`).
- Не проверено: Bazel-сборка этих целей, сборка для iOS (компилятор и линковщик), работа в приложении.

### Этап 2. Opus и аудио на iOS (нужен Mac)
- Opus: `adapters/wave_opus/src/OpusWaveCodec.cpp` под iOS-цель поверх `//third-party/opus:opus` (в репозитории libopus 1.5.1,
  публичная видимость). Адаптер написан под libopus 1.5.2, нужна проверка API. Профиль: 48 кГц, стерео, 20 мс, 128 кбит/с
  (диапазон 48–160), in-band FEC, PLC.
- Слушатель: `AVAudioEngine` с `AVAudioSourceNode`. Render-блок не захватывает `self`, ничего не выделяет и вызывает
  `pullListenerPcm`.
- Хост: `IPcmOutputTap` в render-блоке `BGMixPlayer` вызывает `onPcmRendered` (realtime-безопасно).
- Проверка: round-trip Opus-кодека на macOS (тест), прогон `BGWaveCoreTests`, сборка. Устройство пока не нужно.

### Этап 3. Транспорт в приложении
Стек выбран (раздел 4). Осталось:
- Bazel-цель адаптера `WebRtcWaveTransport` из BG-Media (нужен экспорт из `submodules/BeyGramMedia/BUILD`, пункт 2.3) и
  зависимость от `//third-party/libdatachannel:libdatachannel`. Адаптер использует `rtc::` 57 раз, поэтому получает
  `-Drtc=bgrtc` через `defines`.
- ICE через STUN без TURN. При `P2PFailed` нужна фаза 2 (звонок Telegram, `IExternalCallTransport`), это отдельное решение.
- Проверка: два устройства, Android ↔ iOS, в обе стороны (сценарий в разделе 6). Одного симулятора мало.

### Этап 4. Telegram и интерфейс (Gemini)
- Отправка инвайтов через TDLib как скрытая ссылка (`text-url`). Отправка под режимом stealth требует `sendNowConsent`, это
  согласуется с потоком Stealth.
- Приём: хук в рендер сообщений апстрима, карточка приглашения в чате (аналог Android `BgWaveCard`).
- `BGWaveViewController`: заменить тело `BGWaveLinkLooksValid` на `beygram::wave::decodeInvite` и показывать кнопки
  «Присоединиться» и «Отмена». Сам файл не переписываем, меняется одна функция.
- Фон: `UIBackgroundModes: audio` уже есть. Вместо `BgWaveNetworkWatcher` использовать `NWPathMonitor`.

### Контроллер и фасад (поверх этапа 4)
- `BGWaveController` (`BGWaveCore/BGWaveController.*`, PR #118): порт `BgWaveController` из Android на C++. Одна волна
  за раз, таблица приглашений, защита от повтора, лимит приглашений на собеседника. Проверено на Linux:
  `BGWaveControllerTests`.
- `BGWaveSessionController` (`BGWaveListener/`, ветка `feature/ios-bgwave-facade`): Objective-C фасад для экрана и
  карточки. Контракт для UI: `docs/bg-wave-ui-contract.md`. Расхождения с Android и открытые решения:
  `docs/bg-wave-android-compat.md`.
- Не проверено: сборка на macOS и Bazel-тесты обоих слоёв. Mac и Gemini не ждём. Сборку и тесты проверит один большой прогон GitHub CI
  из интеграционной ветки, которую ведёт поток невидимки. Feature-ветки и PR CI не запускают (`.github/workflows/build.yml`).

## 4. Решение о транспорте (принято 2026-11-20)

Владелец выбрал вариант A: **libdatachannel, как на Android**. Архитектура BG Wave сохраняется полностью: ядро BG-Media с
jitter buffer, Opus-пакетизация, RTP/RTCP, сигналинг и формат инвайтов совпадают с Android.

Отклонён вариант B, WebRTC Telegram: медиа пошло бы через libwebrtc, а не через jitter buffer и пакетизатор ядра, то есть
это другая архитектура. Вариант C (отложить P2P) не выбран. Он остаётся запасным, если проверка на устройствах не поднимет P2P.
Решение об этом принимает владелец.

Как собрано (подробно в `third-party/libdatachannel/README.md`):
- **libsrtp.** Одна копия, WebRTC's (`//third-party/webrtc/libsrtp`). Собственная копия libdatachannel не используется: обе
  определяют `srtp_*` в одном бинарнике.
- **OpenSSL → BoringSSL.** libdatachannel использует OpenSSL через несколько функций. Все идентификаторы, которые он
  использует, проверены по заголовкам BoringSSL из репозитория. Ветки OpenSSL 3 не компилируются (BoringSSL сообщает
  `OPENSSL_VERSION_NUMBER 0x1010107f`). TDLib в этом репозитории уже собирается с BoringSSL вместо OpenSSL.
- **Пространство имён `rtc`.** libdatachannel и libwebrtc оба используют `rtc::`. Одинаковые mangled-имена с разной раскладкой
  могут дать тихую ODR-ошибку при линковке. Поэтому библиотека собирается с `-Drtc=bgrtc`, и потребители получают тот же define
  через `defines`. Проверено на Linux: в тестовом бинарнике нет `rtc::`.
- **Opus.** `//third-party/opus:opus`, та же libopus, которая уже нужна целям WebRTC.
- **usrsctp, libjuice, plog.** В Bazel-сборке WebRTC их нет (WebRTC использует dcsctp), поэтому конфликта нет. libjuice
  хэширует сам (`USE_NETTLE=0`), TLS-библиотека ему не нужна.

Правила приложения, которые следуют из общего libsrtp:
- **Не вызывать `rtc::Cleanup()`.** Он доходит до `DtlsSrtpTransport::Cleanup()`, то есть до `srtp_shutdown()` общей libsrtp,
  и ломает звонки WebRTC в этом же процессе. `rtc::Preload()` безопасен.
- **`srtp_init()` может вызываться дважды.** Повторный вызов в libsrtp WebRTC возвращает статус самотеста
  (`crypto/kernel/crypto_kernel.c`), это не ошибка.

## 5. Задания для Gemini (Mac)

Задачи заведены как issues в `Beykus-Y/BeyGram-iOS`. В репозитории не настроено, как Gemini на Mac подхватывает issues, это
нужно подтвердить Beykus.

- **[#71](https://github.com/Beykus-Y/BeyGram-iOS/issues/71). Сборка libdatachannel на macOS.** Цель
  `//third-party/libdatachannel:libdatachannel` для устройства и симулятора, проверка символов `nm`, host-тест
  `BGWaveCoreTests` после слияния #66.
- **[#72](https://github.com/Beykus-Y/BeyGram-iOS/issues/72). Сценарий Android ↔ iOS.** Запуск возможен после этапов 2–4.
  Раздел 6 описывает то же самое.

Общие правила для всех заданий:
1. Не заявлять компиляцию или работу на iOS без лога команды. До прогона статус «не проверено».
2. Пин BG-Media и `submodules/BeyGramMedia/BUILD` не менять (поток музыкального ядра).
3. Полная сборка приложения (`Make.py … build`, цель `Telegram/Telegram`) пока не включает `BGWaveCore` и libdatachannel:
   от них ничего в приложении не зависит. Поэтому сборка приложения ничего не скажет о транспорте. Её нужно делать после этапа 3.

Host-тест (после #66):
```
./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMedia/BGWaveCore:BGWaveCoreTests --test_output=all
```
Ожидается: `BGWaveCoreTests: all checks passed`, код выхода 0. Если падает, приложить лог целиком.

## 6. Проверка совместного прослушивания Android ↔ iOS (сценарий)

Статус: **записан, не запускался.** Результатов нет. Запуск невозможен до этапов 2–4: в приложении ещё нет захвата хоста
на iOS, адаптера транспорта и экрана приглашения.

Предусловия:
- Android: сборка BeyGram с BG-Media на пине `74d309d` (`BGMEDIA_PINNED_COMMIT` в `app/src/main/cpp/CMakeLists.txt`).
- iOS: сборка из `feature/ios-functional-parity-wave` (или DEV после слияния), флаг `beygram.feature.bgMedia` включён.
- Два устройства в одной Wi-Fi сети, без VPN. Ссылки передаются копированием (запасной путь: заметка).
- На обоих направлениях одна и та же дорожка BG Mix.

Сценарий A: Android → iOS
1. Android: создать приглашение (хост), скопировать ссылку.
2. iOS: вставить ссылку на экран BG Wave и нажать «Присоединиться». Ожидается: ссылка принята, слушатель формирует ответ.
3. iOS: скопировать ответ на Android.
4. Android: принять ответ. Ожидается: состояние Live на обеих сторонах, маршрут прямой.
5. Android: играть дорожку 5 минут. Ожидается: iOS слышит звук, без Failed и End.
6. Android: остановить. Ожидается: на iOS End, повторная вставка того же ответа отклоняется.

Сценарий B: iOS → Android (нужен захват хоста на iOS, этап 2): шаги 1–6 зеркально.

Сценарий C: повтор после сбоя. Ожидания по коду, на устройстве не проверено.
1. Довести волну до Failed, например отключив Wi-Fi на время сессии. Ожидается: «нет связи».
2. Хост: «Повторить». Ожидается: Reconnecting, в Live волна не переходит.
3. Хост: «Стоп». Ожидается: на хосте волна закрыта. На слушателе волна остаётся в Reconnecting, пока там не нажат «Стоп».
4. Слушатель: «Повторить», затем, если экран даёт повторный вызов, ещё раз. Ожидается: Reconnecting, после второго вызова Failed с «нет связи».
Если шаг 2 или 4 приводит к Live, гипотеза из кода неверна: записать журнал (события `host.*` и `phase`) и сообщить.

Негативные проверки (можно раньше, только декодирование инвайтов):
- ссылка с одним изменённым символом отклоняется;
- ссылка длиннее 4096 символов отклоняется до декодирования;
- ссылка с истёкшим сроком (TTL 120 с) отклоняется;
- обе формы, `bg://wave/v1/…` и https, принимаются.

Критерии прохождения: оба направления Live; 5 минут без Failed и End; звук слышен (отмечает Beykus); End доходит до второй
стороны; маршрут одинаковый на обеих сторонах.

Логи, прикладываются целиком: Android (логи BG Wave, код в `media/bgwave/*` и JNI, с начала до конца сессии); iOS (консоль
устройства, фильтр `BGWave`; вывод `diagnosticsSummary()` при End, когда появится экран); хэш коммита на каждой стороне.

Фиксация: результаты пишутся сюда отдельным разделом с датой и ссылками на логи.

## 7. Ограничения и риски

- **Протокол v1 не заморожен.** В README фикстур сказано, что окончательная заморозка требует проверки реальным SDP и круга
  Telegram `text-url`. До заморозки формат инвайтов нельзя менять без согласования с Android.
- **Размер ссылки.** Инвайт с тремя кандидатами, как в Offer из фикстуры, занимает 302 символа в https-форме. Потолок ядра:
  2048 байт полезной нагрузки, около 2,8 тыс. символов base64. Это ниже лимита 4096.
- **Исправления ядра.** Ветки `fix/wave-*` аудита уже в `dev`: `fix/wave-jitter-and-pipeline-audio`,
  `fix/wave-signaling-and-security`, `fix/wave-webrtc-and-opus`, `fix/wave-cmake-and-docs`. Это проверено по графу коммитов.
  Тесты ядра на Linux прошли, транспорт на iOS не проверен.
- **Лимит NAT.** TURN нет. Симметричный NAT и CGNAT дают `P2PFailed`, поэтому фаза 2 остаётся нужной.
- **Локальная сеть на iOS.** В приложении нет ключа `NSLocalNetworkUsageDescription`. Без него iOS может не показать запрос
  доступа к локальной сети и блокировать соединения внутри одного Wi-Fi, поэтому проверка Android и iOS в одной сети может
  упасть без понятной причины. Ключ нужно добавить в Info.plist приложения на этапе 3, а текст разрешения утверждает Beykus.
- **Лицензии.** libdatachannel и libjuice под MPL-2.0, usrsctp под BSD-3-Clause, plog под MIT. Проверка исходников: маркера
  «Incompatible With Secondary Licenses» нет ни в одном файле, заголовка MPL-2.0 (Exhibit A) тоже нет, поэтому MPL действует
  через файлы LICENSE. Это техническая запись, не юридическое заключение; атрибуция и вывод в корневом `NOTICE`. Совместимость
  с GPL-2.0-or-later приложения решает владелец (Beykus) перед первой сборкой для релиза.
- **Вспомогательные файлы Linux-проверок** (заголовок версии для BoringSSL, сборка libsrtp WebRTC вне Bazel) в репозиторий
  не входят и для iOS не нужны.
- **Не делать:** не переписывать `BGWaveViewController.mm` целиком; не править пин и `BUILD` `BeyGramMedia` из этого PR;
  не писать в `BGMediaCore` из iOS-репозитория (это только чтение, см. `submodules/BeyGramMedia/CLAUDE.md`); не вызывать
  `rtc::Cleanup()` в приложении.
