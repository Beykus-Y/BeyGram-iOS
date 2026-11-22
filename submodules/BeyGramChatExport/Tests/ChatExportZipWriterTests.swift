import XCTest
@testable import BeyGramChatExport

private final class ZipTestSink: ChatExportSink {
    var data = Data()
    func write(_ chunk: Data) throws {
        data.append(chunk)
    }
}

private func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
}

private func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(readUInt16(bytes, offset)) | (UInt32(readUInt16(bytes, offset + 2)) << 16)
}

final class ChatExportZipWriterTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testCRC32MatchesStandardCheckValue() {
        XCTAssertEqual(ChatExportZipWriter.crc32(of: Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(ChatExportZipWriter.crc32(of: Data()), 0)
    }

    func testEmptyArchiveIsOnlyTheEndRecord() throws {
        let sink = ZipTestSink()
        let zip = ChatExportZipWriter(sink: sink, calendar: utc)
        try zip.finish()
        XCTAssertEqual(sink.data.count, 22)
        XCTAssertEqual(Array(sink.data.prefix(4)), [0x50, 0x4B, 0x05, 0x06])
    }

    func testEntryLayoutDescriptorAndDirectory() throws {
        let sink = ZipTestSink()
        let zip = ChatExportZipWriter(sink: sink, calendar: utc)
        try zip.addEntry(name: "messages.json", modified: date("2026-11-19T10:00:00Z"), contents: Data("{}".utf8))
        try zip.finish()
        let bytes = [UInt8](sink.data)
        // Local header: signature, then flags 0x0808 (data descriptor and UTF-8 names) at offset 6.
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(readUInt16(bytes, 6), 0x0808)
        // The data descriptor follows the 30-byte header, the 13-byte name and the 2 content bytes.
        let descriptor = 30 + "messages.json".utf8.count + 2
        XCTAssertEqual(readUInt32(bytes, descriptor), 0x0807_4B50)
        XCTAssertEqual(readUInt32(bytes, descriptor + 4), ChatExportZipWriter.crc32(of: Data("{}".utf8)))
        XCTAssertEqual(readUInt32(bytes, descriptor + 8), 2)
        XCTAssertEqual(readUInt32(bytes, descriptor + 12), 2)
        // The central directory record follows the 16-byte descriptor.
        let central = descriptor + 16
        XCTAssertEqual(readUInt32(bytes, central), 0x0201_4B50)
        // The end record is the last 22 bytes: one entry, and the directory starts at `central`.
        let end = bytes.count - 22
        XCTAssertEqual(readUInt32(bytes, end), 0x0605_4B50)
        XCTAssertEqual(readUInt16(bytes, end + 8), 1)
        XCTAssertEqual(readUInt16(bytes, end + 10), 1)
        XCTAssertEqual(readUInt32(bytes, end + 16), UInt32(central))
    }

    func testDosDateAndTimeAreInLocalTime() throws {
        let sink = ZipTestSink()
        let zip = ChatExportZipWriter(sink: sink, calendar: utc)
        try zip.addEntry(name: "a", modified: date("2026-11-19T10:00:00Z"), contents: Data())
        try zip.finish()
        let bytes = [UInt8](sink.data)
        // Local header: time at offset 10, date at offset 12.
        XCTAssertEqual(readUInt16(bytes, 10), UInt16(10 << 11))
        XCTAssertEqual(readUInt16(bytes, 12), UInt16(((2026 - 1980) << 9) | (11 << 5) | 19))
    }

    func testEntrySinkStreamsIntoTheOpenEntry() throws {
        let sink = ZipTestSink()
        let zip = ChatExportZipWriter(sink: sink, calendar: utc)
        try zip.beginEntry(name: "messages.html", modified: Date())
        let entrySink = ChatExportZipEntrySink(zip: zip)
        try entrySink.write(Data("<p>".utf8))
        try entrySink.write(Data("hi".utf8))
        try zip.endEntry()
        try zip.finish()
        let bytes = [UInt8](sink.data)
        // "messages.html" is 13 bytes long, so the descriptor follows 30 + 13 + 5 bytes.
        let descriptor = 30 + "messages.html".utf8.count + 5
        XCTAssertEqual(readUInt32(bytes, descriptor + 8), 5)
        XCTAssertEqual(readUInt32(bytes, descriptor + 4), ChatExportZipWriter.crc32(of: Data("<p>hi".utf8)))
    }

    func testRejectsInvalidStatesAndNames() throws {
        let sink = ZipTestSink()
        let zip = ChatExportZipWriter(sink: sink, calendar: utc)
        XCTAssertThrowsError(try zip.write(Data([1]))) { error in
            XCTAssertEqual(error as? ChatExportZipError, .noOpenEntry)
        }
        XCTAssertThrowsError(try zip.beginEntry(name: "/absolute", modified: Date())) { error in
            XCTAssertEqual(error as? ChatExportZipError, .invalidName)
        }
        try zip.beginEntry(name: "a", modified: Date())
        XCTAssertThrowsError(try zip.beginEntry(name: "b", modified: Date())) { error in
            XCTAssertEqual(error as? ChatExportZipError, .entryAlreadyOpen)
        }
        try zip.endEntry()
        try zip.finish()
        XCTAssertThrowsError(try zip.finish()) { error in
            XCTAssertEqual(error as? ChatExportZipError, .finished)
        }
    }
}
