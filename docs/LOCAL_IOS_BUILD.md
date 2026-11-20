# Локальная сборка BeyGram iOS

Руководство по локальной сборке, проверке и установке IPA **BeyGram iOS** на компьютерах Mac с процессорами **Intel (x86_64)** и **Apple Silicon (arm64)** с различными версиями Xcode.

---

## 1. Требования к окружению

### Аппаратное обеспечение и ОС
- **Apple Silicon (M1/M2/M3/M4)** или **Intel Mac (x86_64)**
- **macOS**: рекомендуется macOS 15 Sequoia или новее (в `.bazelrc` заданы `--host_macos_minimum_os=15.0` и `--macos_minimum_os=15.0` для host-инструментов; при сборке на более старой macOS значение можно переопределить в `.bazelrc.local`).
- **Свободное место на диске**: не менее 60–80 ГБ (исходники с подмодулями, `bazelUserRoot`, кеш артефактов `--cacheDir`).
- **Оперативная память**: рекомендуется от 16 ГБ (на машинах с 8–10 ГБ ОЗУ обязательно ограничивайте параллелизм в `.bazelrc.local` через `--jobs=4`).

### Программное обеспечение
- **Xcode**: 26.x / 27.x (проверено на Xcode 26.3 с iOS SDK 26.2 / Swift 6.2.4, а также в CI на `xcode-27`).
- **Bazel**: версия из `versions.json` (текущая: `9.2.0`).
- **Python**: Python 3.10+ (рекомендуется Python 3.13 через MacPorts или Homebrew).
- **Go**: Go `1.24.7+` (для сборки нативного C-архива ядра Mihomo в `submodules/BeyGramProxy/core/`).
- **Git** с поддержкой рекурсивных подмодулей.

---

## 2. Подготовка Xcode и обязательных компонентов

1. Установите нужную версию Xcode и выберите её активной:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   # Пример для версионированного Xcode:
   # sudo xcode-select -s /Applications/Xcode-26.3.0.app/Contents/Developer
   ```
2. Примите лицензию и завершите первичную инициализацию:
   ```bash
   sudo xcodebuild -license accept
   xcodebuild -runFirstLaunch
   ```
3. Установите обязательные компоненты Xcode (в Xcode -> Settings -> Components или через CLI):
   - **iOS Platform / SDK**
   - **iOS Simulator** (если планируются simulator-сборки или тесты)
   - **Metal Toolchain** (начиная с Xcode 26 вынесен в отдельный загружаемый компонент):
     ```bash
     xcodebuild -downloadComponent MetalToolchain
     ```
4. Проверьте готовность компонентов перед сборкой:
   ```bash
   xcode-select -p
   xcodebuild -version
   xcrun --sdk iphoneos --show-sdk-path
   xcrun --sdk iphoneos metal --version
   ```
   Скрипт `build-system/Make/Make.py` автоматически выполняет эти проверки перед запуском `build` и `test` и выводит подсказку при отсутствии Metal Toolchain или iOS SDK.

---

## 3. Настройка Bazel и Python

### Установка Bazel
Установите точную версию Bazel из `versions.json` (например, `9.2.0`) в `~/bin/bazel` или через Homebrew/Bazelisk:
```bash
mkdir -p ~/bin
# Скачайте бинарник bazel-9.2.0 для вашей архитектуры (darwin-arm64 или darwin-x86_64)
# и проверьте SHA-256 перед запуском:
chmod +x ~/bin/bazel
~/bin/bazel --version
```

### Установка Python 3.13 и Go
- **Apple Silicon (Homebrew)**:
  ```bash
  brew install python@3.13 go
  ```
- **Intel / MacPorts**:
  ```bash
  sudo port install python313 go
  ```
Убедитесь, что `python3.13` и `go` (>= 1.24.7) доступны в `PATH` (или в `/opt/local/bin`, `/usr/local/go/bin`, `/opt/homebrew/bin`). При первом запуске Bazel автоматически соберёт `libbeygram-mihomo.a` через `submodules/BeyGramProxy/core/build-bazel.sh` и закеширует результат в `--disk_cache`.

### Клонирование репозитория и подмодулей
```bash
git clone https://github.com/Beykus-Y/BeyGram-iOS.git
cd BeyGram-iOS
git submodule update --init --recursive
```

---

## 4. Постоянный кеш и `.bazelrc.local`

### Постоянный кеш сборки
Для ускорения повторных сборок используйте отдельные постоянные директории за пределами репозитория:
- `--bazelUserRoot="$HOME/beygram-bazel-root"` — output user root Bazel (сохраняет external-репозитории и граф анализа).
- `--cacheDir="$HOME/telegram-bazel-cache"` — локальный дисковый кеш скомпилированных артефактов (`--disk_cache`).

> **Важно:** не выполняйте `bazel clean --expunge` и не удаляйте директории кеша без крайней необходимости — холодная пересборка занимает больше часа.

### Локальные настройки `.bazelrc.local`
Файл `.bazelrc` автоматически подключает необязательный файл `.bazelrc.local` (добавлен в `.gitignore`), куда можно выносить параметры конкретной машины:

```ini
# Пример ~/Projects/BeyGram-iOS/.bazelrc.local
build --jobs=4
```

На мощных Apple Silicon Mac можно увеличить `--jobs` или не создавать `.bazelrc.local` вовсе.

---

## 5. Подготовка конфигурации и подписи IPA

> **Безопасность:** никогда не добавляйте в Git `config.json`, `api_id`, `api_hash`, `.p12`, `.mobileprovision` и приватные ключи. Храните их в отдельной директории, например `~/beygram-local/`.

1. Создайте рабочий каталог вне репозитория:
   ```bash
   mkdir -p ~/beygram-local/codesigning
   ```
2. Подготовьте `~/beygram-local/config.json` на основе `build-system/beygram-dev-configuration.json` (или `build-system/beygram-release-configuration.json`), указав свои `api_id`, `api_hash` и `team_id`.
3. Для локальной sideload-сборки (без платного аккаунта Apple Developer) можно сгенерировать самоподписанные профили и импортировать тестовый сертификат:
   ```bash
   python3.13 build-system/Make/ImportCertificates.py --path build-system/fake-codesigning/certs
   python3.13 build-system/generate-sideload-codesigning.py \
     --bundleId "com.beykus.beygram.dev" \
     --teamId "C67CF9S4VU" \
     --outDir "$HOME/beygram-local/codesigning"
   ```
   При наличии собственного Apple Developer профиля поместите `.mobileprovision` и сертификат в `~/beygram-local/codesigning` или используйте `--xcodeManagedCodesigning`.

---

## 6. Запуск сборки

Пример сборки `release_arm64` IPA для реального устройства (без App Extensions для совместимости с бесплатным Apple ID):

```bash
cd ~/Projects/BeyGram-iOS
set -o pipefail

