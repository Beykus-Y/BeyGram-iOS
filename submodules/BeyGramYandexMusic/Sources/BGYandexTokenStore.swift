import Foundation
import Security

/// Session of the signed-in account. Kept in the Keychain, not in UserDefaults, and never logged.
/// The account fields were added later: tokens saved by an earlier build decode with them empty, and are filled once.
public struct BGYandexStoredTokens: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    /// Unix time, seconds, when the access token expires.
    public let expiresAt: TimeInterval
    /// Provider id of the account. Only used to build the account's paths; never shown.
    public let uid: String?
    public let displayName: String?
    public let hasPlus: Bool?

    public init(accessToken: String, refreshToken: String?, expiresAt: TimeInterval, uid: String? = nil, displayName: String? = nil, hasPlus: Bool? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.uid = uid
        self.displayName = displayName
        self.hasPlus = hasPlus
    }
}

public final class BGYandexTokenStore {
    private let service = "beygram.yandex.tokens"

    public init() {}

    private var baseQuery: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    @discardableResult
    public func save(_ tokens: BGYandexStoredTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else {
            return false
        }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public func load() -> BGYandexStoredTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(BGYandexStoredTokens.self, from: data)
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
