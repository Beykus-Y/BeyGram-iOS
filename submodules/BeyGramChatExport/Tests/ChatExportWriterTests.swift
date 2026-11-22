import XCTest
@testable import BeyGramChatExport

private final class BufferSink: ChatExportSink {
    var data = Data()

    func write(_ chunk: Data) throws {
        data.append(chunk)
    }

    var string: String {
        String(decoding: data, as: UTF8.self)
    }
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

    private func seconds(_ iso: String) -> Int64 {
        Int64(date(iso).timeIntervalSince1970)
    }

    private var header: ChatExportHeader {
        ChatExportHeader(
            accountLabel: "Account A",
            chat: ChatExportChat(id: -1001234, title: "Chat <one>", kind: "channel"),
            exportedAt: date("2026-11-19T10:00:00Z")
        )
    }

    private func message(_ id: Int64, _ iso: String, text: String = "hi", canBeSaved: Bool = true) -> ChatExportMessage {
        ChatExportMessage(id: id, date: date(iso), senderName: "Ann", text: text, canBeSaved: canBeSaved)
    }

    /// Writes the document for `messages` and returns its text with the summary.
    private func render(
        _ format: ChatExportFormat,
        _ messages: [ChatExportMessage],
        range: ChatExportRange? = nil
    ) throws -> (text: String, summary: ChatExportSummary) {
        let sink = BufferSink()
        let writer = ChatExportWriter(
            format: format,
            header: header,
            range: range ?? ChatExportRange(calendar: utc),
            sink: sink
        )
        try writer.begin()
        for item in messages {
            try writer.append(item)
        }
        let summary = try writer.finish()
        return (sink.string, summary)
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

    func testEmptyJSONDocumentHasTheAndroidLayout() throws {
        let (text, _) = try render(.json, [])
        let expected = "{\n\"format\":\"beygram-chat-export\",\n\"version\":1,\n\"exportedAt\":\"2026-11-19T10:00:00Z\","
            + "\n\"sourceAccount\":\"Account A\",\n\"chat\":{\"id\":-1001234,\"title\":\"Chat <one>\",\"kind\":\"channel\"},"
            + "\n\"range\":{\"from\":null,\"to\":null},\n\"mediaRequested\":false,\n\"messages\":[\n],"
            + "\n\"summary\":{\"messages\":0,\"mediaFiles\":0,\"skippedSaveRestricted\":0,\"skippedMedia\":0}\n}\n"
        XCTAssertEqual(text, expected)
    }

    func testOneJSONMessageHasTheAndroidFields() throws {
        let item = ChatExportMessage(
            id: 1,
            date: date("2026-11-01T12:00:00Z"),
            isOutgoing: false,
            senderId: 7,
            senderName: "Ann",
            text: "hi \"there\""
        )
        let (text, _) = try render(.json, [item])
        let fields = "{\"id\":1,\"date\":\(seconds("2026-11-01T12:00:00Z")),\"dateIso\":\"2026-11-01T12:00:00Z\","
            + "\"outgoing\":false,\"sender\":{\"id\":7,\"name\":\"Ann\"},\"text\":\"hi \\\"there\\\"\",\"edited\":false,"
            + "\"service\":false,\"replyToMessageId\":null,\"media\":null}"
        XCTAssertTrue(text.contains("\n" + fields + "\n],"))
    }

    func testSkippedMessagesAreCountedAndJSONStaysValid() throws {
        let reply = ChatExportMessage(id: 3, date: date("2026-11-02T12:00:00Z"), senderName: "Ann", text: "next", replyToMessageId: 1)
        let (text, summary) = try render(.json, [
            message(1, "2026-11-01T12:00:00Z"),
            message(2, "2026-11-01T12:01:00Z", text: "secret", canBeSaved: false),
            reply,
        ])
        XCTAssertEqual(summary, ChatExportSummary(exportedMessages: 2, skippedNotSaveable: 1, skippedOutOfRange: 0))
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let messages = object?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.last?["replyToMessageId"] as? Int, 1)
        let counts = object?["summary"] as? [String: Any]
        XCTAssertEqual(counts?["messages"] as? Int, 2)
        XCTAssertEqual(counts?["skippedSaveRestricted"] as? Int, 1)
    }

