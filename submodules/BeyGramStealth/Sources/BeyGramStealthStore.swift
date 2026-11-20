import Foundation

/// Stealth settings per account, kept in UserDefaults under `beygram.stealth.settings.<accountPeerId>`.
/// Reads are cached, because the hooks run on the send and typing paths.
public final class BeyGramStealthStore: @unchecked Sendable {
    public static let shared = BeyGramStealthStore(defaults: UserDefaults.standard)

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cache: [Int64: BeyGramStealthSettings] = [:]

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func settings(accountPeerId: Int64) -> BeyGramStealthSettings {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if let cached = self.cache[accountPeerId] {
            return cached
        }
        let loaded = BeyGramStealthStore.load(defaults: self.defaults, accountPeerId: accountPeerId)
        self.cache[accountPeerId] = loaded
        return loaded
    }

    public func update(accountPeerId: Int64, _ transform: (inout BeyGramStealthSettings) -> Void) {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        var settings = self.cache[accountPeerId] ?? BeyGramStealthStore.load(defaults: self.defaults, accountPeerId: accountPeerId)
        transform(&settings)
        self.cache[accountPeerId] = settings
        if let data = try? JSONEncoder().encode(settings) {
            self.defaults.set(data, forKey: BeyGramStealthStore.storageKey(accountPeerId: accountPeerId))
        }
    }

    private static func storageKey(accountPeerId: Int64) -> String {
        return "beygram.stealth.settings.\(accountPeerId)"
    }

    private static func load(defaults: UserDefaults, accountPeerId: Int64) -> BeyGramStealthSettings {
        guard let data = defaults.data(forKey: BeyGramStealthStore.storageKey(accountPeerId: accountPeerId)), let settings = try? JSONDecoder().decode(BeyGramStealthSettings.self, from: data) else {
            return BeyGramStealthSettings()
        }
        return settings
    }
}
