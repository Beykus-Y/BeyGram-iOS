import XCTest

@testable import BeyGramDiagnostics

final class BugReportPrivacyTests: XCTestCase {
    func testRedactsBotToken() {
        XCTAssertEqual(
            BugReportPrivacy.redact("token 123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw end"),
            "token [скрыто: токен] end"
        )
    }

    func testRedactsJwt() {
        XCTAssertEqual(
            BugReportPrivacy.redact("jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dBjftJeZ4CVP done"),
            "jwt [скрыто: токен] done"
        )
    }

    func testRedactsSubscriptionLinks() {
        XCTAssertEqual(
            BugReportPrivacy.redact("see https://example.com/path?x=1"),
            "see [скрыто: ссылка]"
        )
        XCTAssertEqual(
            BugReportPrivacy.redact("node vless://id@1.2.3.4:443?security=tls ok"),
            "node [скрыто: ссылка] ok"
        )
    }

    func testKeepsSchemeOfGenericLinks() {
        XCTAssertEqual(
            BugReportPrivacy.redact("ftp://files.local/x"),
            "ftp://[скрыто: ссылка]"
        )
    }

    func testRedactsIPv4WithPort() {
        XCTAssertEqual(
            BugReportPrivacy.redact("peer 10.0.0.1:8080 ok"),
            "peer [скрыто: адрес] ok"
        )
    }

    func testRedactsIPv6() {
        XCTAssertEqual(
            BugReportPrivacy.redact("[2001:db8::1]:443"),
            "[скрыто: адрес]:443"
        )
        XCTAssertEqual(
            BugReportPrivacy.redact("ip 2001:db8:85a3:0:0:8a2e:370:7334 x"),
            "ip [скрыто: адрес] x"
        )
    }

    func testKeepsClockTimes() {
        XCTAssertEqual(BugReportPrivacy.redact("at 12:30:15"), "at 12:30:15")
    }

    func testRedactsHostname() {
        XCTAssertEqual(
            BugReportPrivacy.redact("connect to api.example.org now"),
            "connect to [скрыто: хост] now"
        )
    }

    func testRedactsPhoneNumbers() {
        XCTAssertEqual(BugReportPrivacy.redact("call +7 999 123-45-67"), "call [скрыто: номер]")
        XCTAssertEqual(BugReportPrivacy.redact("id 89123456789"), "id [скрыто: номер]")
    }

    func testRedactsLongHexKeys() {
        XCTAssertEqual(
            BugReportPrivacy.redact("hash 0123456789abcdef0123456789abcdef"),
            "hash [скрыто: ключ]"
        )
    }

    func testRedactsLongBase64LikeKeys() {
        XCTAssertEqual(
            BugReportPrivacy.redact("blob QWxhZGRpbjpvcGVuc2VzYW1lUXdlcnR5MTIzNDU2Nzg5MDEy"),
            "blob [скрыто: ключ]"
        )
    }

    func testRedactsKeyedSecrets() {
        XCTAssertEqual(BugReportPrivacy.redact("token=abc123"), "token=[скрыто]")
        XCTAssertEqual(BugReportPrivacy.redact("password: hunter2"), "password: [скрыто]")
    }

    func testLeavesPlainTextUnchanged() {
        let text = "Connection state changed to ready (attempt 2 of 5)."
        XCTAssertEqual(BugReportPrivacy.redact(text), text)
    }

    func testStripControlsKeepsLineBreaksAndTabs() {
        XCTAssertEqual(BugReportPrivacy.stripControls("a\u{0}b\u{7}c\nd\te"), "abc\nd\te")
    }

    func testSanitizeRemovesControlsBeforeRedacting() {
        XCTAssertEqual(BugReportPrivacy.sanitize("token\u{1}=abc123", maxLength: 100), "token=[скрыто]")
    }

    func testSanitizeTrimsAndRedacts() {
        XCTAssertEqual(
            BugReportPrivacy.sanitize("  open https://x.io/a \n", maxLength: 100),
            "open [скрыто: ссылка]"
        )
    }

    func testSanitizeNeverSplitsSurrogatePairs() {
        XCTAssertEqual(BugReportPrivacy.sanitize("a😀b", maxLength: 2), "a")
        XCTAssertEqual(BugReportPrivacy.sanitize("a😀b", maxLength: 3), "a😀")
        XCTAssertEqual(BugReportPrivacy.sanitize("a😀b", maxLength: 4), "a😀b")
    }

    func testSanitizeZeroLengthIsEmpty() {
        XCTAssertEqual(BugReportPrivacy.sanitize("abc", maxLength: 0), "")
    }
}
