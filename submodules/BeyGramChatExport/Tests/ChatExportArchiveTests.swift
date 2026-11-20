import Foundation
import XCTest
@testable import BeyGramChatExport

private final class MemorySink: ChatExportSink {
    var data = Data()

    func write(_ chunk: Data) throws {
        data.append(chunk)
    }

    /// The archive as text. Stored entries keep names and document text verbatim, so `contains` works on it.
    var text: String {
        String(decoding: data, as: UTF8.self)
    }
}

private struct ScriptedFailure: Error {}

private final class ProgressRecorder {
    var last: ChatExportProgress?
}

private final class ScriptedHistory: ChatExportHistory {
    private let pages: [[ChatExportMessage]]
    private var nextIndex = 0
    private(set) var rewinds = 0

    init(pages: [[ChatExportMessage]]) {
        self.pages = pages
    }

    func nextPage() async throws -> [ChatExportMessage] {
        guard nextIndex < pages.count else {
            return []
        }
        defer {
            nextIndex += 1
        }
        return pages[nextIndex]
    }

    func rewind() async throws {
        rewinds += 1
        nextIndex = 0
    }
}

private final class ScriptedStream: ChatExportFileStream {
    private var remaining: Data

    init(_ data: Data) {
        remaining = data
    }

    /// Four bytes at a time, so the copy loop runs several times per file.
    func readChunk() async throws -> Data? {
        guard !remaining.isEmpty else {
            return nil
        }
        let chunk = Data(remaining.prefix(4))
        remaining = Data(remaining.dropFirst(chunk.count))
        return chunk
    }

    func close() {}
}

private final class ScriptedFiles: ChatExportFileProvider {
    var contents: [Int64: Data] = [:]
    var failing: Set<Int64> = []
    var cancelled: Set<Int64> = []

    func openFile(for attachment: ChatExportAttachment) async throws -> ChatExportFileStream? {
        if cancelled.contains(attachment.id) {
            throw CancellationError()
        }
        if failing.contains(attachment.id) {
            throw ScriptedFailure()
        }
        guard let data = contents[attachment.id] else {
            return nil
        }
        return ScriptedStream(data)
    }
}

