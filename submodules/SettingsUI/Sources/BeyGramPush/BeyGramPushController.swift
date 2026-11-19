import Foundation
import UIKit
import CoreImage
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import BeyGramKit

// Экран BG Push: включение функции, регистрация, статус и отключение.
// Флаг `BeyGramFeature.bgPush` выключен по умолчанию. Пока он выключен, экран показывает только переключатель:
// сеть не используется и Telegram ничего не регистрирует. Выключение переключателя отзывает регистрацию.

private func beyGramPushIsRussian() -> Bool {
    return (Locale.preferredLanguages.first ?? "").hasPrefix("ru")
}

private func beyGramPushLocalized(_ russian: String, _ english: String) -> String {
    return beyGramPushIsRussian() ? russian : english
}

/// Название строки в настройках уведомлений.
public func beyGramPushSettingsTitle() -> String {
    return beyGramPushLocalized("BG Push (экспериментально)", "BG Push (experimental)")
}

private func beyGramPushErrorText(_ error: BeyGramPushError) -> String {
    switch error {
    case .invalidRequest:
        return beyGramPushLocalized("Некорректный запрос", "Invalid request")
    case .network:
        return beyGramPushLocalized("Нет связи с сервером", "No connection to the server")
    case let .http(code):
        return beyGramPushLocalized("Сервер ответил кодом \(code)", "The server responded with code \(code)")
    case .decoding:
        return beyGramPushLocalized("Не удалось разобрать ответ сервера", "Could not read the server response")
    }
}

private func beyGramPushInfoText() -> String {
    return beyGramPushLocalized(
        "Уведомления для iOS без платного аккаунта разработчика. Установите страницу BeyGram на экран «Домой» и разрешите уведомления: Telegram будет присылать их через BG Push, а по нажатию откроется нужный чат. Функция выключена по умолчанию, проверка на iPhone ещё не пройдена.",
        "Notifications for iOS without a paid developer account. Add the BeyGram page to the Home Screen and allow notifications: Telegram sends them through BG Push, and tapping one opens the right chat. The feature is off by default and has not yet been verified on an iPhone."
    )
}

private func beyGramPushStatusText(registration: BeyGramPushState?, hasSecrets: Bool, isRegistering: Bool, lastError: String?) -> String {
    var text: String
    if let registration = registration {
        if !hasSecrets {
            text = beyGramPushLocalized("Секреты привязки не найдены на этом устройстве. Отключите BG Push и настройте заново", "The link secrets are missing on this device. Disconnect BG Push and set it up again")
        } else {
            switch registration.state {
            case .pending:
                text = beyGramPushLocalized("Ждём установки страницы и разрешения на уведомления", "Waiting for the page install and the notification permission")
            case .active:
                if registration.telegramConfirmedAt != nil {
                    text = beyGramPushLocalized("Привязано. Telegram подтвердил регистрацию", "Linked. Telegram confirmed the registration")
                } else if isRegistering {
                    text = beyGramPushLocalized("Привязано. Регистрируем в Telegram", "Linked. Registering with Telegram")
                } else {
                    text = beyGramPushLocalized("Привязано, но Telegram ещё не подтвердил регистрацию. Нажмите «Проверить статус»", "Linked, but Telegram has not confirmed the registration yet. Tap “Check the status”")
                }
            case .expired:
                text = beyGramPushLocalized("Срок установки истёк. Настройте заново", "The setup window has expired. Set it up again")
            case .revoked:
                text = beyGramPushLocalized("Привязка отозвана на сервере. Настройте заново", "The link was revoked on the server. Set it up again")
            }
        }
    } else {
        text = beyGramPushLocalized("Не настроено", "Not set up")
    }
    if let lastError = lastError {
        text += "\n" + lastError
    }
    return text
}

