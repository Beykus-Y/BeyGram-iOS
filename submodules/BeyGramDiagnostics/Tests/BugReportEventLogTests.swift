import XCTest

@testable import BeyGramDiagnostics

final class BugReportEventLogTests: XCTestCase {
    func testKeepsOrderAndSequenceNumbers() {
        let log = BugReportEventLog(capacity: 5, clock: { 1000 })
        log.record(kind: .connection, code: "a")
        log.record(kind: .network, severity: .warning, code: "b")
        let entries = log.snapshot()
        XCTAssertEqual(entries.map(\.seq), [0, 1])
        XCTAssertEqual(entries.map(\.code), ["a", "b"])
        XCTAssertEqual(entries.last?.severity, BugReportSeverity.warning)
        XCTAssertEqual(entries.first?.at, 1000)
        XCTAssertEqual(log.totalRecorded, 2)
        XCTAssertFalse(log.hasOverflowed)
    }

    func testDropsOldestAndMarksOverflow() {
        let log = BugReportEventLog(capacity: 2, clock: { 0 })
        log.record(kind: .ui, code: "1")
        log.record(kind: .ui, code: "2")
        XCTAssertFalse(log.hasOverflowed)
        log.record(kind: .ui, code: "3")
        XCTAssertTrue(log.hasOverflowed)
        XCTAssertEqual(log.snapshot().map(\.code), ["2", "3"])
        XCTAssertEqual(log.snapshot().map(\.seq), [1, 2])
        XCTAssertEqual(log.totalRecorded, 3)
    }
}
