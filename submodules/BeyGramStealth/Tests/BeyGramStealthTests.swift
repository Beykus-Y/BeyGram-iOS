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
}
