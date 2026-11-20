import XCTest
@testable import BeyGramYandexMusic

final class BGYandexTests: XCTestCase {
    private let credentials = BGYandexCredentials(clientId: "id", clientSecret: "secret")

    func testSourceStaysHiddenWithoutCredentials() {
        let empty = BGYandexCredentials(clientId: "", clientSecret: "")
        XCTAssertFalse(BGYandexAvailability.isAvailable(flagEnabled: true, credentials: empty, consentAccepted: true))
    }

    func testSourceStaysHiddenWithoutFlagOrConsent() {
        XCTAssertFalse(BGYandexAvailability.isAvailable(flagEnabled: false, credentials: credentials, consentAccepted: true))
        XCTAssertFalse(BGYandexAvailability.isAvailable(flagEnabled: true, credentials: credentials, consentAccepted: false))
        XCTAssertTrue(BGYandexAvailability.isAvailable(flagEnabled: true, credentials: credentials, consentAccepted: true))
    }

    func testConsentIsOffByDefaultAndCanBeAccepted() {
        let suite = UserDefaults(suiteName: "bgyandex.tests.\(UUID().uuidString)")!
        let consent = BGYandexConsent(defaults: suite)
        XCTAssertFalse(consent.isAccepted)
        consent.accept()
        XCTAssertTrue(consent.isAccepted)
        consent.revoke()
        XCTAssertFalse(consent.isAccepted)
    }

    func testPacingKeepsQuarterSecondGap() {
        var gate = BGYandexRequestGate()
        XCTAssertEqual(gate.reserve(now: 10), 0, accuracy: 0.0001)
        XCTAssertEqual(gate.reserve(now: 10), 0.25, accuracy: 0.0001)
        XCTAssertEqual(gate.reserve(now: 10), 0.5, accuracy: 0.0001)
    }

    func testRateLimitPausesWholeQueue() {
        var gate = BGYandexRequestGate()
        gate.reportRateLimited(retryAfterHeader: "7", now: 100)
        XCTAssertEqual(gate.reserve(now: 101), 6, accuracy: 0.0001)
    }

    func testRateLimitWithoutHeaderUsesDefault() {
        var gate = BGYandexRequestGate()
        gate.reportRateLimited(retryAfterHeader: nil, now: 0)
        XCTAssertEqual(gate.reserve(now: 0), BGYandexConfig.defaultRetryAfter, accuracy: 0.0001)
    }

    func testFormBodyEncodesReservedCharacters() {
        let body = BGYandexDeviceFlow.formBody([("code", "a+b c&=")])
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "code=a%2Bb%20c%26%3D")
    }

    func testPollOutcomes() {
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: 400, body: Data(#"{"error":"authorization_pending"}"#.utf8)), .pending)
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: 400, body: Data(#"{"error":"slow_down"}"#.utf8)), .slowDown)
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: 400, body: Data(#"{"error":"expired_token"}"#.utf8)), .failed(.sessionExpired))
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: nil, body: nil), .failed(.network))
    }

    func testTokenResponseIsParsed() {
        let body = Data(#"{"access_token":"t","refresh_token":"r","expires_in":3600}"#.utf8)
        XCTAssertEqual(BGYandexDeviceFlow.pollOutcome(statusCode: 200, body: body),
                       .tokens(BGYandexTokens(accessToken: "t", refreshToken: "r", expiresIn: 3600)))
    }

    func testDeviceCodeIsParsedWithDefaults() {
        let body = Data(#"{"device_code":"dc","user_code":"UC","verification_url":"https://ya.ru/device"}"#.utf8)
        XCTAssertEqual(BGYandexDeviceFlow.parseDeviceCode(body),
                       BGYandexDeviceCode(deviceCode: "dc", userCode: "UC", verificationUrl: "https://ya.ru/device", expiresIn: 300, interval: 5))
    }

    func testDownloadInfoIsParsedAndSigned() {
        let xml = "<?xml version=\"1.0\"?><download-info><host>s1.example</host><path>/get/track.mp3</path><ts>123</ts><s>abc</s></download-info>"
        let info = BGYandexAPI.parseDownloadInfo(xml)
        XCTAssertEqual(info, BGYandexAPI.DownloadInfo(host: "s1.example", path: "/get/track.mp3", ts: "123", s: "abc"))
        XCTAssertEqual(BGYandexAPI.directLink(info!)?.absoluteString, "https://s1.example/get-mp3/397e3ab8dde222691699f60954c292a3/123/get/track.mp3")
    }

    func testDoctypeIsRefused() {
        XCTAssertNil(BGYandexAPI.parseDownloadInfo("<!DOCTYPE x [<!ENTITY e \"y\">]><download-info><host>h</host><path>/p</path><ts>1</ts><s>s</s></download-info>"))
    }

    func testAccountParsesUidAndPlus() {
        let root: [String: Any] = ["result": ["account": ["uid": 42, "login": "user"], "plus": ["has_plus": true]]]
        XCTAssertEqual(BGYandexAPI.parseAccount(root), BGYandexAccount(uid: "42", displayName: "user", hasPlus: true))
    }

    func testRefreshRequestUsesRefreshGrant() {
        let request = BGYandexTokenRefresh.request(refreshToken: "r+1", credentials: credentials)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(String(decoding: request.httpBody ?? Data(), as: UTF8.self),
                       "grant_type=refresh_token&refresh_token=r%2B1&client_id=id&client_secret=secret")
    }

    func testRefreshOutcomes() {
        XCTAssertEqual(BGYandexTokenRefresh.outcome(statusCode: 200, body: Data(#"{"access_token":"t","expires_in":3600}"#.utf8)),
                       .tokens(BGYandexTokens(accessToken: "t", refreshToken: nil, expiresIn: 3600)))
        XCTAssertEqual(BGYandexTokenRefresh.outcome(statusCode: 200, body: Data(#"{"access_token":"t","refresh_token":"n","expires_in":60}"#.utf8)),
                       .tokens(BGYandexTokens(accessToken: "t", refreshToken: "n", expiresIn: 60)))
        XCTAssertEqual(BGYandexTokenRefresh.outcome(statusCode: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)), .sessionExpired)
        XCTAssertEqual(BGYandexTokenRefresh.outcome(statusCode: 403, body: nil), .sessionExpired)
        XCTAssertEqual(BGYandexTokenRefresh.outcome(statusCode: 500, body: Data()), .unavailable)
        XCTAssertEqual(BGYandexTokenRefresh.outcome(statusCode: 200, body: Data(#"{"expires_in":3600}"#.utf8)), .unavailable)
        XCTAssertEqual(BGYandexTokenRefresh.outcome(statusCode: nil, body: nil), .unavailable)
    }

    func testFileNameIsSafe() {
        XCTAssertEqual(BGYandexTrackResolver.fileName(trackId: "../12/3"), "ym-123.mp3")
    }
}