/// QR-код для строки. Генерируется через CoreImage, без сети.
private func beyGramPushQrImage(_ string: String, size: CGFloat) -> UIImage? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
        return nil
    }
    filter.setValue(Data(string.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let outputImage = filter.outputImage, outputImage.extent.width > 0 else {
        return nil
    }
    let scale = size / outputImage.extent.width
    let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}

private final class BeyGramPushQrController: UIViewController {
    private let link: String

    init(link: String) {
        self.link = link
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemBackground
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.closePressed))

        let imageView = UIImageView(image: beyGramPushQrImage(self.link, size: 240.0))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(imageView)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 15.0)
        label.text = self.link
        self.view.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 40.0),
            imageView.widthAnchor.constraint(equalToConstant: 240.0),
            imageView.heightAnchor.constraint(equalToConstant: 240.0),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 24.0),
            label.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24.0),
            label.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24.0),
        ])
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }
}

private enum BeyGramPushAction: Int32 {
    case setup = 0
    case openSetupPage = 1
    case showQr = 2
    case check = 3
    case disconnect = 4
}

private enum BeyGramPushSection: Int32 {
    case main
}

private final class BeyGramPushArguments {
    let setEnabled: (Bool) -> Void
    let perform: (BeyGramPushAction) -> Void

    init(setEnabled: @escaping (Bool) -> Void, perform: @escaping (BeyGramPushAction) -> Void) {
        self.setEnabled = setEnabled
        self.perform = perform
    }
}

private enum BeyGramPushEntry: ItemListNodeEntry {
    case header(PresentationTheme, String)
    case toggle(PresentationTheme, String, Bool)
    case text(PresentationTheme, String, Int32)
    case action(PresentationTheme, String, BeyGramPushAction, Bool)

    var section: ItemListSectionId {
        return BeyGramPushSection.main.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case .toggle:
            return 1
        case let .text(_, _, id):
            return 10 + id
        case let .action(_, _, action, _):
            return 100 + action.rawValue
        }
    }

    static func ==(lhs: BeyGramPushEntry, rhs: BeyGramPushEntry) -> Bool {
        switch lhs {
        case let .header(lhsTheme, lhsText):
            if case let .header(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .toggle(lhsTheme, lhsText, lhsValue):
            if case let .toggle(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            } else {
                return false
            }
        case let .text(lhsTheme, lhsText, lhsId):
            if case let .text(rhsTheme, rhsText, rhsId) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsId == rhsId {
                return true
            } else {
                return false
            }
        case let .action(lhsTheme, lhsText, lhsAction, lhsDestructive):
            if case let .action(rhsTheme, rhsText, rhsAction, rhsDestructive) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsAction == rhsAction, lhsDestructive == rhsDestructive {
                return true
            } else {
                return false
            }
        }
    }

    static func <(lhs: BeyGramPushEntry, rhs: BeyGramPushEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramPushArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.setEnabled(newValue)
            })
        case let .text(_, text, _):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .action(_, text, action, destructive):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: destructive ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.perform(action)
            })
        }
    }
}

private func beyGramPushEntries(presentationData: PresentationData, enabled: Bool, registration: BeyGramPushState?, hasSecrets: Bool, isRegistering: Bool, lastError: String?) -> [BeyGramPushEntry] {
    let theme = presentationData.theme
    let languageCode = beyGramPushIsRussian() ? "ru" : "en"
    var entries: [BeyGramPushEntry] = []
    entries.append(.header(theme, beyGramPushLocalized("Уведомления", "Notifications")))
    entries.append(.toggle(theme, BeyGramFeature.bgPush.title(languageCode: languageCode), enabled))
    entries.append(.text(theme, beyGramPushInfoText(), 0))
    guard enabled else {
        return entries
    }
    entries.append(.text(theme, beyGramPushStatusText(registration: registration, hasSecrets: hasSecrets, isRegistering: isRegistering, lastError: lastError), 1))
    let needsSetup = registration == nil || registration?.state == .expired || registration?.state == .revoked
    if needsSetup {
        entries.append(.action(theme, beyGramPushLocalized("Настроить уведомления", "Set up notifications"), .setup, false))
    }
    if hasSecrets, let registration = registration, registration.state == .pending {
        entries.append(.action(theme, beyGramPushLocalized("Открыть страницу установки в Safari", "Open the setup page in Safari"), .openSetupPage, false))
        entries.append(.action(theme, beyGramPushLocalized("Показать QR-код", "Show the QR code"), .showQr, false))
    }
    if registration != nil {
        if hasSecrets {
            entries.append(.action(theme, beyGramPushLocalized("Проверить статус", "Check the status"), .check, false))
        }
        entries.append(.action(theme, beyGramPushLocalized("Отключить и удалить привязку", "Disconnect and remove the link"), .disconnect, true))
    }
    return entries
}

