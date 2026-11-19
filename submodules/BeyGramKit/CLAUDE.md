# BeyGramKit

Модуль BeyGram: флаги функций и настройки. Часть плана переноса BeyGram на iOS (документ «План переноса BeyGram на iOS»).

## Схема расширения апстрима

- Код BeyGram живёт в отдельных модулях `submodules/BeyGram*`. Файлы Telegram-iOS меняются только короткими хуками: вызов кода модуля из одного места.
- Каждая правка файла апстрима даёт конфликт при слиянии с `TelegramMessenger/Telegram-iOS` (см. `docs/UPSTREAM_SYNC.md`), поэтому логика в апстрим-файлы не пишется.
- Модуль зависит только от Foundation. Не импортировать Postbox и TelegramCore: новый код не должен добавлять зависимостей от Postbox.

## Что здесь

- `BeyGramFeature`: флаги функций. Каждый case относится к блоку плана (B–K). По умолчанию все выключены.
- `BeyGramSettings`: хранилище поверх `UserDefaults`, ключи `beygram.feature.*` и `beygram.settings.appearance`. Изменения рассылаются через `didChangeNotification`.
- `BeyGramAppearance`: `telegram` (оригинальные темы Telegram, по умолчанию) или `beygram` (вид BeyGram рядом с ними).

## Как добавить функцию

1. Добавить case в `BeyGramFeature` и название в `title(languageCode:)`. Сейчас ru и en, de/es/fr позже.
2. В месте хука читать `BeyGramSettings.shared.isEnabled(.<case>)`. Выключенная функция не должна менять поведение Telegram.
3. Не менять формат ключей без увеличения `BeyGramSettings.schemaVersion` и миграции.

## BG Push (блок G2)

- `BeyGramPush.swift`: модели (`BeyGramPushIngress`, `BeyGramPushState`), HTTP-клиент `BeyGramPushClient` (`/api/v1/push/pairings`, `/api/v1/push/installations/{id}`), хранилище `BeyGramPushStore` (`UserDefaults`, ключ `beygram.push.state.v1`) и разбор ссылки `BeyGramPushOpenRequest` для `beygram://push/open?account=&peer=&msg=`. Только Foundation.
- Регистрация токена в Telegram (`account.registerDevice` и `unregisterDevice` с `token_type` 10): `TelegramCore/Sources/TelegramEngine/AccountData/BeyGramPushRegistration.swift`. Это новый файл, существующий путь APNs и VoIP не менялся.
- Экран и строка в «Уведомления»: `SettingsUI/Sources/BeyGramPush/BeyGramPushController.swift`. Переключатель управляет `BeyGramFeature.bgPush`, который по умолчанию выключен.
- Deep link: ветка в `AppDelegate.openUrl` работает только при включённом флаге. Если аккаунт не совпадает или чат не найден, открывается список чатов.
- Контракт сервера: issue #30 в BeyGram-Diagnostics-Server. Контракт не подтверждён на iPhone: go/no-go проверяет владелец.

## Статус сборки

Код написан в облачной сессии без Swift и Bazel, поэтому компиляция не проверена. Первая проверка пойдёт одним CI-прогоном ветки `integration/beygram-ios` после слияния волны.
