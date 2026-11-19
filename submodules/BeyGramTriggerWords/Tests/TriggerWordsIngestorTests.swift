import XCTest
@testable import BeyGramTriggerWords

private final class MemoryStorage: TriggerWordKeyValueStore {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
}

final class TriggerWordsIngestorTests: XCTestCase {
    func testIngestRecordsOneMentionAndKeepsTextWhenPreviewsOn() {
        let store = TriggerWordsStore(storage: MemoryStorage())
        _ = store.upsertRule(TriggerWordRule(pattern: "тест"))
        let now = Date(timeIntervalSince1970: 10_000)
        let message = TriggerWordIncomingMessage(accountId: 1, chatId: 2, messageId: 3, messageDate: now, text: "это тест",
                                                 senderName: "Ann", isChatMuted: true, isChatOpenOnScreen: false, isProtectedContent: false)
        let account = TriggerWordAccountSettings(notificationsEnabled: true, backgroundEnabled: true, previewsEnabled: true, chatPreviewsEnabled: true)
        let decision = TriggerWordsIngestor.ingest(message, store: store, account: account, now: now)
        XCTAssertEqual(decision?.postAlert, true)
        XCTAssertEqual(store.state.mentions.count, 1)
        XCTAssertEqual(store.state.mentions.first?.text, "это тест")
    }

    func testIngestDropsTextWhenProtected() {
        let store = TriggerWordsStore(storage: MemoryStorage())
        _ = store.upsertRule(TriggerWordRule(pattern: "тест"))
        let now = Date(timeIntervalSince1970: 10_000)
        let message = TriggerWordIncomingMessage(accountId: 1, chatId: 2, messageId: 3, messageDate: now, text: "тест",
                                                 senderName: "Ann", isChatMuted: true, isChatOpenOnScreen: false, isProtectedContent: true)
        let account = TriggerWordAccountSettings(notificationsEnabled: true, backgroundEnabled: true, previewsEnabled: true, chatPreviewsEnabled: true)
        _ = TriggerWordsIngestor.ingest(message, store: store, account: account, now: now)
        XCTAssertNil(store.state.mentions.first?.text)
    }

    func testIngestIgnoresMessageWithNoMatch() {
        let store = TriggerWordsStore(storage: MemoryStorage())
        _ = store.upsertRule(TriggerWordRule(pattern: "тест"))
        let now = Date(timeIntervalSince1970: 10_000)
        let message = TriggerWordIncomingMessage(accountId: 1, chatId: 2, messageId: 3, messageDate: now, text: "hello",
                                                 senderName: "Ann", isChatMuted: true, isChatOpenOnScreen: false, isProtectedContent: false)
        let account = TriggerWordAccountSettings(notificationsEnabled: true, backgroundEnabled: true, previewsEnabled: true, chatPreviewsEnabled: true)
        XCTAssertNil(TriggerWordsIngestor.ingest(message, store: store, account: account, now: now))
        XCTAssertTrue(store.state.mentions.isEmpty)
    }
}
