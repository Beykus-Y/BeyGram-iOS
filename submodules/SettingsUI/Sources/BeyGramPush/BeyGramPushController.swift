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

// Экран BG Push: включение функции, привязка PWA, статус и отключение.
// Флаг `BeyGramFeature.bgPush` выключен по умолчанию. Пока он выключен, экран показывает только переключатель:
// сеть не используется и Telegram ничего не регистрирует.

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

private func beyGramPushAppVersion() -> String {
    return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
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

private func beyGramPushStatusText(state: BeyGramPushState?, lastError: String?) -> String {
    var text: String
    switch state?.status {
    case .pending?:
        text = beyGramPushLocalized("Ждём установки страницы и разрешения на уведомления", "Waiting for the page install and the notification permission")
    case .completed?:
        if state?.telegramRegistered == true {
            text = beyGramPushLocalized("Привязано. Telegram принял регистрацию", "Linked. Telegram accepted the registration")
        } else {
            text = beyGramPushLocalized("Привязано, но Telegram не подтвердил регистрацию. Проверьте статус", "Linked, but Telegram has not confirmed the registration. Check the status")
        }
    case .expired?:
        text = beyGramPushLocalized("Ссылка установки истекла. Настройте заново", "The setup link has expired. Set it up again")
    case .revoked?:
        text = beyGramPushLocalized("Привязка отозвана на сервере. Настройте заново", "The link was revoked on the server. Set it up again")
    case nil:
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

private func beyGramPushEntries(presentationData: PresentationData, enabled: Bool, state: BeyGramPushState?, lastError: String?) -> [BeyGramPushEntry] {
    let theme = presentationData.theme
    let languageCode = beyGramPushIsRussian() ? "ru" : "en"
    var entries: [BeyGramPushEntry] = []
    entries.append(.header(theme, beyGramPushLocalized("Уведомления", "Notifications")))
    entries.append(.toggle(theme, BeyGramFeature.bgPush.title(languageCode: languageCode), enabled))
    entries.append(.text(theme, beyGramPushInfoText(), 0))
    guard enabled else {
        return entries
    }
    entries.append(.text(theme, beyGramPushStatusText(state: state, lastError: lastError), 1))
    let hasPairing = state?.pairingId != nil
    let status = state?.status
    if !hasPairing || status == .expired || status == .revoked {
        entries.append(.action(theme, beyGramPushLocalized("Настроить уведомления", "Set up notifications"), .setup, false))
    }
    if status == .pending {
        entries.append(.action(theme, beyGramPushLocalized("Открыть страницу установки в Safari", "Open the setup page in Safari"), .openSetupPage, false))
        entries.append(.action(theme, beyGramPushLocalized("Показать QR-код", "Show the QR code"), .showQr, false))
    }
    if hasPairing {
        entries.append(.action(theme, beyGramPushLocalized("Проверить статус", "Check the status"), .check, false))
        entries.append(.action(theme, beyGramPushLocalized("Отключить и удалить привязку", "Disconnect and remove the link"), .disconnect, true))
    }
    return entries
}

/// Состояние экрана и сетевые действия. Живёт, пока открыт экран, и держит опрос статуса.
private final class BeyGramPushScreenModel {
    private let context: AccountContext
    private let store = BeyGramPushStore.shared
    private let client = BeyGramPushClient()
    private let registrationDisposable = MetaDisposable()
    private var pollTimer: Timer?
    private var revisionValue = 0

    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var lastError: String?
    weak var controller: UIViewController?

    init(context: AccountContext) {
        self.context = context
    }

    deinit {
        self.pollTimer?.invalidate()
        self.registrationDisposable.dispose()
    }

    private func bump() {
        self.revisionValue += 1
        self.revision.set(self.revisionValue)
    }

    func setEnabled(_ enabled: Bool) {
        BeyGramSettings.shared.setEnabled(enabled, for: .bgPush)
        if !enabled {
            self.stopPolling()
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
            self.poll()
        case .disconnect:
            self.disconnect()
        }
    }

    private func startSetup() {
        let installationId = self.store.loadOrCreate().installationId
        self.client.createPairing(installationId: installationId, appVersion: beyGramPushAppVersion()) { [weak self] result in
            DispatchQueue.main.async {
                guard let strongSelf = self else {
                    return
                }
                switch result {
                case let .success(pairing):
                    var state = strongSelf.store.loadOrCreate()
                    state.pairingId = pairing.pairingId
                    state.pollToken = pairing.pollToken
                    state.setupUrl = pairing.setupUrl
                    state.expiresAt = pairing.expiresAt
                    state.status = .pending
                    state.ingress = nil
                    state.telegramRegistered = false
                    strongSelf.store.save(state)
                    strongSelf.lastError = nil
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

    func openSetupPage() {
        guard let setupUrl = self.store.load()?.setupUrl else {
            return
        }
        self.context.sharedContext.applicationBindings.openUrl(setupUrl)
    }

    func showQr() {
        guard let setupUrl = self.store.load()?.setupUrl, let controller = self.controller else {
            return
        }
        let navigationController = UINavigationController(rootViewController: BeyGramPushQrController(link: setupUrl))
        controller.present(navigationController, animated: true, completion: nil)
    }

    func poll() {
        guard let state = self.store.load(), let pairingId = state.pairingId, let pollToken = state.pollToken else {
            return
        }
        self.client.pollPairing(pairingId: pairingId, pollToken: pollToken) { [weak self] result in
            DispatchQueue.main.async {
                guard let strongSelf = self else {
                    return
                }
                switch result {
                case let .success(pollResult):
                    strongSelf.apply(pollResult)
                case let .failure(error):
                    strongSelf.lastError = beyGramPushErrorText(error)
                    strongSelf.bump()
                }
            }
        }
    }

    private func apply(_ pollResult: BeyGramPushPollResult) {
        guard var state = self.store.load() else {
            return
        }
        state.status = pollResult.status
        if let ingress = pollResult.ingress, state.ingress != ingress {
            state.ingress = ingress
            state.telegramRegistered = false
        }
        self.store.save(state)
        self.lastError = nil
        self.bump()
        switch pollResult.status {
        case .pending:
            break
        case .completed:
            self.stopPolling()
            if !state.telegramRegistered, let ingress = state.ingress {
                self.register(ingress: ingress)
            }
        case .expired, .revoked:
            self.stopPolling()
        }
    }

    private func register(ingress: BeyGramPushIngress) {
        guard let token = ingress.registrationToken() else {
            self.lastError = beyGramPushLocalized("Не удалось подготовить токен регистрации", "Could not prepare the registration token")
            self.bump()
            return
        }
        let registration = beyGramRegisterWebPushToken(account: self.context.account, token: token, otherAccountUserIds: []) |> deliverOnMainQueue
        self.registrationDisposable.set(registration.start(next: { [weak self] registered in
            guard let strongSelf = self else {
                return
            }
            if var state = strongSelf.store.load() {
                state.telegramRegistered = registered
                strongSelf.store.save(state)
            }
            strongSelf.lastError = registered ? nil : beyGramPushLocalized("Telegram не принял регистрацию токена", "Telegram did not accept the token registration")
            strongSelf.bump()
        }))
    }

    private func disconnect() {
        self.stopPolling()
        guard let state = self.store.load() else {
            return
        }
        if state.telegramRegistered, let ingress = state.ingress, let token = ingress.registrationToken() {
            let unregistration = beyGramUnregisterWebPushToken(account: self.context.account, token: token, otherAccountUserIds: []) |> deliverOnMainQueue
            self.registrationDisposable.set(unregistration.start(completed: {}))
        }
        if let pollToken = state.pollToken {
            self.client.deleteInstallation(installationId: state.installationId, pollToken: pollToken) { _ in
            }
        }
        self.store.clear()
        self.lastError = nil
        self.bump()
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
        let entries = beyGramPushEntries(presentationData: presentationData, enabled: BeyGramSettings.shared.isEnabled(.bgPush), state: BeyGramPushStore.shared.load(), lastError: model.lastError)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    model.controller = controller
    return controller
}
