# BeyGram iOS — bootstrap

Это самостоятельная iOS-реализация BeyGram. Исходный Android-проект импортирован ради истории и ссылок на поведение/дизайн; Kotlin/Jetpack Compose и Android TDLib JNI **не запускаются на iOS**.

## Статус

- [x] SwiftUI app shell с четырьмя вкладками и базовой палитрой.
- [x] XcodeGen проект для сборки iPhone-приложения.
- [x] GitHub Actions для unsigned device build и IPA артефакта.
- [ ] iOS-совместимая сборка TDLib и Swift/C++ bridge.
- [ ] Telegram API id/hash из отдельной безопасной конфигурации.
- [ ] Авторизация, сохранение сессии, чаты, сообщения, медиа.
- [ ] iOS lifecycle, background notifications, proxies, diagnostics.
- [ ] Apple signing, provisioning, реальная установка и тестирование.
- [ ] Согласованная кроссплатформенная система тем и синхронизации функций.

**Текущая сборка — только UI-прототип. Она не выполняет вход в Telegram и не может заменить Android-клиент.**

## Сборка

На macOS с Xcode и Homebrew:

```bash
brew install xcodegen
cd ios
xcodegen generate --spec project.yml
xcodebuild -project BeyGramIOS.xcodeproj \
  -scheme BeyGramIOS -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

На GitHub workflow `.github/workflows/ios.yml` выполняет эти шаги на macOS runner.

## IPA и подпись

CI создаёт **BeyGram-iOS-unsigned.ipa** (упакованный `Payload/BeyGramIOS.app`) и прикрепляет его к workflow artifact. По тегу `ios-v*` файл публикуется в GitHub Releases как **prerelease**.

Это **не подписанный Apple релиз**. Нельзя просто открыть его на iPhone и установить. Для реального устройства нужны подходящие сертификат, provisioning profile и установка через поддерживаемый механизм (либо внешняя переподпись совместимым инструментом). Не сохраняйте приватные сертификаты, пароли и профили непосредственно в git.

Будущий подписанный CI будет отдельным этапом после согласования способа распространения и создания учётных данных Apple.

## Организация

- `ios/` — новая iOS-реализация.
- Исходные Android файлы пока не удаляются: они нужны как точная поведенческая спецификация.
- Android и iOS имеют разный UI и платформенный runtime; не объединять Kotlin и Swift прямым merge.
- Новые функции переносить в оба клиента через спецификации и отдельные PR.
