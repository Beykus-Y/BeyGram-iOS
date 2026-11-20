import Foundation
import Security

// Секреты BG Push лежат в Keychain, а не в UserDefaults. Bearer владельца даёт право опрашивать и отзывать регистрацию,
// ingress-адрес содержит capability, а ссылка установки содержит одноразовый код привязки.
// Keychain переживает переустановку приложения, UserDefaults нет, поэтому контроллер сверяет registrationId
// с BeyGramPushState и сбрасывает секреты, которые не относятся к сохранённой регистрации.

/// Секреты одной регистрации.
public struct BeyGramPushSecrets: Codable, Equatable {
    /// Регистрация, к которой относятся секреты.
    public var registrationId: String
    /// Bearer владельца: нужен для опроса, подтверждения и отзыва.
    public var bearer: String
    /// Адрес ingress (содержит capability). Сервер отдаёт его один раз, при создании.
    public var ingressUrl: String
    /// Ссылка установки PWA. Нужна, пока регистрация pending.
    public var setupUrl: String
    /// Ключи Telegram, как только сервер их отдал.
    public var telegramKeys: BeyGramPushTelegramKeys?

    public init(registrationId: String, bearer: String, ingressUrl: String, setupUrl: String, telegramKeys: BeyGramPushTelegramKeys?) {
        self.registrationId = registrationId
        self.bearer = bearer
        self.ingressUrl = ingressUrl
        self.setupUrl = setupUrl
        self.telegramKeys = telegramKeys
    }
}

/// Хранилище секретов BG Push в Keychain: один элемент на установку.
public final class BeyGramPushSecretStore {
    public static let shared = BeyGramPushSecretStore(service: "beygram.push.secrets")

    private let service: String

    public init(service: String) {
        self.service = service
    }

    private func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: "registration",
        ]
    }

    public func load() -> BeyGramPushSecrets? {
        var query = self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(BeyGramPushSecrets.self, from: data)
    }

    /// Заменяет сохранённые секреты. Возвращает false, если Keychain отказал.
    @discardableResult
    public func save(_ secrets: BeyGramPushSecrets) -> Bool {
        guard let data = try? JSONEncoder().encode(secrets) else {
            return false
        }
        self.clear()
        var insert = self.baseQuery()
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    public func clear() {
        _ = SecItemDelete(self.baseQuery() as CFDictionary)
    }
}
