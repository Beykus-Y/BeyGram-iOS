# BG Wave: контракт для UI

Дата: 2026-11-22. Статус: контроллер и ядро проверены на Linux (`BGWaveCoreTests`, `BGWaveControllerTests`, выход 0).
Фасад `BGWaveSessionController` написан и не собран (нет macOS). Устройство не проверялось. Сборку и тесты проверит
один большой прогон GitHub CI, когда закончат все потоки; его запускает поток невидимки из интеграционной ветки.
Расхождения с Android и открытые решения: `docs/bg-wave-android-compat.md`.

## 1. Слои

| Слой | Где | Что делает | Язык |
|---|---|---|---|
| `BGWaveInvite` | `BGWaveCore/` | Кодек приглашений в двух формах, срок, nonce | C++20 |
| `BGWaveSession` | `BGWaveCore/` | Одна сессия (хост или слушатель) поверх `WaveAudioPipeline` | C++20 |
| `BGWaveController` | `BGWaveCore/` | Одна волна для пользователя: приглашения, фазы, ошибки | C++20 |
| `BGWaveRuntime` | `BGWaveListener/Sources/` | Opus, libdatachannel, `BGWaveSession`, хост-тап | C++20 |
| `BGWaveSessionController` | `BGWaveListener/` | Фасад для UI: очередь, таймеры, тап, вывод слушателя | Objective-C++ |
| Экран, карточка, отправка в чат | UI | Показ, кнопки, `text-url` в приватном чате | Swift или ObjC |

UI работает только с фасадом. Контроллер и ядро UI не вызывает.

## 2. Потоки и порядок вызовов

- Методы фасада асинхронны. Каждый вызов уходит на приватную serial-очередь `org.beygram.wave.session`
  (`BGWaveSessionController.mm`, строка 335). Вызывать можно из любого потока.
- Completion-блоки, `delegate`, `outboundLinkHandler` и `hostTapHandler` вызываются на главной очереди.
- Единственное синхронное ожидание главной очереди: `hostTapHandler(NULL)` через `dispatch_sync` перед освобождением
  хост-сессии (`BGWaveSessionController.mm`, строки 606–612). Поэтому главная очередь не должна синхронно ждать фасад.
  Публичные методы асинхронны, так что этого не происходит.
- Сбор ICE идёт синхронно на очереди фасада внутри `startHosting` и `join`. Он ждёт до `gatheringTimeoutMs` = 5000 мс
  (`WebRtcWaveTransport.hpp`, строка 35). UI показывает прогресс и не ждёт.
- `-invalidate` асинхронный. Вызвать один раз перед освобождением последней ссылки.

## 3. API фасада

Заголовок: `BGWaveListener/PublicHeaders/BGWaveListener/BGWaveSessionController.h`.

| Метод | Когда вызывать | Что приходит назад |
|---|---|---|
| `snapshotWithCompletion:` | при показе экрана | снимок, на главной |
| `startHostingForAccountId:chatId:peerId:completion:` | хост начал делиться | https-оффер, sid, ошибка |
| `offerSentForSidHex:success:` | после отправки оффера в Telegram | успех: ждём ответ; неуспех: волна закрыта |
| `setHostSourceUnsupported:forSidHex:` | источник звука нельзя отправить слушателю | флаг в снимке |
| `receiveLink:accountId:chatId:senderId:outgoing:privateChat:messageId:` | для каждого сообщения, где может быть ссылка | карточка появляется через делегата |
| `joinSidHex:completion:` | слушатель нажал «Присоединиться» | https-ответ, sid, ошибка; `None` означает отказ без изменений (приглашения нет или оно не Pending) |
| `answerSendFailedForSidHex:` | ответ не ушёл в Telegram | волна `Failed`, ошибка `SendFailed` |
| `declineSidHex:completion:` | «Отклонить» | https-Cancel с nonce 1 (`kDeclineNonce`) |
| `stopWithCompletion:` | «Стоп» в любой фазе | https-Cancel до ответа или End после ответа, nonce 2 (`kStopNonce`); nil, если отправлять нечего |
| `retryWithCompletion:` | «Повторить» после сбоя | `started`: запущен ли повтор. Для обеих ролей как в Android, см. раздел 14 |
| `dismiss` | «Закрыть» после сбоя или окончания | очищает экран |
| `cancelLinkForSidHex:completion:` | оффер ушёл уже после локального стопа | https-Cancel с nonce 3 (`kAbortCancelNonce`) |
| `resetAccountId:` | выход из аккаунта | приглашения аккаунта удаляются; волна закрывается, если она его |
| `noteOfferMessageForAccountId:chatId:messageId:sidHex:` | оффер отправлен сообщением | связывает сообщение с sid |
| `offerMessageGoneForAccountId:chatId:messageId:stillValidSidHex:` | сообщение удалено или изменено | волна с этим оффером отменяется |
| `invalidate` | экран закрывается | освобождает сессию, таймеры, вывод звука и тап |

