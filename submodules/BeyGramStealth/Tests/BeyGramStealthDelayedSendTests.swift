import Foundation
import XCTest
import BeyGramStealth

final class BeyGramStealthDelayedSendTests: XCTestCase {
    private let start: Int64 = 1_000_000_000_000

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BeyGramStealthDelayedSendTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeDirectory(_ directory: URL) {
        _ = try? FileManager.default.removeItem(at: directory)
    }

    private func makeQueue(_ directory: URL, accountPeerId: Int64 = 1, hideOnline: Bool = false, nowMillis: Int64) -> BeyGramStealthDelayedSendQueue {
        return BeyGramStealthDelayedSendQueue(directory: directory, accountPeerId: accountPeerId, hideOnline: hideOnline, nowMillis: nowMillis)
    }

    func testAQueuedMessageSurvivesARestart() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "hello", delaySeconds: 30, nowMillis: start)
        let restarted = makeQueue(directory, nowMillis: start + 1_000)
        XCTAssertEqual(restarted.entries(), [entry])
    }

    func testAMessageWaitsForItsDelay() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        _ = try queue.enqueue(chatPeerId: 42, text: "later", delaySeconds: 30, nowMillis: start)
        XCTAssertTrue(queue.dueEntries(nowMillis: start + 29_999).isEmpty)
        XCTAssertEqual(queue.dueEntries(nowMillis: start + 30_000).map { $0.text }, ["later"])
    }

    func testCancelReturnsTheTextOfAQueuedMessage() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "draft", delaySeconds: 30, nowMillis: start)
        XCTAssertEqual(try queue.cancel(id: entry.id), entry)
        XCTAssertTrue(queue.entries().isEmpty)
    }

    func testAMessageInFlightCannotBeCancelledOrEdited() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "sending", delaySeconds: 15, nowMillis: start)
        XCTAssertTrue(try queue.markDispatching(id: entry.id, nowMillis: start + 15_000))
        XCTAssertNil(try queue.cancel(id: entry.id))
        XCTAssertFalse(try queue.edit(id: entry.id, text: "changed"))
        XCTAssertEqual(queue.entries().first?.status, BeyGramStealthDelayedStatus.dispatching)
    }

    func testEditChangesTheTextAndKeepsTheDueTime() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "first", delaySeconds: 30, nowMillis: start)
        XCTAssertTrue(try queue.edit(id: entry.id, text: "second"))
        let edited = try XCTUnwrap(queue.entries().first)
        XCTAssertEqual(edited.text, "second")
        XCTAssertEqual(edited.notBeforeMillis, start + 30_000)
    }

    func testSendNowReleasesAQueuedMessageBeforeItsTime() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "now", delaySeconds: 120, nowMillis: start)
        XCTAssertTrue(try queue.sendNow(id: entry.id, nowMillis: start + 5_000))
        let due = queue.dueEntries(nowMillis: start + 5_000)
        XCTAssertEqual(due.map { $0.id }, [entry.id])
        XCTAssertEqual(due.first?.sendNowConsented, true)
    }

    func testSendNowSendsAFailedMessageAgain() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "retry", delaySeconds: 15, nowMillis: start)
        XCTAssertTrue(try queue.markDispatching(id: entry.id, nowMillis: start + 15_000))
        XCTAssertTrue(try queue.markFailed(id: entry.id, failure: .network))
        XCTAssertEqual(queue.entries().first?.status, BeyGramStealthDelayedStatus.failed)
        XCTAssertEqual(queue.entries().first?.failure, BeyGramStealthDelayedFailure.network)
        XCTAssertTrue(try queue.sendNow(id: entry.id, nowMillis: start + 20_000))
        XCTAssertEqual(queue.entries().first?.status, BeyGramStealthDelayedStatus.queued)
        XCTAssertNil(queue.entries().first?.failure)
        XCTAssertEqual(queue.dueEntries(nowMillis: start + 20_000).map { $0.id }, [entry.id])
    }

    func testARestartTurnsAnInFlightMessageIntoUncertainAndNeverResendsIt() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "maybe sent", delaySeconds: 15, nowMillis: start)
        XCTAssertTrue(try queue.markDispatching(id: entry.id, nowMillis: start + 15_000))
        let restarted = makeQueue(directory, nowMillis: start + 16_000)
        XCTAssertEqual(restarted.entries().first?.status, BeyGramStealthDelayedStatus.uncertain)
        XCTAssertTrue(restarted.dueEntries(nowMillis: start + 10_000_000).isEmpty)
    }

    func testHideOnlineHoldsAMessageDueAtStartUntilTheUserSendsIt() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "held", delaySeconds: 10, nowMillis: start)
        let restarted = makeQueue(directory, hideOnline: true, nowMillis: start + 60_000)
        XCTAssertEqual(restarted.heldAtLoad(), [entry.id])
        XCTAssertTrue(restarted.dueEntries(nowMillis: start + 60_000).isEmpty)
        XCTAssertTrue(try restarted.sendNow(id: entry.id, nowMillis: start + 60_000))
        XCTAssertEqual(restarted.dueEntries(nowMillis: start + 60_000).map { $0.id }, [entry.id])
        XCTAssertTrue(restarted.heldAtLoad().isEmpty)
    }

    func testWithoutHideOnlineADueMessageIsDueAfterARestart() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "not held", delaySeconds: 10, nowMillis: start)
        let restarted = makeQueue(directory, hideOnline: false, nowMillis: start + 60_000)
        XCTAssertTrue(restarted.heldAtLoad().isEmpty)
        XCTAssertEqual(restarted.dueEntries(nowMillis: start + 60_000).map { $0.id }, [entry.id])
    }

    func testAMessageOlderThanTheRetentionExpiresAndKeepsItsText() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "keep me", delaySeconds: 15, nowMillis: start)
        let later = start + BeyGramStealthDelayedSendQueue.retentionMillis + 1
        let restarted = makeQueue(directory, nowMillis: later)
        XCTAssertEqual(restarted.entries().first?.status, BeyGramStealthDelayedStatus.failed)
        XCTAssertEqual(restarted.entries().first?.failure, BeyGramStealthDelayedFailure.expired)
        XCTAssertEqual(restarted.entries().first?.text, entry.text)
        XCTAssertTrue(restarted.dueEntries(nowMillis: later).isEmpty)
    }

    func testAWallClockJumpBackBringsTheDueTimeForward() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        _ = try queue.enqueue(chatPeerId: 42, text: "clock", delaySeconds: 60, nowMillis: start)
        let jumpedBack = start - 10 * 60 * 60 * 1000
        let restarted = makeQueue(directory, nowMillis: jumpedBack)
        XCTAssertEqual(restarted.entries().first?.notBeforeMillis, jumpedBack + 60_000)
        XCTAssertEqual(restarted.dueEntries(nowMillis: jumpedBack + 60_000).count, 1)
    }

    func testEachAccountKeepsItsOwnQueue() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let first = makeQueue(directory, accountPeerId: 1, nowMillis: start)
        let second = makeQueue(directory, accountPeerId: 2, nowMillis: start)
        _ = try first.enqueue(chatPeerId: 42, text: "one", delaySeconds: 15, nowMillis: start)
        XCTAssertTrue(second.entries().isEmpty)
        let reloaded = makeQueue(directory, accountPeerId: 1, nowMillis: start)
        XCTAssertEqual(reloaded.entries().map { $0.text }, ["one"])
    }

    func testTheFiftyFirstMessageIsRefused() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        for index in 0 ..< BeyGramStealthDelayedSendQueue.maximumEntries {
            _ = try queue.enqueue(chatPeerId: 42, text: "message \(index)", delaySeconds: 15, nowMillis: start)
        }
        XCTAssertThrowsError(try queue.enqueue(chatPeerId: 42, text: "one too many", delaySeconds: 15, nowMillis: start)) { error in
            XCTAssertEqual(error as? BeyGramStealthDelayedQueueError, BeyGramStealthDelayedQueueError.full)
        }
        XCTAssertEqual(queue.entries().count, BeyGramStealthDelayedSendQueue.maximumEntries)
    }

    func testEmptyTextAndAnOutOfRangeDelayAreRefused() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        XCTAssertThrowsError(try queue.enqueue(chatPeerId: 42, text: "   ", delaySeconds: 15, nowMillis: start))
        XCTAssertThrowsError(try queue.enqueue(chatPeerId: 42, text: "ok", delaySeconds: 0, nowMillis: start))
        XCTAssertThrowsError(try queue.enqueue(chatPeerId: 42, text: "ok", delaySeconds: 3601, nowMillis: start))
        XCTAssertTrue(queue.entries().isEmpty)
    }

    func testASentMessageLeavesTheQueue() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "done", delaySeconds: 15, nowMillis: start)
        XCTAssertTrue(try queue.markDispatching(id: entry.id, nowMillis: start + 15_000))
        XCTAssertTrue(try queue.markSent(id: entry.id))
        XCTAssertTrue(queue.entries().isEmpty)
    }

    func testAnUnreadableFileIsKeptAsideAndTheQueueStartsEmpty() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let file = directory.appendingPathComponent("delayed-send-1.json", isDirectory: false)
        try Data("not json".utf8).write(to: file)
        let queue = makeQueue(directory, nowMillis: start)
        XCTAssertTrue(queue.entries().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("delayed-send-1.unreadable.json", isDirectory: false).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testClearRemovesTheAccountsQueue() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        _ = try queue.enqueue(chatPeerId: 42, text: "gone", delaySeconds: 15, nowMillis: start)
        try queue.clear()
        XCTAssertTrue(makeQueue(directory, nowMillis: start).entries().isEmpty)
    }

    func testAFailedNewerMessageDoesNotHoldBackAnOlderOneInItsChat() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let older = try queue.enqueue(chatPeerId: 42, text: "older", delaySeconds: 60, nowMillis: start)
        let newer = try queue.enqueue(chatPeerId: 42, text: "newer", delaySeconds: 15, nowMillis: start + 1)
        XCTAssertEqual(queue.dueEntries(nowMillis: start + 16_000).map { $0.id }, [newer.id])
        XCTAssertTrue(try queue.markDispatching(id: newer.id, nowMillis: start + 16_000))
        XCTAssertTrue(try queue.markFailed(id: newer.id, failure: .network))
        XCTAssertEqual(queue.dueEntries(nowMillis: start + 61_000).map { $0.id }, [older.id])
    }

    func testANewerMessageWaitsBehindAnOlderStuckOneInItsChat() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let older = try queue.enqueue(chatPeerId: 42, text: "older", delaySeconds: 15, nowMillis: start)
        let newer = try queue.enqueue(chatPeerId: 42, text: "newer", delaySeconds: 15, nowMillis: start + 1)
        let otherChat = try queue.enqueue(chatPeerId: 43, text: "other chat", delaySeconds: 15, nowMillis: start + 1)
        XCTAssertTrue(try queue.markDispatching(id: older.id, nowMillis: start + 15_000))
        XCTAssertTrue(try queue.markFailed(id: older.id, failure: .server))
        XCTAssertEqual(queue.dueEntries(nowMillis: start + 20_000).map { $0.id }, [otherChat.id])
        XCTAssertFalse(try queue.markDispatching(id: newer.id, nowMillis: start + 20_000))
        XCTAssertTrue(try queue.sendNow(id: newer.id, nowMillis: start + 20_000))
        XCTAssertEqual(Set(queue.dueEntries(nowMillis: start + 20_000).map { $0.id }), [newer.id, otherChat.id])
    }

    func testAnExpiredMessageDoesNotHoldBackItsChat() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let retention = BeyGramStealthDelayedSendQueue.retentionMillis
        let queue = makeQueue(directory, nowMillis: start)
        _ = try queue.enqueue(chatPeerId: 42, text: "expired", delaySeconds: 15, nowMillis: start)
        let newer = try queue.enqueue(chatPeerId: 42, text: "newer", delaySeconds: 15, nowMillis: start + retention - 1_000)
        XCTAssertEqual(queue.dueEntries(nowMillis: start + retention + 15_000).map { $0.id }, [newer.id])
    }

    func testTopicReplyAndSilenceSurviveARestart() throws {
        let directory = try makeDirectory()
        defer { removeDirectory(directory) }
        let queue = makeQueue(directory, nowMillis: start)
        let entry = try queue.enqueue(chatPeerId: 42, text: "in topic", delaySeconds: 15, nowMillis: start, topicId: 7, replyToMessageId: 9, disableNotification: true)
        let restarted = makeQueue(directory, nowMillis: start + 1_000)
        XCTAssertEqual(restarted.entries(), [entry])
        XCTAssertEqual(restarted.entries().first?.topicId, 7)
        XCTAssertEqual(restarted.entries().first?.replyToMessageId, 9)
        XCTAssertEqual(restarted.entries().first?.disableNotification, true)
    }

    func testEveryFailureHasItsOwnLocalizationKey() {
        let keys = BeyGramStealthDelayedFailure.allCases.map { $0.localizationKey }
        XCTAssertEqual(Set(keys).count, BeyGramStealthDelayedFailure.allCases.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("BeyGram.Stealth.Delay.Failure.") })
    }
}
