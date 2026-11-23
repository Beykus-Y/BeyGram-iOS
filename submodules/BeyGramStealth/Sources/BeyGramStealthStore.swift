import Foundation

/// Stealth settings per account, kept in UserDefaults under `beygram.stealth.settings.<accountPeerId>`.
/// Reads are cached, because the hooks run on the send and typing paths.
public final class BeyGramStealthStore: @unchecked Sendable {
    public static let shared = BeyGramStealthStore(defaults: UserDefaults.standard)

    /// Posted after the settings of one account have changed. It is posted from the thread that made the change, after the
    /// store's lock is released. `userInfo[BeyGramStealthStore.accountPeerIdUserInfoKey]` holds the account's peer id as an
    /// `Int64`. Presence listens, so "hide online" applies at once and not at the next presence change.
    public static let didChangeNotification = Notification.Name("BeyGramStealthStore.didChange")
    public static let accountPeerIdUserInfoKey = "accountPeerId"

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
        let previous = self.cache[accountPeerId] ?? BeyGramStealthStore.load(defaults: self.defaults, accountPeerId: accountPeerId)
        var settings = previous
        transform(&settings)
        // A valid write clears the fail-closed state: the stored values are trusted again once they are rewritten.
        settings.failClosed = false
        self.cache[accountPeerId] = settings
        if let data = try? JSONEncoder().encode(settings) {
            self.defaults.set(data, forKey: BeyGramStealthStore.storageKey(accountPeerId: accountPeerId))
        }
        self.lock.unlock()
        // Posted after the unlock: an observer may read the settings at once without waiting on this lock.
        if settings != previous {
            NotificationCenter.default.post(name: BeyGramStealthStore.didChangeNotification, object: nil, userInfo: [BeyGramStealthStore.accountPeerIdUserInfoKey: accountPeerId])
        }
    }

    private static func storageKey(accountPeerId: Int64) -> String {
        return "beygram.stealth.settings.\(accountPeerId)"
    }

    private static func load(defaults: UserDefaults, accountPeerId: Int64) -> BeyGramStealthSettings {
        guard let data = defaults.data(forKey: BeyGramStealthStore.storageKey(accountPeerId: accountPeerId)) else {
            return BeyGramStealthSettings()
        }
        // Stored data that cannot be read may hide protection the user turned on, so everything stays refused until a valid
        // write (Android's StealthSettingsStore does the same).
        guard let settings = try? JSONDecoder().decode(BeyGramStealthSettings.self, from: data) else {
            return BeyGramStealthSettings.failClosedFallback
        }
        return settings
    }
}
