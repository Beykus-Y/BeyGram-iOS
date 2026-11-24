import XCTest
@testable import BeyGramKit

/// Contract fixtures of BG Push Navigation v2 (issue #74), the same strings as in the server issue #37.
/// NOT CHECKED BY COMPILATION.
final class BeyGramPushNavigationV2Tests: XCTestCase {
    private func request(_ string: String) -> BeyGramPushOpenRequest? {
        return URL(string: string).flatMap { BeyGramPushOpenRequest(url: $0) }
    }

    func testUserMessage() {
        let r = request("beygram://push/open?v=2&account=123&kind=user&rawPeer=456&msg=789")
        XCTAssertEqual(r?.accountUserId, 123)
        XCTAssertEqual(r?.target, BeyGramPushOpenRequest.Target(kind: .user, rawPeerId: 456, messageId: 789))
        XCTAssertNil(r?.peerId)
    }

    func testGroupAndChannelAreDifferentKinds() {
        XCTAssertEqual(request("beygram://push/open?v=2&account=123&kind=chat&rawPeer=42&msg=7")?.target?.kind, .chat)
        XCTAssertEqual(request("beygram://push/open?v=2&account=123&kind=channel&rawPeer=42&msg=7")?.target?.kind, .channel)
    }

    func testChatOnly() {
        let r = request("beygram://push/open?v=2&account=123&kind=channel&rawPeer=42")
        XCTAssertEqual(r?.target, BeyGramPushOpenRequest.Target(kind: .channel, rawPeerId: 42, messageId: nil))
    }

    func testPrecisionIsKept() {
        let r = request("beygram://push/open?v=2&account=9007199254740993&kind=user&rawPeer=9007199254740995&msg=2147483647")
        XCTAssertEqual(r?.accountUserId, 9007199254740993)
        XCTAssertEqual(r?.target?.rawPeerId, 9007199254740995)
        XCTAssertEqual(r?.target?.messageId, Int32.max)
    }

    func testKeyOrderMayDiffer() {
        let r = request("beygram://push/open?msg=1&rawPeer=2&kind=user&account=3&v=2")
        XCTAssertEqual(r?.target, BeyGramPushOpenRequest.Target(kind: .user, rawPeerId: 2, messageId: 1))
    }

    func testLegacyStillWorks() {
        let r = request("beygram://push/open?account=123&peer=456&msg=789")
        XCTAssertEqual(r?.accountUserId, 123)
        XCTAssertEqual(r?.peerId, 456)
        XCTAssertEqual(r?.messageId, 789)
        XCTAssertNil(r?.target)
    }

    func testBareOpen() {
        let r = request("beygram://push/open")
        XCTAssertNotNil(r)
        XCTAssertNil(r?.accountUserId)
        XCTAssertNil(r?.target)
    }

    func testRejectsAreBareOpenNotLegacy() {
        let rejects = [
            "beygram://push/open?v=3&account=123&kind=user&rawPeer=456",
            "beygram://push/open?v=2&account=123&kind=group&rawPeer=456",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=0",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=-1",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=01",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=9223372036854775808",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=1e3",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=456&msg=2147483648",
            "beygram://push/open?v=2&kind=user&rawPeer=456",
            "beygram://push/open?v=2&account=123&rawPeer=456",
            "beygram://push/open?v=2&account=123&kind=user",
            "beygram://push/open?v=2&account=123&account=124&kind=user&rawPeer=456",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=456&peer=9",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=456&extra=1",
            "beygram://push/open?v=2&account=123&kind=user&rawPeer=456#fragment",
            "beygram://user:pw@push/open?v=2&account=123&kind=user&rawPeer=456",
            "beygram://push/open?v=2&account=123&kind=%75ser&rawPeer=456",
        ]
        for string in rejects {
            guard let url = URL(string: string) else {
                continue
            }
            if let r = BeyGramPushOpenRequest(url: url) {
                XCTAssertNil(r.target, string)
                XCTAssertNil(r.accountUserId, string)
                XCTAssertNil(r.peerId, string)
            }
        }
    }

    func testOtherLinksAreNotPushLinks() {
        XCTAssertNil(request("https://example.com/push/open?v=2"))
        XCTAssertNil(request("beygram://other/open"))
    }
}