Фасад сам ничего не отправляет в Telegram. Все https-ссылки уходят в UI, который делает отправку (`text-url`,
только приватный чат).

## 4. Модели состояния

`BGWaveSnapshotModel`: `session` (может быть nil) и `invites` (в порядке прихода).

`BGWaveSessionModel`: `role`, `accountId`, `chatId`, `peerId`, `sidHex`, `phase`, `error`, `route`,
`sourceUnsupported`, `localNetworkHint`. `sidHex` пуст, пока у хоста нет оффера или у слушателя известно только
приглашение.

`BGWaveInviteModel`: `sidHex`, `accountId`, `chatId`, `senderId`, `uri` (ссылка как пришла, любой формы), `expiresAt`,
`status`.

Фазы (`BGWaveSessionPhase`) в том же порядке, что у Android `BgWavePhase` (`BgWaveController.kt`, строка 28):

| Фаза | Смысл | Как попадаем |
|---|---|---|
| Offering | хост создал оффер, ждёт отправки | `startHosting` |
| AwaitingAnswer | оффер отправлен, ждём ответ | `offerSent` с успехом |
| Connecting | ответ принят, соединяемся | `join` у слушателя; ответ у хоста (`onAnswer`) |
| Live | звук идёт | нативные `LiveP2P` и `LiveTelegramCall`, по опросу |
| Reconnecting | повтор начат | `retry` |
| Failed | сбой | нативные `P2PFailed` и `Failed`; по опросу ставится ошибка `NoConnection`; отказ при вступлении |
| Ended | волна закрыта | `stop`; End или Cancel от пира; истёк срок оффера (без ошибки) |

Маршрут (`BGWaveSessionRoute`): `None`, `Direct` (нативный P2P), `ExternalCall`. Это статус, а не обещание. В UI
писать «Прямое соединение», не «P2P».

Статус приглашения (`BGWaveInviteStatus`): Pending, Joined, Declined, Cancelled, Ended, Expired.

## 5. События

| Событие | Когда | Поток |
|---|---|---|
| `didChangeSnapshot` | после каждого изменения волны или приглашений, в том числе по результату опроса | главная |
| `outboundLinkHandler` | опрос нашёл исходящую ссылку (ответ или оффер) | главная |
| `hostTapHandler(tap)` | хост стартовал: отдать тап миксеру | главная |
| `hostTapHandler(NULL)` | перед освобождением хост-сессии: снять тап | главная, синхронно |
| completion-блоки | результат вызова | главная |

Снимок приходит целиком. UI состояние не вычисляет.

## 6. Ошибки и ключи локализации

| `BGWaveSessionError` | Ключ BeyGramL10n | Когда |
|---|---|---|
| Unavailable | `bgwave_error_unavailable` | нативная сессия не создалась |
| SendFailed | `bgwave_error_send_failed` | оффер или ответ не ушёл в Telegram |
| NoConnection | `bgwave_error_no_connection` | P2P не установился или упал (по опросу) |
| Busy | `bgwave_error_busy` | уже идёт другая волна |
| Expired | `bgwave_error_expired` | приглашение истекло при `join`. Истечение оффера переводит волну в Ended без ошибки |
| Rejected | `bgwave_error_rejected` | ядро не приняло приглашение или ответ |
| OfferTooLarge | `bgwave_error_offer_too_large` | оффер длиннее 4096 символов |

