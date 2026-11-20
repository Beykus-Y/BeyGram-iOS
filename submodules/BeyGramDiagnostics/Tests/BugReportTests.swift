import XCTest
@testable import BeyGramDiagnostics

final class BugReportTests: XCTestCase {
    private let validNonce = String(repeating: "A", count: 43)

    func testParsesReportCommand() {
        XCTAssertEqual(BugReportBuilder.parseReportCommand("/report \(validNonce)"), validNonce)
        XCTAssertNil(BugReportBuilder.parseReportCommand("/report short"))
        XCTAssertNil(BugReportBuilder.parseReportCommand("/start \(validNonce)"))
        XCTAssertNil(BugReportBuilder.parseReportCommand("/report \(validNonce) extra"))
    }

    func testEmptyDescriptionIsRefused() {
        XCTAssertThrowsError(try BugReportBuilder.makeBody(reportId: "r", description: "   ", summary: nil, meta: BugReportClientMeta(), events: [])) { error in
            XCTAssertEqual(error as? BugReportError, .emptyDescription)
        }
    }

    func testDescriptionIsClampedToLimit() throws {
        let long = String(repeating: "x", count: 5000)
        let (body, _) = try BugReportBuilder.makeBody(reportId: "r", description: long, summary: nil, meta: BugReportClientMeta(), events: [])
        XCTAssertEqual(body.description.count, BugReportBody.maxDescriptionCharacters)
    }

    func testOldestEventsAreDroppedFirstWhenOverLimit() throws {
        let events = (0 ..< 2500).map { BugReportEvent(kind: .network, severity: .error, code: "e\($0)") }
        let (body, dropped) = try BugReportBuilder.makeBody(reportId: "r", description: "d", summary: nil, meta: BugReportClientMeta(), events: events)
        XCTAssertEqual(body.events.count, BugReportBody.maxEvents)
        XCTAssertEqual(dropped, 500)
        XCTAssertEqual(body.events.last?.code, "e2499")
        XCTAssertEqual(body.clientMeta.eventCountTotal, 2500)
    }

    func testBodyEncodesServerFieldNames() throws {
        let (body, _) = try BugReportBuilder.makeBody(reportId: "r", description: "d", summary: nil, meta: BugReportClientMeta(appVersion: "1.0"), events: [])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(json?["schema_version"] as? Int, 1)
        XCTAssertEqual(json?["report_id"] as? String, "r")
        XCTAssertEqual((json?["client_meta"] as? [String: Any])?["app_version"] as? String, "1.0")
    }

    func testUploadRequestUsesBearerNonce() throws {
        let (body, _) = try BugReportBuilder.makeBody(reportId: "r", description: "d", summary: nil, meta: BugReportClientMeta(), events: [])
        let request = try BugReportBuilder.makeUploadRequest(baseURL: URL(string: "https://example.invalid/")!, nonce: validNonce, body: body)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(validNonce)")
        XCTAssertEqual(request.url?.path, "/api/v1/bug-reports")
    }
}
