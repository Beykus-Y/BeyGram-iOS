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

## Пока не подключено

Модуль не входит ни в одну цель приложения, поэтому сборка `Telegram/Telegram` его не компилирует. Компиляция модуля не проверена: в облачной сессии нет Swift и Bazel. Проверка случится при подключении модуля к приложению, в сборке на macOS.