Строки ключей совпадают с Android `BgWaveErrors` (`BgWaveController.kt`, строки 58–66). `BGWaveSessionErrorLocalizationKey`
возвращает ключ, а `nil` для None. Тексты RU и EN пишет UI-слой в BeyGramL10n.

## 7. Жизненный цикл

Хост:
1. `startHosting` переводит в Offering и возвращает https-оффер. Тап отдаётся через `hostTapHandler`.
2. UI отправляет оффер и вызывает `offerSentForSidHex`.
3. Ответ слушателя приходит в `receiveLink`: волна переходит в Connecting, затем в Live (по опросу).
4. `stop` возвращает Cancel (до ответа) или End (после). Тап снимается до освобождения сессии.

Слушатель:
1. Приглашение появляется в `invites` со статусом Pending.
2. `joinSidHex` переводит в Connecting и возвращает https-ответ. Фасад запускает вывод звука.
3. UI отправляет ответ. Если отправка не удалась, вызвать `answerSendFailedForSidHex`.
4. Live приходит по опросу. Отказ до join: `declineSidHex`. Стоп после join: `stop` (End).

Таймеры: пока волна есть, `pump` вызывается каждые 10 мс (`kPumpIntervalNs`, строка 17), а опрос идёт каждые 100 тиков,
то есть примерно раз в секунду (строка 20). Когда волны нет, таймер останавливается (`updateTimers`, строка 616).

Вывод звука слушателя: старт в `joinSidHex` после успешного join (строка 437). Стоп в `stopWithCompletion` (строка 473),
при закрытии сессии (`willCloseNativeSession`, строка 602) и в `invalidate` (строка 549). Ошибка старта пишется только
в лог (открытый пункт, раздел 14).

## 8. Что решает контроллер, а что UI

В проверяемой копии нет Android-карточки с матрицей кнопок, поэтому ниже только то, что проверено по коду контроллера
и тестам. UI выводит кнопки из фазы, статуса приглашения и этих правил:
- `join` принимает только приглашение в статусе Pending. Иначе отказ без изменений.
- `join`, когда волна не завершена (фаза не Failed и не Ended), даёт `Busy`, и волна не меняется
  (`BGWaveController.cpp`, строка 312).
- `join` приглашения с истёкшим сроком даёт `Expired`.
- `decline` работает только для Pending.
- `stop` в живой фазе отправляет Cancel (Offering, AwaitingAnswer) или End (Connecting, Live, Reconnecting). В Failed и Ended он только закрывает волну локально и возвращает nil (`BGWaveController.cpp`, строки 381–416).
- `retry` работает только из Failed и Reconnecting. Тот же гейт у Android: `BgWaveController.kt`, строка 412.
- `dismiss` работает только из Failed и Ended (`isSettled`, `BGWaveController.cpp`, строки 29–31 и 441).

Предлагаемые кнопки (это предложение для UI, на Android не сверено):
- Pending: «Присоединиться», «Отклонить».
- Offering или AwaitingAnswer: «Отменить» (это `stop`).
- Live: «Стоп».
- Failed с NoConnection: «Повторить» (для обеих ролей как в Android, см. раздел 14) и «Закрыть».
- Ended: «Закрыть».

## 9. Согласие stealth

Правило Android (`BgWaveStealthConsent.kt`, строки 7–11):
- `needsConsent = holdsSends || warnsBeforeSending`;
- сигнал уходит, если `!needsConsent || consented`; согласие привязано к sid (`consentedSid == sidHex`,
  `BgWaveHub.kt`, строка 92).

Где стоит проверка (`BgWaveHub.kt`):
- в `send()` (строка 92). Через неё идут оффер, ответ, Cancel (decline, stop, cancelLink) и End;
- до создания волны (`share`, строка 113) и до `join` (строка 139). Там без согласия состояние не меняется:
  волна не создаётся и не вступает.

