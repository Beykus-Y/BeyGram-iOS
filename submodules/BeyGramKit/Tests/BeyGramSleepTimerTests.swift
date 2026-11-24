import XCTest
@testable import BeyGramKit

final class BeyGramSleepTimerTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000)

    private func makeTimer(account: Int64 = 1) -> (BeyGramSleepTimer, () -> Int) {
        let timer = BeyGramSleepTimer(accountId: account, now: { self.clock })
        var fired = 0
        timer.onFire = { fired += 1 }
        return (timer, { fired })
    }

    func testMinutesTimerFiresAtDeadlineOnly() {
        let (timer, fired) = makeTimer()
        timer.setMinutes(10)
        clock = clock.addingTimeInterval(599)
        timer.tick()
        XCTAssertEqual(fired(), 0)
        XCTAssertEqual(timer.remainingSeconds, 1)
        clock = clock.addingTimeInterval(1)
        timer.tick()
        XCTAssertEqual(fired(), 1)
        XCTAssertEqual(timer.state, .off)
        timer.tick()
        XCTAssertEqual(fired(), 1)
    }

    func testExtendAddsToRunningTimer() {
        let (timer, fired) = makeTimer()
        timer.setMinutes(5)
        clock = clock.addingTimeInterval(240)
        timer.extend(minutes: 15)
        XCTAssertEqual(timer.remainingSeconds, 60 + 900)
        clock = clock.addingTimeInterval(959)
        timer.tick()
        XCTAssertEqual(fired(), 0)
        clock = clock.addingTimeInterval(1)
        timer.tick()
        XCTAssertEqual(fired(), 1)
    }

    func testExtendWithoutTimerStartsOne() {
        let (timer, _) = makeTimer()
        timer.extend()
        XCTAssertEqual(timer.remainingSeconds, TimeInterval(BeyGramSleepTimer.extensionMinutes * 60))
    }

    func testUntilTrackEndSurvivesTrackChangeButFiresOnItsTrackEnd() {
        let (timer, fired) = makeTimer()
        timer.trackChanged(to: "a")
        timer.setUntilTrackEnd()
        timer.trackEnded(trackId: "b")
        XCTAssertEqual(fired(), 0)
        timer.trackEnded(trackId: "a")
        XCTAssertEqual(fired(), 1)
        XCTAssertFalse(timer.isActive)
    }

    func testUntilTrackEndWithoutKnownTrackAdoptsTheNextOne() {
        let (timer, fired) = makeTimer()
        timer.setUntilTrackEnd()
        timer.trackChanged(to: "a")
        timer.trackEnded(trackId: "x")
        XCTAssertEqual(fired(), 0)
        timer.trackEnded(trackId: "a")
        XCTAssertEqual(fired(), 1)
    }

    func testAccountChangeCancelsTimerOfOtherAccount() {
        let (timer, fired) = makeTimer(account: 1)
        timer.setMinutes(5)
        timer.accountChanged(to: 1)
        XCTAssertTrue(timer.isActive)
        timer.accountChanged(to: 2)
        XCTAssertFalse(timer.isActive)
        clock = clock.addingTimeInterval(10_000)
        timer.tick()
        XCTAssertEqual(fired(), 0)
    }

    func testCancelAndZeroMinutes() {
        let (timer, fired) = makeTimer()
        timer.setMinutes(5)
        timer.setMinutes(0)
        XCTAssertEqual(timer.state, .off)
        timer.setUntilTrackEnd()
        timer.cancel()
        timer.trackEnded(trackId: nil)
        XCTAssertEqual(fired(), 0)
    }

    func testOnChangeReportsOnlyRealChanges() {
        let (timer, _) = makeTimer()
        var changes = 0
        timer.onChange = { _ in changes += 1 }
        timer.cancel()
        XCTAssertEqual(changes, 0)
        timer.setMinutes(5)
        XCTAssertEqual(changes, 1)
    }
}