/// Состояние экрана и сетевые действия. Живёт, пока открыт экран, и держит опрос статуса.
private final class BeyGramPushScreenModel {
    private let context: AccountContext
    private let store = BeyGramPushStore.shared
    private let secretStore = BeyGramPushSecretStore.shared
    private let client = BeyGramPushClient()
    private let registerDisposable = MetaDisposable()
    private let unregisterDisposable = MetaDisposable()
    private var pollTimer: Timer?
    private var revisionValue = 0
    private var isPolling = false
    private var isBusy = false
    /// После ошибки Telegram или подтверждения автоматически не повторяем. Повтор запускает «Проверить статус».
    private var telegramAttemptFailed = false

    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    /// Ошибка действия: создание, отзыв, регистрация или подтверждение в Telegram.
    var lastError: String?
    /// Ошибка последнего опроса сервера. Сбрасывается при успешном опросе.
    var pollError: String?
    /// Регистрация в Telegram идёт сейчас.
    var isRegistering = false
    weak var controller: UIViewController?

    init(context: AccountContext) {
        self.context = context
    }

    deinit {
        self.pollTimer?.invalidate()
        self.registerDisposable.dispose()
        self.unregisterDisposable.dispose()
    }

    private func bump() {
        self.revisionValue += 1
        self.revision.set(self.revisionValue)
    }

    /// Запускает опрос, если регистрация ещё не завершена. Вызывается при открытии экрана и при включении функции.
    func resume() {
        guard let registration = self.store.load() else {
            return
        }
        switch registration.state {
        case .pending:
            self.startPolling()
        case .active:
            if registration.telegramConfirmedAt == nil {
                self.startPolling()
            }
        case .expired, .revoked:
            break
        }
    }

    func setEnabled(_ enabled: Bool) {
        BeyGramSettings.shared.setEnabled(enabled, for: .bgPush)
        if enabled {
            self.lastError = nil
            self.pollError = nil
            self.resume()
        } else {
            // Выключенная функция не должна оставлять регистрацию в Telegram и на сервере.
            self.stopPolling()
            self.disconnect(completion: nil)
        }
        self.bump()
    }

    func perform(_ action: BeyGramPushAction) {
        switch action {
        case .setup:
            self.startSetup()
        case .openSetupPage:
            self.openSetupPage()
        case .showQr:
            self.showQr()
        case .check:
            self.lastError = nil
            self.telegramAttemptFailed = false
            self.isRegistering = false
            self.poll()
        case .disconnect:
            self.disconnect(completion: nil)
        }
    }

    private func startSetup() {
        guard !self.isBusy else {
            return
        }
        if self.store.load() != nil {
            // Старую регистрацию сначала отзываем, иначе на сервере останутся лишние привязки.
            self.disconnect(completion: { [weak self] cleared in
                if cleared {
                    self?.createRegistration()
                }
            })
        } else {
            self.createRegistration()
        }
    }