Следствие для stop: без согласия End не уходит, локально волна уже закрыта, и пир держит её до истечения срока. Так
работает Android, iOS повторяет.

Фасад согласие не проверяет. Гейт стоит в слое отправки приложения; его владелец поток невидимки.

## 10. Скрытая ссылка

Правило `BgWaveLink.find` (`BgWaveLink.kt`, строки 33–38):
- в сообщении ровно одна сущность Url, которая покрывает весь непустой текст;
- её аргумент — ссылка волны в любой форме, не длиннее 4096 символов;
- видимый текст-ссылка не считается.

Приватный чат и исходящие: Android отбрасывает сообщения с `!privateChat || outgoing` (`BgWaveController.kt`,
строки 215–216). Отправитель и чат: контроллер iOS проверяет их сам (тест `testInvitationFromGroupWrongSenderOrOwnMessageIsIgnored`).

UI извлекает ссылку по этому правилу и передаёт в `receiveLink:` либо nil.

## 11. Подсказка о локальной сети

- `localNetworkHint` = YES только в фазе Failed и только если транспорт упал без выбранной пары кандидатов
  (`failureKind() == LocalNetworkSuspected`, `BGWaveSessionController.mm`, строки 560–563).
- iOS не даёт публичного API для статуса разрешения на локальную сеть. Поэтому подсказка — признак, не факт, и текст
  только с «возможно».
- Запрос разрешения: при первом использовании BG Wave, не при запуске приложения. Строки `NSLocalNetworkUsageDescription`
  (RU и EN) лежат в ветке `feature/ios-bgwave-local-network-permission` (PR #77, не слит).
- Текст подсказки и кнопки «Настройки» — ключи BeyGramL10n, заводит UI-слой.

## 12. Формы приглашений

- `bg://wave/v1/<payload>` — внутренняя форма.
- `https://beygram.beykus.fun/#bgwave-v1.<payload>` — форма для Telegram. Её отдаёт контроллер.
- `decodeInvite` принимает обе формы. Длина не больше 4096 символов, проверка до декодирования.
- Control-ссылки (Cancel, End) на iOS: caps 0, срок 60 с, как канонические фикстуры BG-Media. На Android: caps 3,
  срок 300 с. Ядро декодирует обе (проверено на Linux, см. `bg-wave-android-compat.md`).

## 13. Тесты и проверки

| Что | Команда (Mac) | Статус |
|---|---|---|
| Кодек и сессия | `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMedia/BGWaveCore:BGWaveCoreTests --test_output=all` | Linux: проходит |
| Контроллер | то же для `BGWaveControllerTests` | Linux: проходит |
| Адаптеры и рантайм | `//submodules/BeyGramMedia/BGWaveListener:BGWaveAdaptersTests`, `:BGWaveRuntimeTests` | не запускались |
| Фасад | сборка `//submodules/BeyGramMedia/BGWaveListener:BGWaveSessionController` | не собирался |
| Android ↔ iOS | сценарий в `docs/bg-wave-ios.md`, раздел 6; issue #97 (его шаг 1 называет старый `BGWaveListenerSession`; шаг 2 закрывает `hostTapHandler` фасада на уровне API) | записан, не запускался |

Mac и Gemini не ждём. Один большой прогон GitHub CI запустится, когда закончат все потоки. Пуш в feature-ветки и
открытие PR CI не запускают: `.github/workflows/build.yml` срабатывает только на `main`, `build/**`, теги и ручной запуск.

## 14. Открытые вопросы

- Повтор после сбоя решён 2026-11-22: как в Android, без отказа для хоста. Подробно в `bg-wave-android-compat.md`,
  пункт 1. Для экрана: если повтор не завершается, выход через «Стоп» в фазе Reconnecting.
- `ExternalCallFallback` в офферах и ответах: пункт 2 compat.
- Ошибка старта вывода слушателя видна только в логе.
- Сетевой ретрай (аналог Android `BgWaveNetworkWatcher`) на iOS не подключён. Нужны `NWPathMonitor` и вызов `retry`.
- Гейт стелса для сигналов BG Wave: раздел 9. Без него отправка не соответствует Android.
