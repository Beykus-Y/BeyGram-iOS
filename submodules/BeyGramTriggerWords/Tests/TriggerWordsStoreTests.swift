import XCTest
@testable import BeyGramTriggerWords

private final class MemoryKeyValueStore: TriggerWordKeyValueStore {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
}

final class TriggerWordsStoreTests: XCTestCase {
    private func mention(account: Int64 = 1, message: Int64, date: TimeInterval = 0) -> TriggerWordMention {
        TriggerWordMention(accountId: account, chatId: 7, messageId: message, messageDate: Date(timeIntervalSince1970: date),
                           matchedPattern: "тест", text: "текст", senderName: "Ann")
    }

    func testRulesPersistAcrossInstances() {
        let kv = MemoryKeyValueStore()
        let store = TriggerWordsStore(storage: kv)
        XCTAssertNil(store.upsertRule(TriggerWordRule(pattern: "тест")))
        XCTAssertEqual(TriggerWordsStore(storage: kv).state.rules.map { $0.pattern }, ["тест"])
    }

    func testInvalidRuleIsNotSaved() {
        let store = TriggerWordsStore(storage: MemoryKeyValueStore())
        XCTAssertEqual(store.upsertRule(TriggerWordRule(pattern: " ")), .emptyPattern)
        XCTAssertTrue(store.state.rules.isEmpty)
    }

    func testDuplicateMessageIsRecordedOnce() {
        let store = TriggerWordsStore(storage: MemoryKeyValueStore())
        store.recordMention(mention(message: 5))
        store.recordMention(mention(message: 5))
        XCTAssertEqual(store.state.mentions.count, 1)
    }

    func testFeedKeepsNewestTwoHundredByDate() {
        let store = TriggerWordsStore(storage: MemoryKeyValueStore())
        for index in 0 ..< 250 {
            store.recordMention(mention(message: Int64(index), date: TimeInterval(index)))
        }
        XCTAssertEqual(store.state.mentions.count, TriggerWordMention.maxFeedEntries)
        XCTAssertEqual(store.state.mentions.first?.messageId, 249)
        XCTAssertEqual(store.state.mentions.last?.messageId, 50)
    }

    func testSignOutRemovesOnlyThatAccountsMentions() {
        let store = TriggerWordsStore(storage: MemoryKeyValueStore())
        store.recordMention(mention(account: 1, message: 1))
        store.recordMention(mention(account: 2, message: 2))
        store.removeMentions(accountId: 1)
        XCTAssertEqual(store.state.mentions.map { $0.accountId }, [2])
    }

    func testPreviewsOffHidesTextOfExistingEntries() {
        let store = TriggerWordsStore(storage: MemoryKeyValueStore())
        store.recordMention(mention(account: 1, message: 1))
        store.hideTextForAccount(1)
        XCTAssertNil(store.state.mentions.first?.text)
    }

    func testPolicyAlertsForMutedChatWithText() {
        let now = Date(timeIntervalSince1970: 10_000)
        let message = TriggerWordIncomingMessage(accountId: 1, chatId: 1, messageId: 1, messageDate: now, text: "это тест",
                                                 senderName: "Ann", isChatMuted: true, isChatOpenOnScreen: false, isProtectedContent: false)
        let account = TriggerWordAccountSettings(notificationsEnabled: true, backgroundEnabled: true, previewsEnabled: true, chatPreviewsEnabled: true)
        let decision = TriggerWordAlertPolicy.decide(message: message, rules: [TriggerWordRule(pattern: "тест")],
                                                     scope: .onlyMutedChats, account: account, now: now)
        XCTAssertEqual(decision?.postAlert, true)
        XCTAssertEqual(decision?.alertShowsText, true)
    }

    func testPolicySkipsUnmutedChatInMutedOnlyScope() {
        let now = Date(timeIntervalSince1970: 10_000)
        let message = TriggerWordIncomingMessage(accountId: 1, chatId: 1, messageId: 1, messageDate: now, text: "тест",
                                                 senderName: "Ann", isChatMuted: false, isChatOpenOnScreen: false, isProtectedContent: false)
        let account = TriggerWordAccountSettings(notificationsEnabled: true, backgroundEnabled: true, previewsEnabled: true, chatPreviewsEnabled: true)
        XCTAssertNil(TriggerWordAlertPolicy.decide(message: message, rules: [TriggerWordRule(pattern: "тест")],
                                                   scope: .onlyMutedChats, account: account, now: now))
    }

