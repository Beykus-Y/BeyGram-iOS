import Foundation
import XCTest

@testable import BeyGramDiagnostics

final class BugReportSnapshotTests: XCTestCase {
    func testEventsCarrySequenceAndTime() {
        let log = BugReportEventLog(capacity: 5, clock: { 1_700_000_000.5 })
        log.record(kind: .tdlib, code: "open")
        let events = BugReportSnapshot.events(from: log)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.seq, 0)
        XCTAssertEqual(events.first?.at, 1_700_000_000.5)
    }

    func testBodyRedactsMessagesAndAttributes() throws {
        let log = BugReportEventLog(capacity: 5, clock: { 0 })
        log.record(
            kind: .connection,
            severity: .warning,
            code: "tls_fail",
            message: "connect https://secret.example/x via 10.1.2.3",
            attrs: ["host": "api.example.org", "auth": "token=abc123"]
        )
        let (body, _) = try BugReportSnapshot.makeBody(reportId: "r", description: "проблема", meta: BugReportClientMeta(), log: log)
        let data = try body.encodedJSON()
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("secret.example"))
        XCTAssertFalse(json.contains("10.1.2.3"))
        XCTAssertFalse(json.contains("api.example.org"))
        XCTAssertFalse(json.contains("abc123"))
        XCTAssertTrue(json.contains("connect [скрыто: ссылка] via [скрыто: адрес]"))
        XCTAssertEqual(body.events.first?.attrs["host"], "[скрыто: хост]")
        XCTAssertEqual(body.events.first?.attrs["auth"], "token=[скрыто]")
    }

    func testSummaryRedactsOnceAndKeepsMarkers() {
        let events = [BugReportEvent(kind: .network, severity: .error, code: "dns", message: "ftp://files.local/x")]
        XCTAssertEqual(BugReportSnapshot.summary(for: events), "- --:--:-- network/dns (error) ftp://[скрыто: ссылка]")
    }

    func testSummaryIsNilWithoutEvents() {
        XCTAssertNil(BugReportSnapshot.summary(for: []))
    }

    func testBudgetKeepsNewestEventsAndMarksOverflow() throws {
        let log = BugReportEventLog(capacity: 300, clock: { 0 })
        let message = String(repeating: "lorem ipsum ", count: 40)
        var attrs: [String: String] = [:]
        for index in 0 ..< 24 {
            attrs["k\(index)"] = String(repeating: "value text ", count: 16)
        }
        for index in 0 ..< 200 {
            log.record(kind: .ui, code: "ev_\(index)", message: message, attrs: attrs)
        }
        let (body, dropped) = try BugReportSnapshot.makeBody(reportId: "r", description: "d", meta: BugReportClientMeta(), log: log)
        let size = try body.encodedJSON().count
        XCTAssertGreaterThan(dropped, 0)
        XCTAssertLessThanOrEqual(size, BugReportBody.clientBudgetBytes)
        XCTAssertEqual(body.events.last?.code, "ev_199")
        XCTAssertEqual(body.clientMeta.bufferOverflowed, true)
        XCTAssertEqual(body.clientMeta.eventCountTotal, 200)
    }

    func testEncodingDoesNotDependOnDictionaryOrder() throws {
        let first = BugReportEvent(kind: .ui, severity: .info, code: "c", attrs: ["a": "1", "b": "2", "c": "3"])
        let second = BugReportEvent(kind: .ui, severity: .info, code: "c", attrs: ["c": "3", "b": "2", "a": "1"])
        let meta = BugReportClientMeta()
        let (bodyA, _) = try BugReportBuilder.makeBody(reportId: "r", description: "d", summary: nil, meta: meta, events: [first])
        let (bodyB, _) = try BugReportBuilder.makeBody(reportId: "r", description: "d", summary: nil, meta: meta, events: [second])
        let dataA = try bodyA.encodedJSON()
        let dataB = try bodyB.encodedJSON()
        XCTAssertEqual(dataA, dataB)
    }
}