time caffeinate -i python3.13 -u build-system/Make/Make.py \
  --bazel="$HOME/bin/bazel" \
  --bazelUserRoot="$HOME/beygram-bazel-root" \
  --cacheDir="$HOME/telegram-bazel-cache" \
  --overrideXcodeVersion \
  build \
  --configurationPath="$HOME/beygram-local/config.json" \
  --codesigningInformationPath="$HOME/beygram-local/codesigning" \
  --disableExtensions \
  --configuration=release_arm64 \
  --buildNumber=1001 \
  2>&1 | tee "$HOME/beygram-local/build.log"
```

Пояснение ключевых флагов:
- `--overrideXcodeVersion` — разрешает использовать фактически выбранный Xcode вместо строгого совпадения с `versions.json`.
- `--disableExtensions` — отключает App Extensions (уменьшает количество App ID и время сборки).
- `--bazelArguments="..."` — позволяет передать дополнительные аргументы во все вызовы Bazel (например, `--bazelArguments="--jobs=4"`).

Готовый IPA находится по пути:
```text
bazel-bin/Telegram/Telegram.ipa
```

---

## 7. Проверка IPA

После сборки обязательно проверьте структуру, архитектуру, URL-схемы и отсутствие посторонних идентификаторов штатным скриптом:

```bash
chmod +x build-system/verify-ipa.sh
build-system/verify-ipa.sh \
  bazel-bin/Telegram/Telegram.ipa \
  "com.beykus.beygram.dev" \
  "BeyGram DEV" \
  "0.0.1"