    func testRangeIsWrittenInUnixSecondsAndHalfOpen() throws {
        let range = ChatExportRange(
            startDay: date("2026-11-01T00:00:00Z"),
            endDay: date("2026-11-03T00:00:00Z"),
            calendar: utc
        )
        XCTAssertEqual(range.fromSeconds, seconds("2026-11-01T00:00:00Z"))
        XCTAssertEqual(range.toSeconds, seconds("2026-11-03T00:00:00Z"))
        XCTAssertTrue(range.contains(date("2026-11-01T00:00:00Z")))
        XCTAssertTrue(range.contains(date("2026-11-02T23:59:59Z")))
        XCTAssertFalse(range.contains(date("2026-11-03T00:00:00Z")))
        XCTAssertFalse(range.contains(date("2026-10-31T23:59:59Z")))
        let (text, _) = try render(.json, [], range: range)
        XCTAssertTrue(text.contains("\"range\":{\"from\":\(seconds("2026-11-01T00:00:00Z")),\"to\":\(seconds("2026-11-03T00:00:00Z"))}"))
    }

    func testReversedDateRangeIsRefusedBeforeWriting() {
        let day = date("2026-11-01T00:00:00Z")
        let sink = BufferSink()
        let writer = ChatExportWriter(
            format: .json,
            header: header,
            range: ChatExportRange(startDay: day, endDay: day, calendar: utc),
            sink: sink
        )
        XCTAssertThrowsError(try writer.begin()) { error in
            XCTAssertEqual(error as? ChatExportRefusal, .invalidDateRange)
        }
        XCTAssertTrue(sink.data.isEmpty)
    }

    func testJSONEscapesControlCharactersAndLineSeparators() throws {
        let item = ChatExportMessage(
            id: 1,
            date: date("2026-11-01T12:00:00Z"),
            senderName: "Ann",
            text: "tab\there\u{2028}end\u{1}"
        )
        let (text, _) = try render(.json, [item])
        XCTAssertTrue(text.contains("\"text\":\"tab\\there\\u2028end\\u0001\""))
    }

    func testAttachmentsAreDescribedAndLinkedWhenTheyAreInTheArchive() throws {
        let file = ChatExportAttachment(id: 5, kind: .document, fileName: "report one.pdf", mimeType: "application/pdf", size: 1234)
        let sink = BufferSink()
        let writer = ChatExportWriter(format: .json, header: header, range: ChatExportRange(calendar: utc), sink: sink)
        try writer.begin()
        try writer.append(ChatExportMessage(id: 1, date: date("2026-11-01T12:00:00Z"), senderName: "Ann", text: "", attachment: file))
        try writer.append(
            ChatExportMessage(id: 2, date: date("2026-11-01T12:01:00Z"), senderName: "Ann", text: "", attachment: file),
            mediaPath: "media/2_report one.pdf"
        )
        _ = try writer.finish()
        XCTAssertTrue(sink.string.contains(
            "\"media\":{\"kind\":\"Document\",\"fileName\":\"report one.pdf\",\"mimeType\":\"application/pdf\","
                + "\"bytes\":1234,\"durationSeconds\":0,\"width\":0,\"height\":0,\"exportedPath\":null}"
        ))
        XCTAssertTrue(sink.string.contains("\"exportedPath\":\"media/2_report one.pdf\"}"))
    }

    func testHTMLFigureNotesAFileThatIsNotInTheArchive() throws {
        let file = ChatExportAttachment(id: 5, kind: .document, fileName: "report one.pdf", mimeType: "application/pdf", size: 1234)
        let item = ChatExportMessage(id: 1, date: date("2026-11-01T12:00:00Z"), senderName: "Ann", text: "", attachment: file)
        let (text, _) = try render(.html, [item])
        XCTAssertTrue(text.contains(
            "<figure class=\"attachment\"><figcaption>Document \u{00B7} report one.pdf \u{00B7} 1234 bytes "
                + "<span class=\"missing\">not included</span></figcaption></figure>\n"
        ))
    }

