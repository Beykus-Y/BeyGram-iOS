import Foundation

/// Why BeyGram stealth sending refused a message. A refused message is stored as failed: it is never sent at once and never
/// dropped. The raw values are stored with the message, so they must not change.
public enum BeyGramStealthRefusal: String, Codable, Equatable, Sendable, CaseIterable {
    /// Telegram cannot schedule a message in a secret chat.
    case secretChat
    /// Telegram cannot schedule a paid message.
    case paidStars
    /// The chosen delay is below the lead that Telegram accepts for a scheduled send.
    case leadTooShort
    /// An ephemeral send takes another path, which does not carry the scheduled date.
    case ephemeral
    /// The scheduled date could not be recorded with the message, so it would have kept its enqueue-time date.
    case notRecorded

    /// The key of the dialog text for this reason. The UI adds the strings (see docs/stealth-ui-contract.md).
    public var localizationKey: String {
        switch self {
        case .secretChat:
            return "BeyGram.Stealth.Refusal.SecretChat"
        case .paidStars:
            return "BeyGram.Stealth.Refusal.PaidStars"
        case .leadTooShort:
            return "BeyGram.Stealth.Refusal.LeadTooShort"
        case .ephemeral:
            return "BeyGram.Stealth.Refusal.Ephemeral"
        case .notRecorded:
            return "BeyGram.Stealth.Refusal.NotRecorded"
        }
    }
}

/// The refusal reason of each failed message, per account, in UserDefaults under `beygram.stealth.refusals.<accountPeerId>`.
/// A message is keyed by its local id, which Postbox can reuse after a deletion, so an entry is only meaningful for a message
/// that is failed now. Entries are dropped after a week.
public final class BeyGramStealthRefusalRegistry: @unchecked Sendable {
    public static let shared = BeyGramStealthRefusalRegistry(defaults: UserDefaults.standard)

    /// How long an entry is kept.
    public static let retentionSeconds: Int32 = 7 * 24 * 60 * 60

    private struct Entry: Codable {
        let refusal: BeyGramStealthRefusal
        let registeredAt: Int32
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Records the reason of `messageKey`, an opaque key that TelegramCore builds from the message id. `nowSeconds` is the server clock.
    public func record(accountPeerId: Int64, messageKey: String, refusal: BeyGramStealthRefusal, nowSeconds: Int32) {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        var entries = BeyGramStealthRefusalRegistry.load(defaults: self.defaults, accountPeerId: accountPeerId)
        entries = entries.filter { nowSeconds - $0.value.registeredAt < BeyGramStealthRefusalRegistry.retentionSeconds }
        entries[messageKey] = Entry(refusal: refusal, registeredAt: nowSeconds)
        if let data = try? JSONEncoder().encode(entries) {
            self.defaults.set(data, forKey: BeyGramStealthRefusalRegistry.storageKey(accountPeerId: accountPeerId))
        }
    }

    /// The reason recorded for `messageKey`, or nil when stealth sending did not refuse that message.
    public func refusal(accountPeerId: Int64, messageKey: String) -> BeyGramStealthRefusal? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return BeyGramStealthRefusalRegistry.load(defaults: self.defaults, accountPeerId: accountPeerId)[messageKey]?.refusal
    }

    private static func load(defaults: UserDefaults, accountPeerId: Int64) -> [String: Entry] {
        guard let data = defaults.data(forKey: storageKey(accountPeerId: accountPeerId)), let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return entries
    }

    private static func storageKey(accountPeerId: Int64) -> String {
        return "beygram.stealth.refusals.\(accountPeerId)"
    }
}