```

Скрипт проверяет:
- совпадение `CFBundleIdentifier`, `CFBundleDisplayName`, `CFBundleShortVersionString`;
- наличие `arm64`-бинарника без симуляторных архитектур (`x86_64`, `IOSSIMULATOR`);
- наличие URL-схемы `beygram` и отсутствие официальных схем/идентификаторов Telegram;
- отсутствие случайно попавших `.p12`, `.cer`, `.pem`, `.key` в бандле.

---

## 8. Установка на реальное устройство с переподписанием

Если IPA собран с self-signed / sideload подписью, перед установкой на iPhone его необходимо переподписать вашим Apple ID / сертификатом разработчика:

- **Sideloadly / AltStore / SideStore**: откройте `Telegram.ipa` (или скопируйте его как `BeyGram-DEV.ipa`) и выполните установку со своим Apple ID.
- **Через `xcodebuild` / `devicectl` (при наличии действующего Developer-сертификата и профиля)**:
  переподпишите `.app` внутри IPA вашим профилем и установите через:
  ```bash
  xcrun devicectl device install app --device <DEVICE_UDID> <PATH_TO_RESIGNED.app>
  ```

---

## 9. Известные ограничения и решённые проблемы совместимости

### 1. Выбор WASI SDK по архитектуре хоста
- **Проблема**: в `MODULE.bazel` изначально был жёстко указан `wasi-sdk-33.0-arm64-macos`, который не запускается на Intel Mac (`x86_64`), а `select()` по платформе цели в `genrule` выбирает архитектуру целевого устройства (`ios_arm64`), а не хоста сборки.
- **Решение**: добавлено правило `wasi_sdk_host` (`build-system/bazel-utils/wasi_sdk.bzl`), которое определяет ОС и архитектуру **машины сборки** (`repository_ctx.os.name` и `repository_ctx.os.arch`) и подключает соответствующий архив (`wasi_sdk_macos_arm64`, `wasi_sdk_macos_x86_64`, `wasi_sdk_linux_arm64`, `wasi_sdk_linux_x86_64`). Обе WASM-цели в `submodules/TgVoipWebrtc/BUILD` (`reference_core_wasm`, `variant_core_wasm`) используют единый алиас `@wasi_sdk`.

### 2. Совместимость iOS SDK (`UIView.reservedRegions`)
- **Проблема**: API `UIView.reservedRegions(kind:)` появился в iOS 27.1 SDK и отсутствует в более ранних SDK (например, iOS 26.2 SDK в Xcode 26.3), из-за чего `#available(iOS 27.1, *)` не спасает от ошибки компиляции.
- **Решение**: правило `xcode_capabilities` (`build-system/bazel-utils/xcode_capabilities.bzl`) при конфигурации Bazel проверяет возможность компиляции `UIView.reservedRegions(kind: .occlusion)` через `xcrun --sdk iphoneos swiftc -typecheck` и выставляет `IOS_SDK_HAS_RESERVED_REGIONS`. Флаг `-DBEYGRAM_ENABLE_RESERVED_REGIONS` передаётся только цели `//submodules/Display:Display` на SDK с поддержкой этого API. На более ранних SDK используются резервные реализации (`[]` и `nil`).

### 3. Аварийное завершение Swift 6.2.4 на этапе SIL CopyPropagation
- **Проблема**: при сборке в режиме оптимизации (`-Osize -wmo`) компилятор Swift 6.2.4 падал на этапе SIL `CopyPropagation` в `RichTextEngineEditorView.replaceTable(with:parkingAt:)` (`RichTextEditor`) и в конструкторе `ShareScreen` (`ShareScreen`).
- **Решение**: выполнен точечный рефакторинг с вынесением внутренних замыканий и вспомогательных вычислений в отдельные приватные методы без изменения поведения (`applyTableReplacement` в `RichTextEngineEditorView+TableEdits.swift`, `resolvePreferredAction` и `selectInitialPeer` в `ShareScreen.swift`), что позволяет собирать оба модуля с полной оптимизацией без `-Onone`.

### 4. Исправления типизации Swift 6.2.4
- `ButtonComponent.swift`: сложное выражение расчёта `mask.locations` для радиального градиента разбито на явно типизированные промежуточные переменные (`ratio`, `start`, `span`, `offset`, `location`).
- `ChatMediaEditorScreenCover.swift`: явно указаны optional-типы `Double?` для `playerDuration` и `subjectDuration` с безопасным fallback `0.0` при неизвестной длительности видео.

### 5. Жёсткий путь `/Applications/Xcode.app` в `dav1d`
- **Проблема**: `third-party/dav1d/build-dav1d-bazel.sh` для `arm64` (`iPhoneOS`) использовал `arm64-iPhoneOS.meson` с жёстко зашитым `/Applications/Xcode.app/Contents/Developer/...`, что ломало сборку при установке Xcode под другим именем (например, `/Applications/Xcode-26.3.0.app`).
- **Решение**: скрипт теперь определяет путь через `${DEVELOPER_DIR:-$(xcode-select -p)}` и подставляет его во временный crossfile для `arm64`, `sim_arm64` и `macos_arm64`.

### 6. Deployment target для host-инструментов и `--bazelArguments`
- В `.bazelrc` добавлены `build:macos --host_macos_minimum_os=15.0` и `build:macos --macos_minimum_os=15.0` для корректной сборки host-инструментов (включая `SwiftTL`) без изменения `MinimumOSVersion` iOS-приложения.
- В `build-system/Make/Make.py` исправлена передача `--bazelArguments` во все вызовы Bazel (`build`, `test`) и добавлены предварительные проверки окружения Xcode (включая Metal Toolchain).

### 7. Оставшиеся ограничения
- На Intel Mac (`x86_64`) и в конфигурациях с Xcode < 27 (iOS SDK < 27.1) функциональность `UIView.reservedRegions` для iPhone Duo отключена на этапе компиляции с использованием безопасных резервных значений.
- В настоящем эксперименте полная сборка IPA и проверка на устройстве выполнялись на `x86_64` macOS Sequoia 15.8.3 + Xcode 26.3 + Bazel 9.2.0; сборка на Apple Silicon с Xcode 27 проверяется отдельно (в том числе через GitHub Actions).

