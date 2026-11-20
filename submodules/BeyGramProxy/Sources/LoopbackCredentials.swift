// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

import Foundation
import Security

/// The username and password that protect the loopback inlet. Every app on the device can reach 127.0.0.1,
/// so they are random per installation and stay in the Keychain.
public struct LoopbackCredentials: Codable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public enum LoopbackCredentialStore {
    public enum Failure: Error, Equatable {
        case randomness
        case keychain(OSStatus)
        case corrupted
    }

    private static let service = "org.beygram.mihomo.loopback"
    private static let account = "credentials"

    /// Returns this installation's credentials, creating them on first use.
    public static func loadOrCreate() throws -> LoopbackCredentials {
        if let existing = try load() {
            return existing
        }
        let username = try randomHex(byteCount: 12)
        let password = try randomHex(byteCount: 24)
        let created = LoopbackCredentials(username: username, password: password)
        let data = try JSONEncoder().encode(created)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Failure.keychain(status)
        }
        return created
    }

    private static func load() throws -> LoopbackCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw Failure.keychain(status)
        }
        guard let credentials = try? JSONDecoder().decode(LoopbackCredentials.self, from: data) else {
            throw Failure.corrupted
        }
        return credentials
    }

    private static func randomHex(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw Failure.randomness
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