    func testPolicyRecordsUnmutedMatchWithoutAlertInAllChatsScope() {
        let now = Date(timeIntervalSince1970: 10_000)
        let message = TriggerWordIncomingMessage(accountId: 1, chatId: 1, messageId: 1, messageDate: now, text: "тест",
                                                 senderName: "Ann", isChatMuted: false, isChatOpenOnScreen: false, isProtectedContent: false)
        let account = TriggerWordAccountSettings(notificationsEnabled: true, backgroundEnabled: true, previewsEnabled: true, chatPreviewsEnabled: true)
        let decision = TriggerWordAlertPolicy.decide(message: message, rules: [TriggerWordRule(pattern: "тест")],
                                                     scope: .allChats, account: account, now: now)
        XCTAssertEqual(decision?.postAlert, false)
        XCTAssertEqual(decision?.feedKeepsText, true)
    }

    func testPolicyNamesOnlyWordWhenPreviewsOff() {
        let now = Date(timeIntervalSince1970: 10_000)
        let message = TriggerWordIncomingMessage(accountId: 1, chatId: 1, messageId: 1, messageDate: now, text: "тест",
                                                 senderName: "Ann", isChatMuted: true, isChatOpenOnScreen: false, isProtectedContent: false)
        let account = TriggerWordAccountSettings(notificationsEnabled: true, backgroundEnabled: true, previewsEnabled: false, chatPreviewsEnabled: true)
        let decision = TriggerWordAlertPolicy.decide(message: message, rules: [TriggerWordRule(pattern: "тест")],
                                                     scope: .onlyMutedChats, account: account, now: now)
        XCTAssertEqual(decision?.postAlert, true)
        XCTAssertEqual(decision?.alertShowsText, false)
        XCTAssertEqual(decision?.feedKeepsText, false)
    }

    func testPolicyNoAlertForOldMessage() {
        let now = Date(timeIntervalSince1970: 10_000)
        let message = TriggerWordIncomingMessage(accountId: 1, chatId: 1, messageId: 1, messageDate: now.addingTimeInterval(-601), text: "тест",
                                                 senderName: "Ann", isChatMuted: true, isChatOpenOnScreen: false, isProtectedContent: false)
        let account = TriggerWordAccountSettings(notificationsEnabled: true, backgroundEnabled: true, previewsEnabled: true, chatPreviewsEnabled: true)
        let decision = TriggerWordAlertPolicy.decide(message: message, rules: [TriggerWordRule(pattern: "тест")],
                                                     scope: .onlyMutedChats, account: account, now: now)
        XCTAssertEqual(decision?.postAlert, false)
    }

    func testUnknownRuleModeIsDroppedWithoutLosingValidRules() throws {
        let kv = InMemoryKV()
        let json = """
        {
          "rules": [
            {"id":"11111111-1111-1111-1111-111111111111","pattern":"hello","mode":"wholeWord","ignoreCase":true,"ignoreDiacritics":false,"isEnabled":true},
            {"id":"22222222-2222-2222-2222-222222222222","pattern":"future","mode":"unknownFutureMode","ignoreCase":true,"ignoreDiacritics":false,"isEnabled":true},
            {"id":"33333333-3333-3333-3333-333333333333","pattern":"\\\\btest\\\\b","mode":"regex","ignoreCase":true,"ignoreDiacritics":false,"isEnabled":true}
          ],
          "scope": "allChats",
          "mentions": []
        }
        """
        kv.set(Data(json.utf8), forKey: "trigger_words")
        let store = TriggerWordsStore(storage: kv)
        XCTAssertEqual(store.state.scope, .allChats)
        XCTAssertEqual(store.state.rules.count, 2)
        XCTAssertEqual(store.state.rules.map(\.mode), [.wholeWord, .regex])
    }
}
