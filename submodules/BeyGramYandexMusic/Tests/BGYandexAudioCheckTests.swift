import XCTest
@testable import BeyGramYandexMusic

final class BGYandexAudioCheckTests: XCTestCase {
    private let id3Start = Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    private let frameStart = Data([0xFF, 0xFB, 0x90, 0x64])

    private func verdict(_ header: Data,
                         bytes: Int64 = 100_000,
                         expected: Int64 = -1,
                         type: String? = "audio/mpeg") -> BGYandexAudioCheck.Verdict {
        return BGYandexAudioCheck.inspect(header: header, byteCount: bytes, expectedLength: expected, contentType: type).verdict
    }

    func testTaggedTrackIsKept() {
        XCTAssertEqual(verdict(id3Start), .audio)
    }

    func testFrameStartTrackIsKept() {
        XCTAssertEqual(verdict(frameStart), .audio)
    }

    func testHTMLErrorPageIsRefused() {
        let page = Data("<!DOCTYPE html><html><body>Error</body></html>".utf8)
        XCTAssertEqual(verdict(page, type: nil), .notMP3)
    }

    func testJSONAnswerIsRefusedByItsType() {
        let body = Data("{\"error\":\"forbidden\"}".utf8)
        XCTAssertEqual(verdict(body, type: "application/json"), .nonAudioType)
    }

    func testTextTypeIsRefusedEvenWithAudioBytes() {
        XCTAssertEqual(verdict(id3Start, type: "text/html; charset=utf-8"), .nonAudioType)
    }

    func testSmallBodyIsRefused() {
        XCTAssertEqual(verdict(id3Start, bytes: 512), .tooSmall)
    }

    func testEmptyFileIsRefused() {
        XCTAssertEqual(verdict(Data(), bytes: 0), .tooSmall)
    }

    func testCutOffBodyIsRefused() {
        XCTAssertEqual(verdict(id3Start, bytes: 50_000, expected: 80_000), .cutOff)
    }

    func testMatchingLengthIsKept() {
        XCTAssertEqual(verdict(id3Start, bytes: 50_000, expected: 50_000), .audio)
    }

    func testUnannouncedLengthIsNotCompared() {
        XCTAssertEqual(verdict(id3Start, bytes: 50_000, expected: -1), .audio)
    }

    func testProbeNamesOnlySizesHeadAndType() {
        let probe = BGYandexAudioCheck.inspect(header: Data("<!DO".utf8),
                                               byteCount: 5,
                                               expectedLength: -1,
                                               contentType: "text/html; charset=utf-8")
        XCTAssertEqual(probe.description, "verdict=nonAudioType bytes=5 expected=-1 head=3c21444f type=text/html")
    }

    func testCachedHTMLFileIsRefusedOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bgyandex-\(UUID().uuidString).mp3")
        try Data(String(repeating: "<html>", count: 2000).utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(BGYandexAudioCheck.inspect(fileAt: url).verdict, .notMP3)
    }

    func testInvalidFileReachesThePlayerAsItsOwnError() {
        XCTAssertEqual(BGYandexPlayback.error(for: .invalidFile), .invalidFile)
    }

    func testLegacyCachedM4AWithMP3ExtensionIsNormalizedInPlace() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bgyandex-resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Valid M4A ftyp header (> 8 KiB) stored with legacy .mp3 extension.
        var m4aBytes = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20])
        m4aBytes.append(Data(repeating: 0x00, count: 10_000))
        let legacyURL = dir.appendingPathComponent("ym-777.mp3")
        try m4aBytes.write(to: legacyURL)

        let resolver = BGYandexTrackResolver(cacheDirectory: dir)
        var linkProviderCalled = false
        resolver.linkProvider = { _, done in
            linkProviderCalled = true
            done(.failure(.network))
        }

        let exp = expectation(description: "localFile")
        var resolvedURL: URL?
        resolver.localFile(trackId: "777") { result in
            if case let .success(url) = result {
                resolvedURL = url
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertFalse(linkProviderCalled, "valid cached audio must not be re-downloaded")
        XCTAssertEqual(resolvedURL?.lastPathComponent, "ym-777.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ym-777.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    }
}
