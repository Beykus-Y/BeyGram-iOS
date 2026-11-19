# Установка BeyGram iOS (Sideloading без платного Apple Developer аккаунта)

BeyGram iOS собирается в конфигурации, совместимой с бесплатной подписью через **AltStore** или **SideStore** (бесплатный Apple ID). Приложение использует независимый Bundle ID (`com.beykus.beygram.dev` / `com.beykus.beygram`) и собственную URL-схему (`beygram://`), поэтому устанавливается **рядом с официальным Telegram** без конфликтов.

## 1. Скачивание IPA

1. Откройте вкладку **Actions** в репозитории [`Beykus-Y/BeyGram-iOS`](https://github.com/Beykus-Y/BeyGram-iOS/actions).
2. Выберите последний успешный запуск workflow **Build BeyGram iOS**.
3. В разделе **Artifacts** скачайте архив `BeyGram-DEV-v0.0.1-b...` и распакуйте `BeyGram-DEV.ipa`.
4. (Опционально) Сверьте контрольную сумму из файла `BeyGram-DEV.ipa.sha256`.

## 2. Установка через SideStore (рекомендуется) или AltStore

1. Установите **SideStore** (или **AltStore**) на iPhone по официальной инструкции разработчиков инструмента.
2. Передайте `BeyGram-DEV.ipa` на iPhone (AirDrop, iCloud Drive, Файлы).
3. Откройте **SideStore** → вкладка **My Apps** → нажмите `+` → выберите `BeyGram-DEV.ipa`.
4. При запросе параметров подписи выберите ваш бесплатный Apple ID.
   - SideStore/AltStore автоматически переподпишет приложение и назначит ваш Team ID.
   - Если инструмент спросит про **App Extensions**, в DEV-сборке для sideloading расширения уже отключены (`--disableExtensions`), поэтому приложение занимает **всего 1 App ID**.

## 3. Ограничения бесплатной подписи Apple ID

| Ограничение | Влияние на BeyGram |
| --- | --- |
| **Срок жизни сертификата: 7 дней** | Необходимо обновлять подпись раз в 7 дней (в SideStore это делается прямо на iPhone). |
| **Лимит: 3 активных приложения** | BeyGram считается одним из 3 sideload-приложений (вместе с самим AltStore/SideStore остаётся место ещё для 1 приложения). |
| **Лимит: 10 App IDs в неделю** | Расширения отключены (`--disableExtensions`), поэтому BeyGram расходует только **1 App ID**. |
| **Нет APNs (Push-уведомления)** | Фоновые системные push-уведомления недоступны. Сообщения доставляются при открытом приложении; в будущем планируется интеграция с **BG Push**. |
| **Нет Associated Domains** | Ссылки `t.me` не перехватываются BeyGram — они продолжают открываться в официальном Telegram, если он установлен. |
| **App Groups fallback** | Если sideload-инструмент удаляет entitlement `com.apple.security.application-groups`, BeyGram автоматически хранит данные в собственном контейнере `Library/Application Support/beygram-app-group` без ошибки `Error 2`. |
| **Отключённые capabilities** | PushKit/VoIP unrestricted, CarPlay, Siri, iCloud, Apple Pay, Associated Domains, Sign in with Apple, Watch App и App Extensions (Share, Widgets, Notification Service/Content, Broadcast Upload, Siri Intents). |
