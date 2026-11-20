# BeyGramProxy: прокси Mihomo на iOS

Ядро Mihomo работает внутри приложения как локальный SOCKS5 на `127.0.0.1:17891`. Telegram подключается к нему через свои настройки прокси. Всё включается флагом `mihomoProxy`, который выключен по умолчанию.

**Статус: не собрано и не проверено на устройстве.** В окружении разработки не было Xcode и Bazel. Go-тесты проходили локально. Swift-код не компилировался. CI не запускался.

## Состав

- `core/` — Go-модуль на mihomo v1.19.32.
  - `bridge/` — JSON-мост. Действия: `init`, `normalize`, `validate`, `setup`, `stop`, `status`, `proxies`, `select`, `testDelay`, `resetConnections`.
  - `normalize/` — подписка (vless, vmess, ss, trojan, hysteria2, tuic) в профиль Clash.
  - `cmd/beygram-mihomo/` — экспорт `BGMihomoInvoke` и `BGMihomoFree` для `-buildmode=c-archive`.
- `Sources/` — Swift-модуль `BeyGramProxy` (цель Bazel, зависит только от Security).
  - `MihomoCoreClient` — типизированный слой над драйвером ядра.
  - `MihomoProxyController` — подписка, запуск и остановка, выбор узла, задержки.
  - `LoopbackCredentials` — логин и пароль локального входа, хранятся в Keychain.
  - `SubscriptionFetcher` — загрузка подписки по https.
  - `MihomoProxyState` — состояние в `state.json`.
- `CoreBridge/` — `MihomoCgoDriver`, заголовок `BeyGramMihomoCore.h` и `module.modulemap`. Не входит в цель Bazel.
- `submodules/SettingsUI/Sources/BeyGramStyle/BeyGramMihomo*.swift` — экран и связка с настройками Telegram.
- `submodules/SettingsUI/Sources/Data and Storage/ProxyListSettingsController.swift` — строка «Прокси Mihomo» в списке прокси. Видна только при флаге.

## Как работает

1. Подписка (ссылка https или текст) нормализуется в профиль Clash. В профиле: `allow-lan: false`, вход `127.0.0.1:17891` (SOCKS5) с логином и паролем, которые уникальны для каждой установки, TUN выключен, группа `BeyGram Telegram` с выбором узла, правило `MATCH`.
2. Ядро запускается в процессе приложения. Network Extension не используется.
3. Перед подключением настройки прокси Telegram сохраняются в `state.json`. После подключения Telegram направляется на локальный вход. При отключении возвращаются сохранённые `enabled` и `activeServer`, а строка локального входа удаляется из списка.

## Известные ограничения

- **Перезапуск при старте.** Если приложение закрыли во время работы, при следующем запуске ядро поднимается само (хук в `AppDelegate`, только при флаге `mihomoProxy`). Подписка при этом загружается заново, если это ссылка.
- **Автопереключение узлов.** Включается переключателем в экране Mihomo. Раз в 20 секунд проверяется узел в работе; если он не отвечает, выбирается самый быстрый из ответивших. Если ядро перестаёт отвечать, оно перезапускается с тем же профилем. В отличие от Android, проверка идёт через задержку узла, а не через отдельную проверку доступа к Telegram, и узлы проверяются по очереди.
- Подписка загружается только напрямую, без прокси.
- Trojan всегда использует TLS, даже без `security` в ссылке. Android так не делает.
- Если пользователь менял свои прокси во время работы Mihomo, при отключении `activeServer` и `enabled` перезапишутся снимком от подключения.
- Строки интерфейса только на русском и английском.

## Лицензия

Mihomo распространяется под GPL-3.0. Исходники модуля и Go-ядра лицензированы GPL-3.0; полный текст лежит в `LICENSE` этого каталога, сведения о сторонних компонентах — в `NOTICE` в корне репозитория. Файл `LICENSE` корня (GPL-2.0) не менялся: код Telegram остаётся под GPL-2.0-or-later. Совместимость объединённой сборки не проверялась юристом; решение о распространении принимает владелец.

Флаг `mihomoProxy` остаётся выключенным по умолчанию. Архив ядра (`libbeygram-mihomo.a`) в сборку пока не подключён: `UnlinkedMihomoCoreDriver` отвечает «Ядро Mihomo не подключено в этой сборке».

## Сборка (не проверено)

Go-тесты:

    cd submodules/BeyGramProxy/core
    go test ./...

Архив для iOS, предположительно:

    GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC=<clang из Xcode для iOS SDK> \
      go build -buildmode=c-archive -o libbeygram-mihomo.a ./cmd/beygram-mihomo

Готовый скрипт (нужен macOS с Xcode и Go 1.24):

    ./submodules/BeyGramProxy/core/build-ios-archive.sh

Скрипт кладёт `libbeygram-mihomo.a` в `CoreBridge/lib` (git игнорирует). Что проверено и что нет:

- Проверено в Linux: `go test ./...` проходит; `go build -buildmode=c-archive` собирает архив, экспорт `BGMihomoInvoke` и `BGMihomoFree` совпадает с `CoreBridge/include/BeyGramMihomoCore.h`. Размер архива для Linux со `-s -w` около 66 МБ.
- Не проверено: сборка под `GOOS=ios` (нужен Xcode), минимальная версия iOS в скрипте (`MIN_IOS`, по умолчанию 15.0, поставить реальный deployment target), размер в IPA.

Bazel пока не подключён: нет цели для архива и заголовка, `MihomoCgoDriver` не входит в `swift_library`, `BeyGramMihomoRuntime` использует `UnlinkedMihomoCoreDriver`. Эти три шага делаются вместе и проверяются только на Mac.

## Перед включением флага

1. Скомпилировать модуль `BeyGramProxy` и экран (в окружении без Xcode не проверено).
2. Подключить архив ядра через `MihomoCgoDriver` и проверить подключение Telegram через локальный вход.
3. Проверить восстановление настроек при отключении.
4. Проверить перезапуск при старте и автопереключение на устройстве.
5. Решить вопрос распространения объединённой сборки (см. выше).
