# Обновление исходников из upstream (`TelegramMessenger/Telegram-iOS`)

История `BeyGram-iOS` объединена с историей официального `Telegram-iOS` без squash — у них есть общий merge base (`24638bc69bd083981b178dd1e7f921eebbf7fc46`, тег `release-13.2`). Благодаря этому последующие обновления подтягиваются стандартным `git merge`.

## Процедура обновления

1. Убедитесь, что `upstream` настроен:
   ```sh
   git remote -v
   # upstream  https://github.com/TelegramMessenger/Telegram-iOS.git
   ```
   Если `upstream` отсутствует:
   ```sh
   git remote add upstream https://github.com/TelegramMessenger/Telegram-iOS.git
   ```

2. Получите новые теги и ветки из `upstream`:
   ```sh
   git fetch upstream --tags
   ```

3. Создайте ветку обновления от `DEV`:
   ```sh
   git checkout DEV
   git pull origin DEV
   git checkout -b chore/upstream-release-13.3
   ```

4. Выполните слияние с нужным тегом (или `upstream/master`):
   ```sh
   git merge release-13.3
   ```

5. Проверьте и сохраните изменения BeyGram при разрешении конфликтов:
   - `versions.json`: сохраните `"app"` (версия BeyGram) и обновите `"upstream_app"`, `"upstream_commit"`, `"xcode"`, `"bazel"`.
   - `.gitmodules`: сохраните абсолютный URL `https://github.com/TelegramMessenger/tgcalls.git` для `submodules/TgVoipWebrtc/tgcalls`.
   - `Telegram/BUILD`: сохраните `telegram_display_name`, `telegram_app_specific_url_scheme` и `UrlTypesInfoPlist` (только `beygram://`).
   - `build-system/Make/Make.py` и `BuildConfiguration.py`: сохраните поддержку `display_name`, `--disableProvisioningProfiles` и `--disableExtensions` в `build`.
   - `submodules/TelegramUI/Sources/AppDelegate.swift`: сохраните fallback для `maybeAppGroupUrl` при отсутствии App Group.
   - `Telegram/Telegram-iOS/Telegram.icon/` и `AppIcons.xcassets/BlueIcon.appiconset/`: сохраните иконки BeyGram.
   - `.github/workflows/build.yml`, `build-system/beygram-*.json`, `build-system/verify-ipa.sh`: сохраните конфигурацию CI BeyGram.

6. Отправьте ветку, запустите workflow **Build BeyGram iOS** вручную (`workflow_dispatch`) и убедитесь, что IPA собирается и проходит `verify-ipa.sh`, после чего откройте PR в `DEV`.

## Хуки BeyGram в файлах Telegram-iOS

Код BeyGram живёт в модулях `submodules/BeyGram*`. В файлы апстрима вставлены только короткие вызовы этих модулей. При слиянии с upstream эти строки нужно сохранить. Правила и список хуков по модулям: `submodules/BeyGramStealth/CLAUDE.md`, `submodules/BeyGramKit/CLAUDE.md`.

| Файл | Что добавлено | Модуль |
|---|---|---|
| `submodules/TelegramCore/BUILD` | зависимость `//submodules/BeyGramStealth:BeyGramStealth` | BeyGramStealth |
| `submodules/TelegramCore/Sources/State/PendingMessageManager.swift` | `sendGroupMessagesContent` и `sendMessageContent`: дата отложенной отправки (`scheduleDate` и флаг 10), отказ для непланируемых отправок | BeyGramStealth |
| `submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift` | `updatePresence`: скрытый онлайн; параметр `accountPeerId` в `AccountPresenceManager` | BeyGramStealth |
| `submodules/TelegramCore/Sources/Account/Account.swift` | передача `accountPeerId` в `AccountPresenceManager` | BeyGramStealth |
| `submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift` | `requestActivity`: скрытый набор текста и другие действия в чате | BeyGramStealth |
| `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift` | `pushPeerReadState`: скрытые отчёты о прочтении | BeyGramStealth |
