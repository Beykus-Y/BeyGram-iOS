# BeyGramProxy: прокси Mihomo на iOS

Ядро Mihomo работает внутри приложения как локальный SOCKS5 на `127.0.0.1:17891`. Telegram подключается к нему через свои настройки прокси. Всё включается флагом `mihomoProxy`, который выключен по умолчанию.

## Состав

- `core/` — Go-модуль на mihomo v1.19.32 (`go >= 1.24.7`).
  - `bridge/` — JSON-мост. Действия: `init`, `normalize`, `validate`, `setup`, `stop`, `status`, `proxies`, `select`, `testDelay`, `resetConnections`.
  - `normalize/` — подписка (vless, vmess, ss, trojan, hysteria2, tuic) в профиль Clash.
  - `cmd/beygram-mihomo/` — экспорт `BGMihomoInvoke` и `BGMihomoFree` для `-buildmode=c-archive`.
  - `build-bazel.sh` — воспроизводимая сборка `libbeygram-mihomo.a` для целевой архитектуры Bazel (`ios_arm64`, `ios_sim_arm64`, `ios_x86_64`, `darwin_arm64`, `darwin_x86_64`).
- `Sources/` — Swift-модуль `BeyGramProxy`.
  - `MihomoCoreClient` — типизированный слой над драйвером ядра.
  - `MihomoProxyController` — подписка, запуск и остановка, выбор узла, задержки, 20-секундный watchdog автопереключения и восстановление после смены сети.
  - `MihomoNetworkMonitor` — `NWPathMonitor`: сообщает о смене сети (интерфейсы или доступность). Контроллер ждёт 2 секунды тишины, проверяет выбранный узел и при отказе перезапускает ядро с тем же узлом.
  - `LoopbackCredentials` — логин и пароль локального входа, хранятся в Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
  - `SubscriptionFetcher` — загрузка подписки по https/http.
  - `MihomoProxyState` — состояние в `state.json` (`.completeFileProtectionUntilFirstUserAuthentication`).
- `CoreBridge/` — `MihomoCgoDriver`, заголовок `BeyGramMihomoCore.h` и `module.modulemap`. Подключены в Bazel-целях `BeyGramMihomoCore` и `BeyGramProxy`.
- `submodules/SettingsUI/Sources/BeyGramStyle/BeyGramMihomo*.swift` — экран и связка с настройками Telegram (`MihomoCgoDriver`).
- `submodules/SettingsUI/Sources/Data and Storage/ProxyListSettingsController.swift` — строка «Прокси Mihomo» в списке прокси. Видна только при флаге.

## Как работает

1. Подписка (ссылка https или текст) нормализуется в профиль Clash. В профиле: `allow-lan: false`, вход `127.0.0.1:17891` (SOCKS5) с логином и паролем, которые уникальны для каждой установки, TUN выключен, группа `BeyGram Telegram` с выбором узла, правило `MATCH`.
2. Ядро запускается в процессе приложения. Network Extension не используется.
3. Перед подключением настройки прокси Telegram сохраняются в `state.json`. После подключения Telegram направляется на локальный вход. При отключении возвращаются сохранённые `enabled` и `activeServer`, а строка локального входа удаляется из списка.

## Известные ограничения

- **Фоновая работа на iOS.** Ядро работает внутри процесса приложения без `NEPacketTunnelProvider` / Network Extension. Когда iOS переводит приложение в фон и приостанавливает процесс (suspended), локальный SOCKS5-вход на `127.0.0.1:17891` останавливается вместе с процессом. При возвращении приложения на передний план сокеты переподключаются; при полном перезапуске приложения хук в `AppDelegate` перезапускает ядро (или восстанавливает исходные настройки прокси Telegram при отказе).
- **Перезапуск при старте.** Если приложение закрыли во время работы, при следующем запуске ядро поднимается само (хук в `AppDelegate`, только при флаге `mihomoProxy`). Подписка при этом загружается заново, если это ссылка. При отказе запуска исходные настройки прокси Telegram восстанавливаются.
- **Автопереключение узлов.** Включается переключателем в экране Mihomo. Раз в 20 секунд проверяется узел в работе; если он не отвечает, выбирается самый быстрый из ответивших. Если ядро перестаёт отвечать, оно перезапускается с тем же профилем. В отличие от Android, проверка идёт через задержку узла, а не через отдельную проверку доступа к Telegram, и узлы проверяются по очереди.
- Подписка загружается только напрямую, без прокси.
- Trojan всегда использует TLS, даже без `security` в ссылке. Android так не делает.
- Если пользователь менял свои прокси во время работы Mihomo, при отключении `activeServer` и `enabled` перезапишутся снимком от подключения.
- Строки интерфейса только на русском и английском.

## Лицензия

Mihomo распространяется под GPL-3.0. Исходники модуля и Go-ядра лицензированы GPL-3.0; полный текст лежит в `LICENSE` этого каталога, сведения о сторонних компонентах — в `NOTICE` в корне репозитория. Файл `LICENSE` корня (GPL-2.0) не менялся: код Telegram остаётся под GPL-2.0-or-later. Совместимость объединённой сборки не проверялась юристом; решение о распространении принимает владелец.

Флаг `mihomoProxy` остаётся выключенным по умолчанию.

## Сборка

Go-тесты:

    cd submodules/BeyGramProxy/core
    go test ./...

Сборка в Bazel (штатный путь через `Make.py` и в CI):

- Цель `//submodules/BeyGramProxy:beygram_mihomo_archive` запускает `core/build-bazel.sh` с текущим `$(TARGET_CPU)`, формируя `libbeygram-mihomo.a` (deployment target iOS `15.0`) без сохранения бинарника в Git.
- Результат кешируется Bazel (`--disk_cache`) по исходникам `core/` и `$(TARGET_CPU)`, поэтому без изменений в Go-коде ядро не пересобирается.
- `//submodules/BeyGramProxy:BeyGramMihomoCore` экспортирует C-модуль `BeyGramMihomoCore` и линкует `CoreFoundation`, `Security` и `libresolv`.
- `//submodules/BeyGramProxy:BeyGramProxy` компилирует `Sources/` и `CoreBridge/MihomoCgoDriver.swift`.

Ручная сборка архива (при необходимости отдельной проверки):

    ./submodules/BeyGramProxy/core/build-ios-archive.sh
