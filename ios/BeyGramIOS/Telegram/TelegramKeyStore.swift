import Foundation
import Security

/// Keeps the TDLib database key on-device. A lost key must not silently reset a previous database.
enum TelegramKeyStore {
    private static let service = "com.beykus.beygram.ios.tdlib"
    private static let account = "database-key-v1"

    enum KeyError: LocalizedError {
        case readFailed(OSStatus)
        case randomFailed(OSStatus)
        case writeFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .readFailed(let status):
                return "Не удалось получить ключ базы TDLib из Keychain (\(status))."
            case .randomFailed(let status):
                return "Не удалось создать ключ базы TDLib (\(status))."
            case .writeFailed(let status):
                return "Не удалось сохранить ключ базы TDLib (\(status))."
            }
        }
    }

    static func existingKey() throws -> Data? {
        var result: CFTypeRef?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else {
                throw KeyError.readFailed(errSecDecode)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeyError.readFailed(status)
        }
    }

    static func createKey() throws -> Data {
        if let key = try existingKey() {
            return key
        }

        var random = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
        guard randomStatus == errSecSuccess else {
            throw KeyError.randomFailed(randomStatus)
        }

        let key = Data(random)
        let entry: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: key
        ]
        let saveStatus = SecItemAdd(entry as CFDictionary, nil)
        if saveStatus == errSecDuplicateItem, let existing = try existingKey() {
            return existing
        }
        guard saveStatus == errSecSuccess else {
            throw KeyError.writeFailed(saveStatus)
        }
        return key
    }
}
