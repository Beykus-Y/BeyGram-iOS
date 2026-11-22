import Foundation

/// The server-side date of a stealth send made at server time `nowSeconds`: the chosen delay, but never less than
/// `BeyGramStealthSettings.minimumServerLeadSeconds`, because Telegram publishes a message due within 10 seconds at once.
public func beyGramStealthScheduleTime(nowSeconds: Int32, delaySeconds: Int32) -> Int32 {
    return nowSeconds + max(delaySeconds, BeyGramStealthSettings.minimumServerLeadSeconds)
}

/// A server-scheduled send that waits for its request: the delay the user chose, and the date the message is stored with.
public struct BeyGramStealthScheduledSend: Codable, Equatable {
    public let delaySeconds: Int32
    public let scheduleTime: Int32
    /// The server clock when the entry was last written.
    public let registeredAt: Int32

    public init(delaySeconds: Int32, scheduleTime: Int32, registeredAt: Int32) {
        self.delaySeconds = delaySeconds
        self.scheduleTime = scheduleTime
        self.registeredAt = registeredAt
    }
}

/// The server-scheduled sends that wait for their requests, per account and per message. TelegramCore reads an entry when the
/// request of its message is built (after the media upload) and sets the date from the delay then. The entries are kept in
/// UserDefaults under `beygram.stealth.schedules.<accountPeerId>`, so they survive a restart. Entries are dropped after a week.
public final class BeyGramStealthScheduleRegistry: @unchecked Sendable {
    public static let shared = BeyGramStealthScheduleRegistry(defaults: UserDefaults.standard)

    /// How long an entry is kept. A pending send is dispatched long before this; the bound only limits storage.
    public static let retentionSeconds: Int32 = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Records, or rewrites, the entry of `messageKey`: an opaque key that TelegramCore builds from the message id.
    /// `nowSeconds` is the server clock.
    public func register(accountPeerId: Int64, messageKey: String, delaySeconds: Int32, scheduleTime: Int32, nowSeconds: Int32) {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        var entries = BeyGramStealthScheduleRegistry.load(defaults: self.defaults, accountPeerId: accountPeerId)
        entries = entries.filter { nowSeconds - $0.value.registeredAt < BeyGramStealthScheduleRegistry.retentionSeconds }
        entries[messageKey] = BeyGramStealthScheduledSend(delaySeconds: delaySeconds, scheduleTime: scheduleTime, registeredAt: nowSeconds)
        if let data = try? JSONEncoder().encode(entries) {
            self.defaults.set(data, forKey: BeyGramStealthScheduleRegistry.storageKey(accountPeerId: accountPeerId))
        }
    }

    /// The entry of `messageKey`, or nil when that message is not a server-scheduled send that waits.
    public func scheduledSend(accountPeerId: Int64, messageKey: String) -> BeyGramStealthScheduledSend? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return BeyGramStealthScheduleRegistry.load(defaults: self.defaults, accountPeerId: accountPeerId)[messageKey]
    }

    private static func load(defaults: UserDefaults, accountPeerId: Int64) -> [String: BeyGramStealthScheduledSend] {
        guard let data = defaults.data(forKey: storageKey(accountPeerId: accountPeerId)), let entries = try? JSONDecoder().decode([String: BeyGramStealthScheduledSend].self, from: data) else {
            return [:]
        }
        return entries
    }

    private static func storageKey(accountPeerId: Int64) -> String {
        return "beygram.stealth.schedules.\(accountPeerId)"
    }
}
