import XCTest
@testable import BeyGramChatExport

private final class BufferSink: ChatExportSink {
    var data = Data()
    func write(_ chunk: Data) throws {
        data.append(chunk)
    }
    var string: String { String(decoding: data, as: UTF8.self) }
}

final class ChatExportWriterTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private var header: ChatExportHeader {
        ChatExportHeader(accountLabel: "Account A", chatTitle: "Chat <one>", exportedAt: date("2026-11-19T10:00:00Z"))
    }

    func testSecretChatIsRefusedBeforeWriting() {
        XCTAssertThrowsError(try ChatExportWriter.checkTarget(isSecretChat: true, hasProtectedContent: false)) { error in
            XCTAssertEqual(error as? ChatExportRefusal, .secretChat)
        }
    }

    func testProtectedContentIsRefused() {
        XCTAssertThrowsError(try ChatExportWriter.checkTarget(isSecretChat: false, hasProtectedContent: true)) { error in
            XCTAssertEqual(error as? ChatExportRefusal, .protectedContent)
        }
    }

    func testJSONOutputIsValidAndCountsSkippedMessages() throws {
        let sink = BufferSink()
        let writer = ChatExportWriter(format: .json, header: header, range: ChatExportRange(calendar: utc), sink: sink)
        try writer.begin()
        try writer.append(ChatExportMessage(id: 1, date: date("2026-11-01T12:00:00Z"), senderName: "Ann", text: "hi \"there\""))
        try writer.append(ChatExportMessage(id: 2, date: date("2026-11-01T12:01:00Z"), senderName: "Bob", text: "secret", canBeSaved: false))
        try writer.append(ChatExportMessage(id: 3, date: date("2026-11-02T12:00:00Z"), senderName: "Ann", text: "next", replyToMessageId: 1))
        let summary = try writer.finish()

        XCTAssertEqual(summary, ChatExportSummary(exportedMessages: 2, skippedNotSaveable: 1, skippedOutOfRange: 0))
        let object = try JSONSerialization.jsonObject(with: sink.data) as? [String: Any]
        XCTAssertEqual(object?["account"] as? String, "Account A")
        let messages = object?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.last?["replyTo"] as? Int, 1)
    }

    func testDateRangeIsHalfOpenOnDays() throws {
        let range = ChatExportRange(startDay: date("2026-11-01T00:00:00Z"), endDay: date("2026-11-03T00:00:00Z"), calendar: utc)
        XCTAssertTrue(range.contains(date("2026-11-01T00:00:00Z")))
        XCTAssertTrue(range.contains(date("2026-11-02T23:59:59Z")))
        XCTAssertFalse(range.contains(date("2026-11-03T00:00:00Z")))
        XCTAssertFalse(range.contains(date("2026-10-31T23:59:59Z")))
    }

    func testHTMLEscapesTextAndSender() throws {
        let sink = BufferSink()
        let writer = ChatExportWriter(format: .html, header: header, range: ChatExportRange(calendar: utc), sink: sink)
        try writer.begin()
        try writer.append(ChatExportMessage(id: 9, date: date("2026-11-01T12:00:00Z"), senderName: "<b>", text: "a & b"))
        _ = try writer.finish()
        XCTAssertTrue(sink.string.contains("&lt;b&gt;"))
        XCTAssertTrue(sink.string.contains("a &amp; b"))
        XCTAssertTrue(sink.string.contains("Chat &lt;one&gt;"))
    }
}