    private func createRegistration() {
        self.isBusy = true
        self.lastError = nil
        self.pollError = nil
        self.bump()
        let bearer = BeyGramPushBearer.generate()
        self.client.createRegistration(bearer: bearer) { [weak self] result in
            DispatchQueue.main.async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.isBusy = false
                switch result {
                case let .success(registration):
                    let secrets = BeyGramPushSecrets(registrationId: registration.registrationId, bearer: bearer, ingressUrl: registration.ingressUrl, setupUrl: registration.setupUrl, telegramKeys: nil)
                    guard strongSelf.secretStore.save(secrets) else {
                        // Без сохранённых секретов регистрацию не отследить, поэтому отзываем её, пока bearer ещё в памяти.
                        strongSelf.client.deleteRegistration(registrationId: registration.registrationId, bearer: bearer) { _ in
                        }
                        strongSelf.lastError = beyGramPushLocalized("Не удалось сохранить секреты в Keychain", "Could not save the secrets to the Keychain")
                        strongSelf.bump()
                        return
                    }
                    strongSelf.store.save(BeyGramPushState(registrationId: registration.registrationId, state: registration.state, expiresAt: registration.expiresAt, telegramConfirmedAt: nil))
                    strongSelf.telegramAttemptFailed = false
                    strongSelf.isRegistering = false
                    strongSelf.bump()
                    strongSelf.startPolling()
                    strongSelf.openSetupPage()
                case let .failure(error):
                    strongSelf.lastError = beyGramPushErrorText(error)
                    strongSelf.bump()
                }
            }
        }
    }

    private func openSetupPage() {
        guard let setupUrl = self.secretStore.load()?.setupUrl else {
            return
        }
        self.context.sharedContext.applicationBindings.openUrl(setupUrl)
    }

    private func showQr() {
        guard let setupUrl = self.secretStore.load()?.setupUrl, let controller = self.controller else {
            return
        }
        let navigationController = UINavigationController(rootViewController: BeyGramPushQrController(link: setupUrl))
        controller.present(navigationController, animated: true, completion: nil)
    }

    func poll() {
        guard !self.isPolling, let registration = self.store.load(), let secrets = self.secretStore.load(), secrets.registrationId == registration.registrationId else {
            return
        }
        let registrationId = registration.registrationId
        self.isPolling = true
        self.client.pollRegistration(registrationId: registrationId, bearer: secrets.bearer) { [weak self] result in
            DispatchQueue.main.async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.isPolling = false
                switch result {
                case let .success(status):
                    strongSelf.apply(status, registrationId: registrationId)
                case let .failure(error):
                    strongSelf.pollError = beyGramPushErrorText(error)
                    strongSelf.bump()
                }
            }
        }
    }

    private func apply(_ status: BeyGramPushRegistrationStatus, registrationId: String) {
        // Ответ относится к регистрации, которая могла смениться, пока шёл запрос. Тогда он не нужен.
        guard var registration = self.store.load(), registration.registrationId == registrationId, var secrets = self.secretStore.load(), secrets.registrationId == registrationId else {
            return
        }
        self.pollError = nil
        registration.state = status.state
        if let expiresAt = status.expiresAt {
            registration.expiresAt = expiresAt
        }
        if let confirmedAt = status.telegramConfirmedAt {
            registration.telegramConfirmedAt = confirmedAt
        }
        if let keys = status.telegramKeys, secrets.telegramKeys != keys {
            secrets.telegramKeys = keys
            self.secretStore.save(secrets)
        }
        self.store.save(registration)
        self.bump()
        switch status.state {
        case .pending:
            break
        case .active:
            if registration.telegramConfirmedAt != nil {
                self.stopPolling()
            } else if let keys = secrets.telegramKeys {
                if !self.telegramAttemptFailed && !self.isRegistering {
                    self.register(keys: keys)
                }
            } else {
                self.lastError = beyGramPushLocalized("Сервер не вернул ключи Telegram", "The server did not return the Telegram keys")
                self.bump()
            }
        case .expired, .revoked:
            self.stopPolling()
        }
    }

    private func register(keys: BeyGramPushTelegramKeys) {
        guard let secrets = self.secretStore.load(), let token = BeyGramPushTelegramToken(endpoint: secrets.ingressUrl, keys: keys).registrationToken() else {
            self.telegramAttemptFailed = true
            self.lastError = beyGramPushLocalized("Не удалось подготовить токен регистрации", "Could not prepare the registration token")
            self.bump()
            return
        }
        self.isRegistering = true
        self.bump()
        let registration = beyGramRegisterWebPushToken(account: self.context.account, token: token, otherAccountUserIds: []) |> deliverOnMainQueue
        self.registerDisposable.set(registration.start(next: { [weak self] registered in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isRegistering = false
            if registered {
                strongSelf.confirm()
            } else {
                strongSelf.telegramAttemptFailed = true
                strongSelf.lastError = beyGramPushLocalized("Telegram не принял регистрацию. Нажмите «Проверить статус», чтобы повторить", "Telegram did not accept the registration. Tap “Check the status” to retry")
            }
            strongSelf.bump()
        }))
    }

    /// Сообщает серверу, что Telegram принял токен. Сервер отмечает время подтверждения.
    private func confirm() {
        guard let registration = self.store.load(), let secrets = self.secretStore.load(), secrets.registrationId == registration.registrationId else {
            return
        }
        let registrationId = registration.registrationId
        self.client.confirmTelegram(registrationId: registrationId, bearer: secrets.bearer) { [weak self] result in
            DispatchQueue.main.async {
                guard let strongSelf = self else {
                    return
                }
                switch result {
                case .success:
                    if var confirmed = strongSelf.store.load(), confirmed.registrationId == registrationId {
                        confirmed.telegramConfirmedAt = Date()
                        strongSelf.store.save(confirmed)
                    }
                    strongSelf.telegramAttemptFailed = false
                    strongSelf.lastError = nil
                    strongSelf.stopPolling()
                case let .failure(error):
                    strongSelf.telegramAttemptFailed = true
                    strongSelf.lastError = beyGramPushErrorText(error)
                }
                strongSelf.bump()
            }
        }
    }

    /// Отзывает регистрацию на сервере, затем снимает токен с Telegram. Локальное состояние стирается,
    /// только когда сервер подтвердил отзыв, чтобы повтор был возможен. Completion получает true, если состояние очищено.
    private func disconnect(completion: ((Bool) -> Void)?) {
        guard !self.isBusy else {
            completion?(false)
            return
        }
        self.stopPolling()
        guard let registration = self.store.load() else {
            completion?(true)
            return
        }
        guard let secrets = self.secretStore.load(), secrets.registrationId == registration.registrationId else {
            // Секретов нет, поэтому отозвать регистрацию на сервере нельзя. Очищаем только локальное состояние.
            self.clearLocal()
            self.bump()
            completion?(true)
            return
        }
        self.isBusy = true
        self.lastError = nil
        self.bump()
        self.client.deleteRegistration(registrationId: registration.registrationId, bearer: secrets.bearer) { [weak self] result in
            DispatchQueue.main.async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.isBusy = false
                switch result {
                case .success:
                    strongSelf.releaseTelegramToken(secrets: secrets)
                    strongSelf.clearLocal()
                    strongSelf.bump()
                    completion?(true)
                case let .failure(error):
                    strongSelf.lastError = beyGramPushLocalized("Не удалось отозвать привязку на сервере: ", "Could not revoke the link on the server: ") + beyGramPushErrorText(error)
                    strongSelf.bump()
                    completion?(false)
                }
            }
        }
    }

    private func releaseTelegramToken(secrets: BeyGramPushSecrets) {
        guard let keys = secrets.telegramKeys, let token = BeyGramPushTelegramToken(endpoint: secrets.ingressUrl, keys: keys).registrationToken() else {
            return
        }
        let unregistration = beyGramUnregisterWebPushToken(account: self.context.account, token: token, otherAccountUserIds: []) |> deliverOnMainQueue
        self.unregisterDisposable.set(unregistration.start(completed: {}))
    }

    private func clearLocal() {
        self.store.clear()
        self.secretStore.clear()
        self.isRegistering = false
        self.telegramAttemptFailed = false
        self.pollError = nil
        self.lastError = nil
    }

    private func startPolling() {
        self.pollTimer?.invalidate()
        self.pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true, block: { [weak self] _ in
            self?.poll()
        })
    }

    private func stopPolling() {
        self.pollTimer?.invalidate()
        self.pollTimer = nil
    }
}

/// Экран BG Push. Открывается из настроек уведомлений.
public func beyGramPushController(context: AccountContext) -> ViewController {
    let model = BeyGramPushScreenModel(context: context)
    let arguments = BeyGramPushArguments(setEnabled: { [weak model] enabled in
        model?.setEnabled(enabled)
    }, perform: { [weak model] action in
        model?.perform(action)
    })

    let signal = combineLatest(context.sharedContext.presentationData, model.revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("BG Push"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let errorText = [model.lastError, model.pollError].compactMap({ $0 }).joined(separator: "\n")
        let entries = beyGramPushEntries(presentationData: presentationData, enabled: BeyGramSettings.shared.isEnabled(.bgPush), registration: BeyGramPushStore.shared.load(), hasSecrets: BeyGramPushSecretStore.shared.load() != nil, isRegistering: model.isRegistering, lastError: errorText.isEmpty ? nil : errorText)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    model.controller = controller
    model.resume()
    return controller
}
