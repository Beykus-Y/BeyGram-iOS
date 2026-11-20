import XCTest
@testable import BeyGramChatExport

private final class CountingSink: ChatExportSink {
    var bytes = 0
    func write(_ data: Data) throws { bytes += data.count }
}

final class ChatExportJobTests: XCTestCase {
    private func message(_ id: Int64) -> ChatExportMessage {
        ChatExportMessage(id: id, date: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)), senderName: "A", text: "m\(id)")
    }

    private var header: ChatExportHeader {
        ChatExportHeader(accountLabel: "a", chat: ChatExportChat(id: 1, title: "c", kind: "private"), exportedAt: Date())
    }

    func testRunsAllPagesAndReportsProgress() async throws {
        let sink = CountingSink()
        let writer = ChatExportWriter(format: .json, header: header, range: ChatExportRange(), sink: sink)
        var pages: [[ChatExportMessage]] = [[message(1), message(2)], [message(3)], []]
        var lastProgress: ChatExportProgress?
        var cleaned = false
        let job = ChatExportJob(writer: writer, cleanup: { cleaned = true }, onProgress: { lastProgress = $0 })
        let summary = try await job.run { pages.removeFirst() }
        XCTAssertEqual(summary.exportedMessages, 3)
        XCTAssertEqual(lastProgress?.pagesLoaded, 2)
        XCTAssertFalse(cleaned)
    }

    func testErrorRunsCleanupAndRethrows() async {
        let writer = ChatExportWriter(format: .html, header: header, range: ChatExportRange(), sink: CountingSink())
        var cleaned = false
        let job = ChatExportJob(writer: writer, cleanup: { cleaned = true }, onProgress: { _ in })
        struct Boom: Error {}
        do {
            _ = try await job.run { throw Boom() }
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error is Boom)
            XCTAssertTrue(cleaned)
        }
    }
}
