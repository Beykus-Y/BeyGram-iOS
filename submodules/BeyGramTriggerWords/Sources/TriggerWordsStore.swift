import Foundation

/// Storage for trigger-word rules, scope and the mentions feed (contract: docs/trigger-words.md).
///
/// Pure logic over a key-value protocol: the app supplies a `UserDefaults`-backed implementation.
/// The rules are shared by all accounts; each mention records its account.
public enum TriggerWordScope: String, Codable {
    /// Only muted chats are checked. Telegram stays silent there, so a match gives an alert and a feed entry.
    case onlyMutedChats
    /// All chats are checked. Matches in unmuted chats give a feed entry only.
    case allChats
}

public protocol TriggerWordKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public struct TriggerWordMention: Codable, Equatable, Identifiable {
    public static let maxFeedEntries = 200

    public var id: String { "\(accountId):\(chatId):\(messageId)" }
    public var accountId: Int64
    public var chatId: Int64
    public var messageId: Int64
    public var messageDate: Date
    public var matchedPattern: String
    /// Nil when previews are off: the feed keeps no text for this match.
    public var text: String?
    public var senderName: String?

    public init(accountId: Int64, chatId: Int64, messageId: Int64, messageDate: Date, matchedPattern: String,
                text: String?, senderName: String?) {
        self.accountId = accountId
        self.chatId = chatId
        self.messageId = messageId
        self.messageDate = messageDate
        self.matchedPattern = matchedPattern
        self.text = text
        self.senderName = senderName
    }
}

public struct TriggerWordState: Codable, Equatable {
    public var rules: [TriggerWordRule] = []
    public var scope: TriggerWordScope = .onlyMutedChats
    public var mentions: [TriggerWordMention] = []
}

public final class TriggerWordsStore {
    private static let storageKey = "trigger_words"
    private let storage: TriggerWordKeyValueStore
    public private(set) var state: TriggerWordState

    public init(storage: TriggerWordKeyValueStore) {
        self.storage = storage
        if let data = storage.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(TriggerWordState.self, from: data) {
            state = decoded
        } else {
            state = TriggerWordState()
        }
    }

    public func setScope(_ scope: TriggerWordScope) {
        state.scope = scope
        save()
    }

    /// Adds or replaces a rule. Returns the validation error, if any, and saves nothing then.
    @discardableResult
    public func upsertRule(_ rule: TriggerWordRule) -> TriggerWordValidationError? {
        let existingIndex = state.rules.firstIndex { $0.id == rule.id }
        let otherCount = state.rules.count - (existingIndex == nil ? 0 : 1)
        if let error = TriggerWordMatcher.validate(rule, existingCount: otherCount) {
            return error
        }
        if let index = existingIndex {
            state.rules[index] = rule
        } else {
            state.rules.append(rule)
        }
        save()
        return nil
    }

    public func removeRule(id: UUID) {
        state.rules.removeAll { $0.id == id }
        save()
    }

    /// Records a match. A repeated update for the same message does not add a second entry.
    /// Keeps the newest 200 entries by message date, so an older catch-up cannot push out newer matches.
    public func recordMention(_ mention: TriggerWordMention) {
        guard !state.mentions.contains(where: { $0.id == mention.id }) else {
            return
        }
        state.mentions.append(mention)
        state.mentions.sort { $0.messageDate > $1.messageDate }
        if state.mentions.count > TriggerWordMention.maxFeedEntries {
            state.mentions.removeLast(state.mentions.count - TriggerWordMention.maxFeedEntries)
        }
        save()
    }

    /// Removes feed entries on this device only. Telegram messages are not changed.
    public func clearFeed() {
        state.mentions.removeAll()
        save()
    }

    /// Signing an account out removes its mentions. Rules and scope stay.
    public func removeMentions(accountId: Int64) {
        state.mentions.removeAll { $0.accountId == accountId }
        save()
    }

    /// Turning previews off removes the text of existing entries for that account.
    public func hideTextForAccount(_ accountId: Int64) {
        for index in state.mentions.indices where state.mentions[index].accountId == accountId {
            state.mentions[index].text = nil
            state.mentions[index].senderName = nil
        }
        save()
    }

    private func save() {
        storage.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
    }
}

/// `UserDefaults` adapter for `TriggerWordsStore`.
public final class UserDefaultsTriggerWordStorage: TriggerWordKeyValueStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

extension TriggerWordsStore {
    /// The app-wide store. Every screen and the update handler must share it, so the state stays in one place.
    public static let shared = TriggerWordsStore(storage: UserDefaultsTriggerWordStorage(defaults: .standard))
}
