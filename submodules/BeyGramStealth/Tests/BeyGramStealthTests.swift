import Foundation
import XCTest
import BeyGramStealth

final class BeyGramStealthTests: XCTestCase {
    func testDefaultsChangeNothing() {
        let settings = BeyGramStealthSettings()
        XCTAssertTrue(settings.allows(.readHistory, chatPeerId: 1))
        XCTAssertTrue(settings.allows(.typing, chatPeerId: 1))
        XCTAssertTrue(settings.allows(.onlinePresence, chatPeerId: nil))
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: nil, nowSeconds: 1000), .unchanged)
    }

    func testAccountSwitchesHideOnlyTheirEffect() {
        let settings = BeyGramStealthSettings(hideReadReceipts: true)
        XCTAssertFalse(settings.allows(.readHistory, chatPeerId: 5))
        XCTAssertTrue(settings.allows(.typing, chatPeerId: 5))
        XCTAssertTrue(settings.allows(.onlinePresence, chatPeerId: nil))
    }

    func testChatOverridesApplyToReadAndTypingButNotToPresence() {
        let settings = BeyGramStealthSettings(hideReadReceipts: true, hideOnline: true, hideTyping: true, chatModes: ["42": .allow, "7": .block])
        XCTAssertTrue(settings.allows(.readHistory, chatPeerId: 42))
        XCTAssertTrue(settings.allows(.typing, chatPeerId: 42))
        XCTAssertFalse(settings.allows(.onlinePresence, chatPeerId: 42))
        XCTAssertFalse(settings.allows(.readHistory, chatPeerId: 43))
        XCTAssertFalse(settings.allows(.typing, chatPeerId: 43))
    }

    func testBlockOverrideHidesEffectsTheAccountAllows() {
        let settings = BeyGramStealthSettings(chatModes: ["7": .block])
        XCTAssertFalse(settings.allows(.typing, chatPeerId: 7))
        XCTAssertFalse(settings.allows(.readHistory, chatPeerId: 7))
        XCTAssertTrue(settings.allows(.typing, chatPeerId: 8))
        XCTAssertTrue(settings.allows(.typing, chatPeerId: nil))
    }

    func testScheduledSendLeadsFromNow() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 30)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: nil, nowSeconds: 1000), .scheduled(1030))
    }

    func testDateChosenByTheUserIsLeftAlone() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 30)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: 5000, unschedulableReason: .secretChat, nowSeconds: 1000), .unchanged)
    }

    func testSecretChatIsRefusedAndNamesItsReason() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 30)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: .secretChat, nowSeconds: 1000), .refused(.secretChat))
    }

    func testPaidMessageIsRefusedAndNamesItsReason() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 30)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: .paidStars, nowSeconds: 1000), .refused(.paidStars))
    }

    func testViewOnceAndDirectMessagesAreRefusedAndNameTheirReason() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 30)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: .viewOnceOrLiveLocation, nowSeconds: 1000), .refused(.viewOnceOrLiveLocation))
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: .directMessages, nowSeconds: 1000), .refused(.directMessages))
        // The raw values are stored with refused messages, so they must not change.
        XCTAssertEqual(BeyGramStealthRefusal.viewOnceOrLiveLocation.rawValue, "viewOnceOrLiveLocation")
        XCTAssertEqual(BeyGramStealthRefusal.directMessages.rawValue, "directMessages")
    }

    func testShortLeadIsRefusedAndNamesItsReason() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 10)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: nil, nowSeconds: 1000), .refused(.leadTooShort))
    }

    func testEveryRefusalHasItsOwnLocalizationKey() {
        let keys = BeyGramStealthRefusal.allCases.map { $0.localizationKey }
        XCTAssertEqual(Set(keys).count, BeyGramStealthRefusal.allCases.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("BeyGram.Stealth.Refusal.") })
    }

    func testSettingsSurviveEncoding() throws {
        let settings = BeyGramStealthSettings(hideReadReceipts: true, serverScheduledSend: true, scheduledSendDelaySeconds: 60, chatModes: ["9": .allow])
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(BeyGramStealthSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    private func temporaryDefaults() throws -> (defaults: UserDefaults, suite: String) {
        let suite = "BeyGramStealthTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    func testScheduleTimeNeverLeadsLessThanTheMinimum() {
        XCTAssertEqual(beyGramStealthScheduleTime(nowSeconds: 1000, delaySeconds: 5), 1000 + BeyGramStealthSettings.minimumServerLeadSeconds)
        XCTAssertEqual(beyGramStealthScheduleTime(nowSeconds: 1000, delaySeconds: 60), 1060)
    }

    func testScheduleRegistryKeepsEachAccountsEntriesAcrossARestart() throws {
        let (defaults, suite) = try temporaryDefaults()
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        BeyGramStealthScheduleRegistry(defaults: defaults).register(accountPeerId: 1, messageKey: "a", delaySeconds: 60, scheduleTime: 1060, nowSeconds: 1000)
        let restarted = BeyGramStealthScheduleRegistry(defaults: defaults)
        XCTAssertEqual(restarted.scheduledSend(accountPeerId: 1, messageKey: "a"), BeyGramStealthScheduledSend(delaySeconds: 60, scheduleTime: 1060, registeredAt: 1000))
        XCTAssertNil(restarted.scheduledSend(accountPeerId: 2, messageKey: "a"))
        XCTAssertNil(restarted.scheduledSend(accountPeerId: 1, messageKey: "b"))
    }

    func testScheduleRegistryHoldsTheDateItWasRewrittenWith() throws {
        let (defaults, suite) = try temporaryDefaults()
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let registry = BeyGramStealthScheduleRegistry(defaults: defaults)
        registry.register(accountPeerId: 1, messageKey: "a", delaySeconds: 60, scheduleTime: 1060, nowSeconds: 1000)
        registry.register(accountPeerId: 1, messageKey: "a", delaySeconds: 60, scheduleTime: 1100, nowSeconds: 1040)
        XCTAssertEqual(registry.scheduledSend(accountPeerId: 1, messageKey: "a"), BeyGramStealthScheduledSend(delaySeconds: 60, scheduleTime: 1100, registeredAt: 1040))
    }

    func testScheduleRegistryDropsEntriesOlderThanTheRetention() throws {
        let (defaults, suite) = try temporaryDefaults()
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let registry = BeyGramStealthScheduleRegistry(defaults: defaults)
        let later = 1000 + BeyGramStealthScheduleRegistry.retentionSeconds + 1
        registry.register(accountPeerId: 1, messageKey: "old", delaySeconds: 30, scheduleTime: 1030, nowSeconds: 1000)
        registry.register(accountPeerId: 1, messageKey: "new", delaySeconds: 30, scheduleTime: later + 30, nowSeconds: later)
        XCTAssertNil(registry.scheduledSend(accountPeerId: 1, messageKey: "old"))
        XCTAssertNotNil(registry.scheduledSend(accountPeerId: 1, messageKey: "new"))
    }

    func testRefusalRegistryKeepsEachAccountsReasonsAcrossARestart() throws {
        let (defaults, suite) = try temporaryDefaults()
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        BeyGramStealthRefusalRegistry(defaults: defaults).record(accountPeerId: 1, messageKey: "a", refusal: .paidStars, nowSeconds: 1000)
        let restarted = BeyGramStealthRefusalRegistry(defaults: defaults)
        XCTAssertEqual(restarted.refusal(accountPeerId: 1, messageKey: "a"), BeyGramStealthRefusal.paidStars)
        XCTAssertNil(restarted.refusal(accountPeerId: 2, messageKey: "a"))
        XCTAssertNil(restarted.refusal(accountPeerId: 1, messageKey: "b"))
    }

    func testRefusalRegistryKeepsTheLatestReason() throws {
        let (defaults, suite) = try temporaryDefaults()
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let registry = BeyGramStealthRefusalRegistry(defaults: defaults)
        registry.record(accountPeerId: 1, messageKey: "a", refusal: .paidStars, nowSeconds: 1000)
        registry.record(accountPeerId: 1, messageKey: "a", refusal: .notRecorded, nowSeconds: 1010)
        XCTAssertEqual(registry.refusal(accountPeerId: 1, messageKey: "a"), BeyGramStealthRefusal.notRecorded)
    }

    func testStoryViewSwitchHidesOnlyStoryViews() {
        let settings = BeyGramStealthSettings(noStoryViews: true)
        XCTAssertFalse(settings.allows(.storyView, chatPeerId: 5))
        XCTAssertTrue(settings.allows(.readHistory, chatPeerId: 5))
        XCTAssertTrue(settings.allows(.onlinePresence, chatPeerId: nil))
        let allowed = BeyGramStealthSettings(chatModes: ["5": .allow], noStoryViews: true)
        XCTAssertTrue(allowed.allows(.storyView, chatPeerId: 5))
        XCTAssertFalse(allowed.allows(.storyView, chatPeerId: 6))
    }

    func testSettingsWrittenBeforeAKeyExistedKeepTheirValues() throws {
        // The JSON an earlier build wrote has no story-view key. Decoding must keep what the user had chosen.
        let stored = #"{"no_read_receipts":true,"hide_online":true,"hide_typing":false,"scheduled_send":false,"scheduled_send_delay":15,"chats":{}}"#
        let decoded = try JSONDecoder().decode(BeyGramStealthSettings.self, from: Data(stored.utf8))
        XCTAssertTrue(decoded.hideReadReceipts)
        XCTAssertTrue(decoded.hideOnline)
        XCTAssertFalse(decoded.noStoryViews)
        XCTAssertFalse(decoded.failClosed)
    }

    func testFailClosedRefusesEveryEffectAndSchedulesEverySend() {
        let settings = BeyGramStealthSettings.failClosedFallback
        XCTAssertFalse(settings.allows(.readHistory, chatPeerId: 1))
        XCTAssertFalse(settings.allows(.typing, chatPeerId: 1))
        XCTAssertFalse(settings.allows(.storyView, chatPeerId: 1))
        XCTAssertFalse(settings.allows(.onlinePresence, chatPeerId: nil))
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: nil, nowSeconds: 1000), .scheduled(1015))
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, unschedulableReason: .secretChat, nowSeconds: 1000), .refused(.secretChat))
        // A chat exception does not lift a fail-closed refusal, as on Android.
        let excepted = BeyGramStealthSettings(chatModes: ["1": .allow], failClosed: true)
        XCTAssertFalse(excepted.allows(.typing, chatPeerId: 1))
    }

    func testUnreadableStoredSettingsFailClosedUntilTheNextValidWrite() throws {
        let (defaults, suite) = try temporaryDefaults()
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(Data("not json".utf8), forKey: "beygram.stealth.settings.1")
        let store = BeyGramStealthStore(defaults: defaults)
        XCTAssertTrue(store.settings(accountPeerId: 1).failClosed)
        XCTAssertFalse(store.settings(accountPeerId: 1).allows(.typing, chatPeerId: nil))
        XCTAssertFalse(store.settings(accountPeerId: 2).failClosed)
        store.update(accountPeerId: 1) { $0.hideTyping = false }
        XCTAssertFalse(store.settings(accountPeerId: 1).failClosed)
        XCTAssertTrue(store.settings(accountPeerId: 1).allows(.typing, chatPeerId: nil))
    }
}
