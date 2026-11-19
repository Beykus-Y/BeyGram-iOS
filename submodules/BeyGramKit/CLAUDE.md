# BeyGramKit

Модуль BeyGram: флаги функций и настройки. Часть плана переноса BeyGram на iOS (документ «План переноса BeyGram на iOS»).

## Схема расширения апстрима

- Код BeyGram живёт в отдельных модулях `submodules/BeyGram*`. Файлы Telegram-iOS меняются только короткими хуками: вызов кода модуля из одного места.
- Каждая правка файла апстрима даёт конфликт при слиянии с `TelegramMessenger/Telegram-iOS` (см. `docs/UPSTREAM_SYNC.md`), поэтому логика в апстрим-файлы не пишется.
- Модуль зависит только от Foundation и Security (Keychain для секретов BG Push, как в `PasscodeCore`). Не импортировать Postbox и TelegramCore: новый код не должен добавлять зависимостей от Postbox.

## Что здесь

- `BeyGramFeature`: флаги функций. Каждый case относится к блоку плана (B–K). По умолчанию все выключены.
- `BeyGramSettings`: хранилище поверх `UserDefaults`, ключи `beygram.feature.*` и `beygram.settings.appearance`. Изменения рассылаются через `didChangeNotification`.
- `BeyGramAppearance`: `telegram` (оригинальные темы Telegram, по умолчанию) или `beygram` (вид BeyGram рядом с ними).

## Как добавить функцию

1. Добавить case в `BeyGramFeature` и название в `title(languageCode:)`. Сейчас ru и en, de/es/fr позже.
2. В месте хука читать `BeyGramSettings.shared.isEnabled(.<case>)`. Выключенная функция не должна менять поведение Telegram.
3. Не менять формат ключей без увеличения `BeyGramSettings.schemaVersion` и миграции.

## BG Push (блок G2)

Поток: создать регистрацию (`POST /api/v1/push/registrations`), открыть ссылку установки (страница PWA сама вызывает `complete`), дождаться `active` (опрос `GET`), зарегистрировать токен в Telegram, вызвать `POST …/{id}/telegram-confirm`. Отзыв: `DELETE /api/v1/push/registrations/{id}`, затем `account.unregisterDevice` с тем же токеном.

- `BeyGramPush.swift`: модели (`BeyGramPushRegistration`, `BeyGramPushRegistrationStatus`, `BeyGramPushState`, `BeyGramPushTelegramToken`), генератор bearer `BeyGramPushBearer`, HTTP-клиент `BeyGramPushClient`, состояние в `UserDefaults` (`BeyGramPushStore`, ключ `beygram.push.state.v2`, без секретов) и разбор ссылки `BeyGramPushOpenRequest` для `beygram://push/open?account=&peer=&msg=`.
- `BeyGramPushSecrets.swift`: секреты регистрации (bearer владельца, адрес ingress, ссылка установки, ключи Telegram) в Keychain (`BeyGramPushSecretStore`). Keychain переживает переустановку приложения, поэтому контроллер сверяет `registrationId` с состоянием.
- Регистрация токена в Telegram (`account.registerDevice` и `unregisterDevice` с `token_type` 10): `TelegramCore/Sources/TelegramEngine/AccountData/BeyGramPushRegistration.swift`. Существующий путь APNs и VoIP не менялся.
- Экран и строка в «Уведомления»: `SettingsUI/Sources/BeyGramPush/BeyGramPushController.swift`. Переключатель управляет `BeyGramFeature.bgPush`, который по умолчанию выключен. Выключение переключателя отзывает регистрацию так же, как кнопка «Отключить».
- Deep link: ветка в `AppDelegate.openUrl` работает только при включённом флаге. Если аккаунт не совпадает или чат не найден, открывается список чатов.
- Контракт сервера: раздел «API для нативного клиента» в `docs/bg-push.md` репозитория BeyGram-Diagnostics-Server (issue #30). Контракт не подтверждён на iPhone: go/no-go проверяет владелец.

## Статус сборки

Код написан в облачной сессии без Swift и Bazel, поэтому компиляция не проверена. Первая проверка пойдёт одним CI-прогоном ветки `integration/beygram-ios` после слияния волны.
