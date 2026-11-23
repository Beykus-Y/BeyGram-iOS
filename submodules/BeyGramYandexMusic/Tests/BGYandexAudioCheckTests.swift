import XCTest
import AVFoundation
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

    func testSyntheticMP3FixtureIsAcceptedAndFullyDecoded() throws {
        let url = try self.fixtureURL()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        let header = try handle.read(upToCount: BGYandexAudioCheck.headerByteCount) ?? Data()
        try handle.close()

        XCTAssertEqual(BGYandexAudioCheck.inspect(header: header,
                                                  byteCount: byteCount,
                                                  expectedLength: byteCount,
                                                  contentType: "audio/mpeg").verdict, .audio)

        let file = try AVAudioFile(forReading: url)
        var decodedFrames: AVAudioFramePosition = 0
        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(min(4096, file.length - file.framePosition))
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: remaining)!
            try file.read(into: buffer, frameCount: remaining)
            if buffer.frameLength == 0 {
                break
            }
            decodedFrames += AVAudioFramePosition(buffer.frameLength)
        }
        XCTAssertGreaterThan(decodedFrames, 44_100)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(file.processingFormat.sampleRate, 44_100, accuracy: 1)
    }

    func testHeaderOnlyCorruptCacheIsRefusedByDecoderAndCanBeDiscarded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bgyandex-corrupt-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = try self.fixtureURL()
        let fixtureHandle = try FileHandle(forReadingFrom: fixture)
        let firstFrameHeader = try fixtureHandle.read(upToCount: 4) ?? Data()
        try fixtureHandle.close()
        var corrupt = Data(repeating: 0, count: Int(BGYandexAudioCheck.minimumByteCount) + 128)
        corrupt.replaceSubrange(0..<firstFrameHeader.count, with: firstFrameHeader)

        let cacheFile = directory.appendingPathComponent(BGYandexTrackResolver.fileName(trackId: "789"))
        try corrupt.write(to: cacheFile)
        XCTAssertEqual(BGYandexAudioCheck.inspect(fileAt: cacheFile).verdict, .audio,
                       "the fast check is only a container hint; AVFoundation decides whether the body decodes")

        var decodedFrames: AVAudioFramePosition = 0
        do {
            let file = try AVAudioFile(forReading: cacheFile)
            while true {
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
                try file.read(into: buffer, frameCount: buffer.frameCapacity)
                if buffer.frameLength == 0 { break }
                decodedFrames += AVAudioFramePosition(buffer.frameLength)
            }
        } catch {
            // An open/read error is a decoder refusal. If AVFoundation tolerates the first frame, the frame-count
            // assertion still requires that the body be far shorter than the real fixture it impersonates.
        }
        XCTAssertLessThan(decodedFrames, 22_050)

        let service = BGYandexService(
            credentials: BGYandexCredentials(clientId: "id", clientSecret: "secret"),
            cacheDirectory: directory
        )
        service.discardUnplayableFile(rowKey: "ym:789:654")
        XCTAssertNil(service.resolver.cachedFile(trackId: "789"))
    }

    func testTruncatedRealMP3BodyFailsAnnouncedLengthCheck() throws {
        let complete = try Data(contentsOf: self.fixtureURL())
        XCTAssertEqual(BGYandexAudioCheck.inspect(header: Data(complete.prefix(BGYandexAudioCheck.headerByteCount)),
                                                  byteCount: Int64(complete.count),
                                                  expectedLength: Int64(complete.count) + 4_096,
                                                  contentType: "audio/mpeg").verdict, .cutOff)
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

    private func fixtureURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let runfiles = environment["TEST_SRCDIR"] ?? FileManager.default.currentDirectoryPath
        let workspace = environment["TEST_WORKSPACE"] ?? ""
        let path = URL(fileURLWithPath: runfiles)
            .appendingPathComponent(workspace)
            .appendingPathComponent("submodules/BeyGramYandexMusic/Tests/Fixtures/synthetic-tone.mp3")
        if FileManager.default.fileExists(atPath: path.path) {
            return path.resolvingSymlinksInPath()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("submodules/BeyGramYandexMusic/Tests/Fixtures/synthetic-tone.mp3")
            .resolvingSymlinksInPath()
    }
}