final class ChatExportArchiveTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private var header: ChatExportHeader {
        ChatExportHeader(accountLabel: "Account A", chatTitle: "Chat", exportedAt: date("2026-11-19T10:00:00Z"))
    }

    private func photo(_ id: Int64, size: Int64 = 3, fileName: String = "pic.jpg") -> ChatExportAttachment {
        ChatExportAttachment(id: id, kind: .photo, fileName: fileName, mimeType: "image/jpeg", size: size)
    }

    private func message(_ id: Int64, attachment: ChatExportAttachment? = nil, text: String = "hi") -> ChatExportMessage {
        ChatExportMessage(
            id: id,
            date: date("2026-11-01T12:00:00Z"),
            senderName: "Ann",
            text: text,
            mediaKind: attachment == nil ? nil : "photo",
            attachment: attachment
        )
    }

    private func runExport(
        pages: [[ChatExportMessage]],
        files: ScriptedFiles,
        limits: ChatExportMediaLimits = .standard,
        documentBufferBytes: Int = 16 * 1024 * 1024,
        format: ChatExportFormat = .json
    ) async throws -> (summary: ChatExportSummary, archive: MemorySink, history: ScriptedHistory, progress: ChatExportProgress?) {
        let history = ScriptedHistory(pages: pages)
        let archive = MemorySink()
        let recorder = ProgressRecorder()
        let job = ChatExportArchiveJob(
            format: format,
            header: header,
            range: ChatExportRange(calendar: utc),
            history: history,
            files: files,
            destination: archive,
            limits: limits,
            documentBufferBytes: documentBufferBytes,
            calendar: utc,
            cleanup: {},
            onProgress: { recorder.last = $0 }
        )
        let summary = try await job.run()
        return (summary, archive, history, recorder.last)
    }

    func testArchiveHoldsTheDocumentAndTheCopiedMedia() async throws {
        let files = ScriptedFiles()
        files.contents = [1: Data("abc".utf8), 2: Data("defgh".utf8)]
        let result = try await runExport(
            pages: [[message(10, attachment: photo(1)), message(11, attachment: photo(2, size: 5)), message(12)]],
            files: files
        )
        XCTAssertEqual(result.summary.mediaFiles, 2)
        XCTAssertEqual(result.summary.skippedMedia, 0)
        XCTAssertTrue(result.archive.text.contains("media/10_pic.jpg"))
        XCTAssertTrue(result.archive.text.contains("media/11_pic.jpg"))
        XCTAssertTrue(result.archive.text.contains("messages.json"))
        XCTAssertTrue(result.archive.text.contains("\"exportedPath\":\"media/10_pic.jpg\""))
        XCTAssertTrue(result.archive.text.contains("\"durationSeconds\":0"))
        XCTAssertTrue(result.archive.text.contains("\"width\":0"))
    }

    func testUnknownSizeFailedOpenAndMissingFilesAreSkipped() async throws {
        let files = ScriptedFiles()
        files.contents = [2: Data("xyz".utf8)]
        files.failing = [3]
        let result = try await runExport(
            pages: [[
                message(20, attachment: photo(1, size: 0)),
                message(21, attachment: photo(2)),
                message(22, attachment: photo(3)),
                message(23, attachment: photo(4)),
            ]],
            files: files
        )
        XCTAssertEqual(result.summary.mediaFiles, 1)
        XCTAssertEqual(result.summary.skippedMedia, 3)
        XCTAssertTrue(result.archive.text.contains("media/21_pic.jpg"))
        XCTAssertTrue(result.archive.text.contains("\"exportedPath\":null"))
    }

    func testLimitsStopCopyingAndCountTheRest() async throws {
        let files = ScriptedFiles()
        files.contents = [1: Data("aaa".utf8), 2: Data("bbb".utf8), 3: Data("ccc".utf8), 4: Data("ddd".utf8)]
        let limits = ChatExportMediaLimits(maxFiles: 2, maxSingleFileBytes: 100, maxTotalBytes: 150)
        let result = try await runExport(
            pages: [[
                message(30, attachment: photo(1, size: 60)),
                message(31, attachment: photo(2, size: 60)),
                message(32, attachment: photo(3, size: 60)),
                message(33, attachment: photo(4, size: 101)),
            ]],
            files: files,
            limits: limits
        )
        XCTAssertEqual(result.summary.mediaFiles, 2)
        XCTAssertEqual(result.summary.skippedMedia, 2)
        XCTAssertFalse(result.archive.text.contains("media/32_"))
        XCTAssertFalse(result.archive.text.contains("media/33_"))
    }

    func testDocumentLargerThanTheBufferIsRenderedAgainWithoutCopyingTwice() async throws {
        let files = ScriptedFiles()
        files.contents = [1: Data("abc".utf8)]
        let result = try await runExport(
            pages: [[message(40, attachment: photo(1))], [message(41, text: "later")]],
            files: files,
            documentBufferBytes: 16
        )
        XCTAssertEqual(result.history.rewinds, 1)
        XCTAssertEqual(result.summary.mediaFiles, 1)
        XCTAssertEqual(result.summary.exportedMessages, 2)
        XCTAssertTrue(result.archive.text.contains("\"exportedPath\":\"media/40_pic.jpg\""))
        // Two messages, one copied file. The second pass must not count them again.
        XCTAssertEqual(result.progress?.processedMessages, 2)
        XCTAssertEqual(result.progress?.exportedMessages, 2)
        XCTAssertEqual(result.progress?.mediaCopied, 1)
    }

    func testCancellationStopsTheExportAndCleansUp() async throws {
        let files = ScriptedFiles()
        files.cancelled = [1]
        let history = ScriptedHistory(pages: [[message(50, attachment: photo(1))]])
        var cleaned = false
        let job = ChatExportArchiveJob(
            format: .json,
            header: header,
            range: ChatExportRange(calendar: utc),
            history: history,
            files: files,
            destination: MemorySink(),
            calendar: utc,
            cleanup: { cleaned = true },
            onProgress: { _ in }
        )
        do {
            _ = try await job.run()
            XCTFail("the export should have been cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(cleaned)
    }

    func testHTMLDocumentLinksImagesAndNotesMissingFiles() async throws {
        let files = ScriptedFiles()
        files.contents = [1: Data("abc".utf8)]
        let result = try await runExport(
            pages: [[
                message(70, attachment: photo(1)),
                message(71, attachment: ChatExportAttachment(id: 2, kind: .document, fileName: "a b.pdf", mimeType: "application/pdf", size: 9)),
            ]],
            files: files,
            format: .html
        )
        XCTAssertTrue(result.archive.text.contains("messages.html"))
        XCTAssertTrue(result.archive.text.contains("<img loading=\"lazy\" src=\"media/70_pic.jpg\" alt=\"pic.jpg\">"))
        XCTAssertTrue(result.archive.text.contains("<figcaption>Document · a b.pdf · 9 bytes <span class=\"missing\">not included</span></figcaption>"))
        // The figure names the kind, so the bracketed prefix is not repeated.
        XCTAssertFalse(result.archive.text.contains("[photo] "))
    }

    func testEntryNamesFollowTheAndroidRules() {
        XCTAssertEqual(
            ChatExportFileName.mediaEntryName(
                messageId: 7,
                attachment: ChatExportAttachment(id: 1, kind: .photo, fileName: "My Pic.JPG", mimeType: "image/jpeg", size: 1)
            ),
            "media/7_My Pic.jpg"
        )
        XCTAssertEqual(
            ChatExportFileName.mediaEntryName(
                messageId: 9,
                attachment: ChatExportAttachment(id: 2, kind: .document, fileName: "", mimeType: "", size: 1)
            ),
            "media/9_document.bin"
        )
        XCTAssertEqual(
            ChatExportFileName.mediaEntryName(
                messageId: 3,
                attachment: ChatExportAttachment(id: 3, kind: .voice, fileName: "a/b:c.txt", mimeType: "text/plain", size: 1)
            ),
            "media/3_a_b_c.txt"
        )
        XCTAssertEqual(
            ChatExportFileName.mediaEntryName(
                messageId: 4,
                attachment: ChatExportAttachment(id: 4, kind: .voice, fileName: "", mimeType: "audio/ogg; codecs=opus", size: 1)
            ),
            "media/4_voice.ogg"
        )
    }

    func testWhitespaceInNamesIsASCIIOnlyAsOnAndroid() {
        // Java's \s does not match U+00A0, so Android keeps a non-breaking space inside a name.
        XCTAssertEqual(
            ChatExportFileName.mediaEntryName(
                messageId: 5,
                attachment: ChatExportAttachment(id: 5, kind: .photo, fileName: "a\u{00A0}\u{00A0}b.png", mimeType: "", size: 1)
            ),
            "media/5_a\u{00A0}\u{00A0}b.png"
        )
    }

    func testLongNamesAreCutToEightyUTF16Units() {
        let long = String(repeating: "é", count: 100)
        let name = ChatExportFileName.mediaEntryName(
            messageId: 1,
            attachment: ChatExportAttachment(id: 1, kind: .photo, fileName: long + ".png", mimeType: "", size: 1)
        )
        XCTAssertEqual(name, "media/1_" + String(repeating: "é", count: 80) + ".png")
    }

    func testTextOnlyMessagesHaveANullMediaObject() throws {
        let sink = MemorySink()
        let writer = ChatExportWriter(format: .json, header: header, range: ChatExportRange(calendar: utc), sink: sink)
        try writer.begin()
        XCTAssertTrue(writer.accepts(message(60)))
        try writer.append(message(60))
        _ = try writer.finish()
        let object = try JSONSerialization.jsonObject(with: sink.data) as? [String: Any]
        let messages = object?["messages"] as? [[String: Any]]
        XCTAssertTrue(messages?.first?["media"] is NSNull)
    }
}
