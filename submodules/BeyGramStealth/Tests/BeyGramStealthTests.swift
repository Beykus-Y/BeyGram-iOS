import Foundation
import XCTest
import BeyGramStealth

final class BeyGramStealthTests: XCTestCase {
    func testDefaultsChangeNothing() {
        let settings = BeyGramStealthSettings()
        XCTAssertTrue(settings.allows(.readHistory, chatPeerId: 1))
        XCTAssertTrue(settings.allows(.typing, chatPeerId: 1))
        XCTAssertTrue(settings.allows(.onlinePresence, chatPeerId: nil))
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, isSchedulable: true, nowSeconds: 1000), .unchanged)
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
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, isSchedulable: true, nowSeconds: 1000), .scheduled(1030))
    }

    func testDateChosenByTheUserIsLeftAlone() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 30)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: 5000, isSchedulable: false, nowSeconds: 1000), .unchanged)
    }

    func testUnschedulableSendIsRefusedNotSentAtOnce() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 30)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, isSchedulable: false, nowSeconds: 1000), .refused)
    }

    func testShortLeadIsRefused() {
        let settings = BeyGramStealthSettings(serverScheduledSend: true, scheduledSendDelaySeconds: 10)
        XCTAssertEqual(settings.sendDecision(explicitScheduleTime: nil, isSchedulable: true, nowSeconds: 1000), .refused)
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
}
