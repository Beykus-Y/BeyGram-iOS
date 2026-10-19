import Foundation
import TDLibKit
import UIKit

enum TelegramAuthPhase: Equatable {
    case missingConfiguration
    case initializing
    case phoneNumber
    case code
    case password
    case ready
    case actionRequired(String)
    case failed(String)
}

@MainActor
final class TelegramService: ObservableObject {
    @Published private(set) var phase: TelegramAuthPhase = .initializing
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var codeDeliveryInfo: TelegramCodeDeliveryInfo?

    let conversations = TelegramConversations()

    private let configuration: TelegramConfiguration?
    private var manager: TDLibClientManager?
    private var client: TDLibClient?
    private var sentParameters = false

    init(configuration: TelegramConfiguration? = TelegramConfiguration.load()) {
        self.configuration = configuration
        guard configuration != nil else {
            phase = .missingConfiguration
            return
        }

        let manager = TDLibClientManager()
        self.manager = manager
        self.client = manager.createClient(updateHandler: { [weak self] data, _ in
            Task { @MainActor [weak self] in
                self?.handleUpdate(data)
            }
        })
        if let client = self.client {
            conversations.bind(client: client)
        }
    }

    func submitPhone(_ phone: String) {
        guard phase == .phoneNumber, !isSubmitting else { return }
        let value = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("+"), value.count >= 8 else {
            errorMessage = "Введите номер с кодом страны, например +79991234567."
            return
        }
        perform(TelegramRequestFactory.make(SetAuthenticationPhoneNumber(phoneNumber: value, settings: nil)))
    }

    func submitCode(_ code: String) {
        guard phase == .code, !isSubmitting else { return }
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "Введите код, полученный от Telegram."
            return
        }
        perform(TelegramRequestFactory.make(CheckAuthenticationCode(code: value)))
    }

    func resendCode() {
        guard phase == .code, !isSubmitting,
              let info = codeDeliveryInfo, info.nextMethod != nil else { return }
        guard Date() >= info.resendAvailableAt else {
            errorMessage = "Повторный запрос пока не разрешён Telegram."
            return
        }
        perform(TelegramRequestFactory.make(ResendAuthenticationCode(reason: nil)))
    }

    func submitPassword(_ password: String) {
        guard phase == .password, !isSubmitting else { return }
        guard !password.isEmpty else {
            errorMessage = "Введите пароль двухэтапной аутентификации."
            return
        }
        perform(TelegramRequestFactory.make(CheckAuthenticationPassword(password: password)))
    }

    private func handleUpdate(_ data: Data) {
        conversations.handleUpdate(data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["@type"] as? String == "updateAuthorizationState",
              let state = object["authorization_state"] as? [String: Any],
              let stateType = state["@type"] as? String else {
            return
        }

        isSubmitting = false
        errorMessage = nil
        switch stateType {
        case "authorizationStateWaitTdlibParameters":
            configureTDLib()
        case "authorizationStateWaitPhoneNumber":
            codeDeliveryInfo = nil
            phase = .phoneNumber
        case "authorizationStateWaitCode":
            if let rawInfo = state["code_info"] as? [String: Any] {
                codeDeliveryInfo = TelegramCodeDeliveryInfo(raw: rawInfo)
            } else {
                codeDeliveryInfo = nil
            }
            phase = .code
        case "authorizationStateWaitPassword":
            codeDeliveryInfo = nil
            phase = .password
        case "authorizationStateReady":
            codeDeliveryInfo = nil
            phase = .ready
            conversations.start()
        case "authorizationStateWaitEmailAddress":
            phase = .actionRequired("Telegram требует адрес электронной почты. Этот шаг входа ещё не реализован.")
        case "authorizationStateWaitEmailCode":
            phase = .actionRequired("Telegram требует код с электронной почты. Этот шаг входа ещё не реализован.")
        case "authorizationStateWaitOtherDeviceConfirmation":
            phase = .actionRequired("Telegram ожидает подтверждение через другое устройство. QR-вход пока не реализован.")
        case "authorizationStateWaitRegistration":
            phase = .actionRequired("Аккаунт требует регистрацию и принятие условий Telegram. Этот шаг ещё не реализован.")
        case "authorizationStateWaitPremiumPurchase":
            phase = .actionRequired("Telegram требует дополнительную проверку Premium. Этот шаг ещё не реализован.")
        case "authorizationStateLoggingOut", "authorizationStateClosing":
            phase = .initializing
        case "authorizationStateClosed":
            phase = .failed("TDLib закрылась. Перезапустите приложение.")
        default:
            phase = .actionRequired("Telegram запросил неподдерживаемый шаг входа.")
        }
    }

    private func configureTDLib() {
        guard !sentParameters, let configuration else { return }
        sentParameters = true
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("BeyGram", isDirectory: true)

            let database = support.appendingPathComponent("tdlib", isDirectory: true)
            let files = support.appendingPathComponent("files", isDirectory: true)

            // Never create a fresh encryption key for a non-empty existing database.
            let existingKey = try TelegramKeyStore.existingKey()
            if existingKey == nil,
               FileManager.default.fileExists(atPath: database.path),
               !(try FileManager.default.contentsOfDirectory(atPath: database.path)).isEmpty {
                phase = .failed("База Telegram существует, но её ключ в Keychain отсутствует. Автоматический сброс запрещён.")
                return
            }

            let key = try existingKey ?? TelegramKeyStore.createKey()
            try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

            let parameters = SetTdlibParameters(
                apiHash: configuration.apiHash,
                apiId: configuration.apiID,
                applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
                databaseDirectory: database.path,
                databaseEncryptionKey: key,
                deviceModel: UIDevice.current.model,
                filesDirectory: files.path,
                systemLanguageCode: Locale.current.languageCode ?? "en",
                systemVersion: UIDevice.current.systemVersion,
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: false,
                useTestDc: false
            )
            let request = try TelegramRequestFactory.makeVerifiedParameters(parameters, expectedConfiguration: configuration)
            perform(request, displaySpinner: false)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func perform(_ query: TdQuery, displaySpinner: Bool = true) {
        guard let client else {
            phase = .failed("TDLib не инициализирована.")
            return
        }
        if displaySpinner {
            isSubmitting = true
        }
        errorMessage = nil
        do {
            try client.send(query: query, completion: { [weak self] data in
                Task { @MainActor [weak self] in
                    self?.handleResponse(data)
                }
            })
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }

    private func handleResponse(_ data: Data) {
        isSubmitting = false
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["@type"] as? String == "error" else {
            return
        }
        let message = response["message"] as? String ?? "Неизвестная ошибка Telegram."
        if sentParameters && phase == .initializing {
            phase = .failed(message)
        } else {
            errorMessage = message
        }
    }
}
