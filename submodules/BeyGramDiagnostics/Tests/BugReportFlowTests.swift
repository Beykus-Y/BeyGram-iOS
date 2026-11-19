import XCTest
@testable import BeyGramDiagnostics

final class BugReportFlowTests: XCTestCase {
    private let nonce = String(repeating: "A", count: 43)
    private let id = "11111111-1111-4111-8111-111111111111"

    func testHappyPathDelivers() {
        var state = BugReportFlow.reduce(.idle, .start, makeReportId: { self.id })
        XCTAssertEqual(state, .awaitingNonce(reportId: id))
        state = BugReportFlow.reduce(state, .nonceReceived(nonce))
        XCTAssertEqual(state, .uploading(reportId: id, nonce: nonce))
        state = BugReportFlow.reduce(state, .uploadAccepted(statusToken: "tok"))
        XCTAssertEqual(state, .delivered(reportId: id, statusToken: "tok"))
    }

    func testMalformedNonceFailsWithoutUpload() {
        let state = BugReportFlow.reduce(.awaitingNonce(reportId: id), .nonceReceived("short"))
        XCTAssertEqual(state, .failed(reportId: id, reason: .nonceRejected))
    }

    func testStatusCodesMapToFailures() {
        XCTAssertEqual(BugReportFlow.failure(forHTTPStatus: 401), .nonceRejected)
        XCTAssertEqual(BugReportFlow.failure(forHTTPStatus: 403), .notAllowedOrLimited)
        XCTAssertEqual(BugReportFlow.failure(forHTTPStatus: 409), .conflict)
        XCTAssertEqual(BugReportFlow.failure(forHTTPStatus: 413), .tooLarge)
        XCTAssertEqual(BugReportFlow.failure(forHTTPStatus: 422), .invalidBody)
        XCTAssertEqual(BugReportFlow.failure(forHTTPStatus: nil), .transient)
        XCTAssertEqual(BugReportFlow.failure(forHTTPStatus: 500), .transient)
    }

    func testRetryOnlyForTransientAndExpiredNonce() {
        XCTAssertTrue(BugReportFlow.canRetry(.transient))
        XCTAssertTrue(BugReportFlow.canRetry(.nonceRejected))
        XCTAssertFalse(BugReportFlow.canRetry(.tooLarge))
        XCTAssertFalse(BugReportFlow.canRetry(.invalidBody))
    }

    func testCancelReturnsToIdleFromAwaitingNonce() {
        XCTAssertEqual(BugReportFlow.reduce(.awaitingNonce(reportId: id), .cancel), .idle)
    }
}

final class BugReportClientRequestTests: XCTestCase {
    func testUploadRequestHasNoBodyLeakOfNonceOutsideHeader() throws {
        let nonce = String(repeating: "B", count: 43)
        let (body, _) = try BugReportBuilder.makeBody(reportId: "r", description: "d", summary: nil, meta: BugReportClientMeta(), events: [])
        let request = try BugReportBuilder.makeUploadRequest(baseURL: URL(string: "https://example.invalid/")!, nonce: nonce, body: body)
        let bodyText = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertFalse(bodyText.contains(nonce))
    }
}
