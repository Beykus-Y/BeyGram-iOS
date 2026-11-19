# BeyGram iOS

Неофициальный клиент Telegram для iOS в экосистеме **BeyGram**, основанный на официальной кодовой базе [`TelegramMessenger/Telegram-iOS`](https://github.com/TelegramMessenger/Telegram-iOS).

## Происхождение и текущий upstream

- **Версия BeyGram:** `0.0.1` (`DEV`)
- **Базовый upstream:** `TelegramMessenger/Telegram-iOS`
- **Тег upstream:** `release-13.2`
- **Commit SHA upstream:** `24638bc69bd083981b178dd1e7f921eebbf7fc46`
- **Лицензия:** GPLv2 (условия оригинального проекта Telegram iOS; исходный код публикуется с сохранением всех оригинальных лицензий и copyright notices).

## Основные отличия от официального Telegram iOS

- **Независимая идентификация:**
  - DEV Bundle ID: `com.beykus.beygram.dev` (`BeyGram DEV`)
  - Release Bundle ID: `com.beykus.beygram` (`BeyGram`)
  - URL-схема: `beygram://` (схемы `tg://`, `telegram://`, `ton://`, `tonsite://`, `tc://` и Associated Domains отключены, чтобы не перехватывать ссылки у официального Telegram).
- **Поддержка бесплатного sideloading (AltStore / SideStore):**
  - В `Make.py build` добавлена поддержка `--disableProvisioningProfiles` и `--disableExtensions`.
  - В `submodules/TelegramUI/Sources/AppDelegate.swift` добавлен безопасный fallback при `containerURL(forSecurityApplicationGroupIdentifier:) == nil` на локальный каталог `Library/Application Support/beygram-app-group`, что предотвращает ошибку `Error 2` при переподписании бесплатным Apple ID.
- **Брендинг:**
  - Иконка приложения адаптирована из фирменного стиля Android-клиента [`Beykus-Y/BeyGram`](https://github.com/Beykus-Y/BeyGram).
  - Обновлены `CFBundleDisplayName`, `CFBundleName`, экран приветствия (`Tour.*`) и описания разрешений.

## Структура веток

- `main` — стабильные версии BeyGram.
- `DEV` — основная ветка разработки.
- `feature/*` — ветки отдельных задач.
- `backup/*` — архивные ветки предыдущей реализации BeyGram iOS до перехода на кодовую базу Telegram (`backup/pre-telegram-migration-main`, `backup/pre-telegram-migration-dev`).
- `upstream` remote — `https://github.com/TelegramMessenger/Telegram-iOS.git`.

## Сборка через GitHub Actions

Workflow: [`.github/workflows/build.yml`](.github/workflows/build.yml)

- **Runner:** `xcode-27` (macOS 27, Xcode 27.1, ARM64).
- **Система сборки:** Bazel (`9.2.0` из `versions.json`) через `build-system/Make/Make.py`.
- **Запуск:** вручную через `workflow_dispatch` (выбор канала `DEV` или `release`), а также автоматически при push в `main` или теги `v*` / `release-*`.
- **Секреты репозитория:** `TELEGRAM_API_ID` и `TELEGRAM_API_HASH` (подставляются во временную конфигурацию на время сборки и никогда не логируются).
- **Проверка результата:** [`build-system/verify-ipa.sh`](build-system/verify-ipa.sh) автоматически проверяет структуру `Payload/*.app`, архитектуру `arm64`, отсутствие simulator-бинарников, Bundle ID, Display Name, версию, URL-схемы и отсутствие посторонних сертификатов.

## Локальная разработка с Windows и требования к macOS

Сборка iOS-приложения требует **macOS** и **Xcode** (согласно `versions.json`: macOS `27`, Xcode `27.1`, Bazel `9.2.0`, Python 3). На **Windows** выполняется редактирование кода, управление Git/PR и запуск/мониторинг сборок через GitHub Actions (`gh`).

## Документация

- [Установка через AltStore / SideStore и ограничения бесплатной подписи](docs/SIDELOADING.md)
- [Обновление исходников из upstream Telegram-iOS](docs/UPSTREAM_SYNC.md)
- [Оригинальная документация сборки Telegram-iOS](Telegram/CLAUDE.md)