    func testHTMLFollowsTheAndroidDocument() throws {
        let item = ChatExportMessage(id: 9, date: date("2026-11-01T12:00:00Z"), senderName: "<b>", text: "a & b")
        let (text, _) = try render(.html, [item])
        XCTAssertTrue(text.hasPrefix("<!doctype html>\n<html lang=\"und\">\n<head>\n<meta charset=\"utf-8\">\n"))
        XCTAssertTrue(text.contains("<title>Chat &lt;one&gt;</title>"))
        XCTAssertTrue(text.contains("<p class=\"meta\">Source account: Account A</p>"))
        XCTAssertTrue(text.contains("<p class=\"meta\">Exported 2026-11-19T10:00:00Z</p>"))
        XCTAssertTrue(text.contains("<p class=\"meta\">Date range: all messages</p>"))
        XCTAssertTrue(text.contains("<article class=\"message incoming\">\n<header><span class=\"sender\">&lt;b&gt;</span> <time datetime=\"2026-11-01T12:00:00Z\">"))
        XCTAssertTrue(text.contains("<div class=\"text\">a &amp; b</div>\n</article>\n"))
        XCTAssertTrue(text.contains(":root { color-scheme: light dark; }"))
        XCTAssertTrue(text.hasSuffix(
            "</section>\n<footer class=\"chat-footer\">\n<p>Exported 1 messages and 0 media files. "
                + "Skipped 0 save-restricted messages and 0 unavailable media files.</p>\n</footer>\n</main>\n</body>\n</html>\n"
        ))
    }

    func testServiceAndEditedMessagesUseTheAndroidClasses() throws {
        let item = ChatExportMessage(
            id: 4,
            date: date("2026-11-01T12:00:00Z"),
            isOutgoing: true,
            senderName: "",
            text: "",
            isEdited: true,
            serviceText: "Ann joined"
        )
        let (text, _) = try render(.html, [item])
        XCTAssertTrue(text.contains("<article class=\"message outgoing service\">\n<header><span class=\"sender\">Unknown sender</span>"))
        XCTAssertTrue(text.contains("<span class=\"edited\">edited</span></header>\n<div class=\"text\">Ann joined</div>\n</article>\n"))
    }

    func testMediaHrefEncodesEachSegmentLikeAndroid() {
        XCTAssertEqual(ChatExportWriter.mediaHref("media/1_a b~c.txt"), "media/1_a%20b%7Ec.txt")
        XCTAssertEqual(ChatExportWriter.mediaHref("media/2_\u{00E9}.pdf"), "media/2_%C3%A9.pdf")
    }

    func testFinishWritesTheMediaCounts() throws {
        let sink = BufferSink()
        let writer = ChatExportWriter(format: .json, header: header, range: ChatExportRange(calendar: utc), sink: sink)
        try writer.begin()
        let summary = try writer.finish(mediaFiles: 2, skippedMedia: 1)
        XCTAssertEqual(summary.mediaFiles, 2)
        XCTAssertEqual(summary.skippedMedia, 1)
        XCTAssertTrue(sink.string.hasSuffix("\"summary\":{\"messages\":0,\"mediaFiles\":2,\"skippedSaveRestricted\":0,\"skippedMedia\":1}\n}\n"))
    }

    func testInstantAndTimestampFormatsMatchJava() {
        XCTAssertEqual(ChatExportWriter.javaInstantString(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00Z")
        XCTAssertEqual(ChatExportWriter.javaInstantString(Date(timeIntervalSince1970: 1.5)), "1970-01-01T00:00:01.500Z")
        XCTAssertEqual(ChatExportWriter.exportIsoTimestamp(0), "")
        XCTAssertEqual(ChatExportWriter.formatExportTimestamp(0), "")
    }
}
