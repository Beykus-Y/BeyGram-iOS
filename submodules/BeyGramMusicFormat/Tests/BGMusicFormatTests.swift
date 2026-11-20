import XCTest
@testable import BeyGramMusicFormat

/// A ZIP with one deflated `manifest.json`, built by zlib in a helper script and checked by hand.
/// Plain manifest: 192 bytes. CRC-32: 0x99589F54.
private let deflatedManifestZip: [UInt8] = [
        0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00,
        0x21, 0x00, 0x54, 0x9F, 0x58, 0x99, 0x98, 0x00, 0x00, 0x00, 0xC0, 0x00,
        0x00, 0x00, 0x0D, 0x00, 0x00, 0x00, 0x6D, 0x61, 0x6E, 0x69, 0x66, 0x65,
        0x73, 0x74, 0x2E, 0x6A, 0x73, 0x6F, 0x6E, 0x55, 0x8E, 0xEF, 0x0A, 0x82,
        0x30, 0x14, 0xC5, 0xDF, 0xE5, 0x7E, 0xD6, 0x70, 0x6A, 0x5A, 0xBE, 0x4A,
        0xC4, 0xB8, 0xDB, 0xEE, 0x62, 0xE4, 0x54, 0xB6, 0x29, 0x48, 0x04, 0xD1,
        0xAB, 0xF4, 0x1E, 0x3D, 0x83, 0xBE, 0x51, 0x8B, 0x82, 0xE8, 0x7C, 0x3C,
        0x7F, 0x7E, 0x9C, 0x0B, 0xE8, 0xDE, 0x59, 0x0C, 0xD0, 0x80, 0xA0, 0xF9,
        0xE4, 0xD0, 0x6E, 0xEC, 0xE8, 0x8D, 0x84, 0xE4, 0x1B, 0xF0, 0x89, 0x9C,
        0x37, 0x7D, 0x07, 0x0D, 0x4B, 0xC0, 0x9A, 0x8E, 0x3B, 0x42, 0x45, 0xEE,
        0xCF, 0x1E, 0x5A, 0x9C, 0x5B, 0xE3, 0x03, 0x37, 0x2A, 0x72, 0x2A, 0xCD,
        0x54, 0x2E, 0x0B, 0x4C, 0x4B, 0xB1, 0xA5, 0xB4, 0xD4, 0x55, 0x96, 0xEE,
        0xB0, 0x16, 0xE9, 0x5E, 0x66, 0x8A, 0x51, 0xAE, 0x0B, 0x2C, 0x45, 0xC4,
        0x3B, 0x9A, 0xCC, 0x87, 0x50, 0x24, 0x10, 0x4C, 0x68, 0x29, 0x6E, 0x97,
        0xC7, 0x7A, 0x5F, 0x6F, 0xCB, 0x33, 0xE6, 0xE3, 0xA0, 0x30, 0x90, 0xE2,
        0xEF, 0x6F, 0xAC, 0xCE, 0x7E, 0x8A, 0x6D, 0x87, 0xF2, 0xEC, 0xA1, 0x39,
        0x1C, 0xAF, 0x2F, 0x50, 0x4B, 0x01, 0x02, 0x14, 0x00, 0x14, 0x00, 0x00,
        0x00, 0x08, 0x00, 0x00, 0x00, 0x21, 0x00, 0x54, 0x9F, 0x58, 0x99, 0x98,
        0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x0D, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x6D, 0x61, 0x6E, 0x69, 0x66, 0x65, 0x73, 0x74, 0x2E, 0x6A, 0x73,
        0x6F, 0x6E, 0x50, 0x4B, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x01, 0x00, 0x3B, 0x00, 0x00, 0x00, 0xC3, 0x00, 0x00, 0x00, 0x00, 0x00,
]

/// Raw DEFLATE of `hello hello hello hello, bgmusic!` (zlib level 9, no header).
private let deflatedHello: [UInt8] = [
        0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x27, 0x75, 0x14, 0x92, 0xD2, 0x73, 0x4B, 0x8B, 0x33, 0x93, 0x15, 0x01,
]

final class BGMusicFormatTests: XCTestCase {
    private let validUUID = "6f1d2c3a-4b5e-4f60-8a7b-9c0d1e2f3a4b"
    private let trackUUID = "0d6f3c1e-7a2b-4c5d-9e8f-1a2b3c4d5e6f"

    // MARK: Text cleaning (section 7)

    func testLineBreaksInSingleLineBecomeSpaces() {
        XCTAssertEqual(BGMusicText.singleLine("a\nb\r\nc", maxLength: 100), "a b c")
    }

    func testControlCharacterDoesNotBreakBreakRun() {
        // `a`, LF, U+0007, LF, LF, `b` gives `a`, LF, LF, `b`: the removed control does not split the run.
        XCTAssertEqual(BGMusicText.multiline("a\n\u{0007}\n\nb", maxLength: 1000), "a\n\nb")
    }

    func testBidiOverrideAndZeroWidthSpaceAreRemoved() {
        XCTAssertEqual(BGMusicText.singleLine("a\u{202E}b\u{200B}c", maxLength: 100), "abc")
    }

    func testZeroWidthJoinerIsKept() {
        XCTAssertEqual(BGMusicText.singleLine("a\u{200D}b", maxLength: 100), "a\u{200D}b")
    }

    func testTruncationCountsCodePoints() {
        let result = BGMusicText.singleLine(String(repeating: "a", count: 300), maxLength: 128)
        XCTAssertEqual(result.unicodeScalars.count, 128)
    }

    func testCleaningIsIdempotent() {
        let once = BGMusicText.multiline("  x\u{0008}\n\n\n\ny  ", maxLength: 1000)
        XCTAssertEqual(BGMusicText.multiline(once, maxLength: 1000), once)
    }

    // MARK: Strict JSON (section 3)

    func testStrictJSONRejectsDuplicateKeys() {
        XCTAssertEqual(BGMusicStrictJSON.parse(Data("{\"a\":1,\"a\":2}".utf8)), .failure(.duplicateKey))
    }

    func testStrictJSONRejectsTrailingCommaAndSingleQuotes() {
        XCTAssertEqual(BGMusicStrictJSON.parse(Data("[1,2,]".utf8)), .failure(.invalid))
        XCTAssertEqual(BGMusicStrictJSON.parse(Data("{'a':1}".utf8)), .failure(.invalid))
    }

    func testStrictJSONRejectsDataAfterValue() {
        XCTAssertEqual(BGMusicStrictJSON.parse(Data("{} x".utf8)), .failure(.invalid))
    }

    func testStrictJSONRejectsDepthAboveSixteen() {
        let deep = String(repeating: "[", count: 17) + String(repeating: "]", count: 17)
        XCTAssertEqual(BGMusicStrictJSON.parse(Data(deep.utf8)), .failure(.tooDeep))
        let ok = String(repeating: "[", count: 16) + String(repeating: "]", count: 16)
        XCTAssertNotNil(try? BGMusicStrictJSON.parse(Data(ok.utf8)).get())
    }

    func testStrictJSONAcceptsBOMAndEscapes() {
        let parsed = BGMusicStrictJSON.parse(Data([0xEF, 0xBB, 0xBF] + Array("{\"s\":\"\\u0041\\n\"}".utf8)))
        XCTAssertEqual(try? parsed.get(), .object([("s", .string("A\n"))]))
    }

    // MARK: Manifest (section 3.3 example and round trip)

    func testSpecExampleManifestDecodes() {
        let example = """
        {"format":"beygram.music","format_version":1,"min_reader_version":1,
          "playlist_id":"6f1d2c3a-4b5e-4f60-8a7b-9c0d1e2f3a4b","revision":3,"title":"Утро",
          "description":"","updated_at":1700000000000,
          "tracks":[{"id":"0d6f3c1e-7a2b-4c5d-9e8f-1a2b3c4d5e6f","title":"Song","artist":"Artist","album":"",
            "duration_sec":215,"sources":[{"type":"telegram_public","username":"some_channel","message_id":42}]}]}
        """
        guard case let .success(manifest) = BGMusicManifest.decode(Data(example.utf8)) else {
            return XCTFail("spec example must decode")
        }
        XCTAssertEqual(manifest.revision, 3)
        XCTAssertEqual(manifest.tracks.first?.sources, [.telegramPublic(username: "some_channel", messageId: 42)])
    }

    func testUnsupportedWhenMinReaderIsNewer() {
        let json = #"{"format":"beygram.music","format_version":2,"min_reader_version":2,"playlist_id":"\#(validUUID)","revision":0,"title":"t","updated_at":0,"tracks":[]}"#
        XCTAssertEqual(BGMusicManifest.decode(Data(json.utf8)), .unsupported(formatVersion: 2, minReaderVersion: 2))
    }

    func testBadSignatureIsReportedBeforeOtherFields() {
        XCTAssertEqual(BGMusicManifest.decode(Data(#"{"format":"x"}"#.utf8)), .invalid(.badSignature))
    }

    func testWriteThenDecodeRoundTrip() throws {
        let manifest = BGMusicManifest(
            playlistId: validUUID.uppercased(), revision: 7, title: "  Утро\n", description: "a\n\n\n\nb",
            updatedAt: 1, authorName: nil,
            tracks: [BGMusicTrack(id: trackUUID, title: "Song", artist: "", album: "", durationSec: 60, audioHash: nil,
                                  sources: [.telegramPublic(username: "channel_x", messageId: 9)])])
        let json = try manifest.jsonData()
        guard case let .success(decoded) = BGMusicManifest.decode(json) else {
            return XCTFail("written manifest must read back")
        }
        XCTAssertEqual(decoded.playlistId, validUUID)
        XCTAssertEqual(decoded.title, "Утро")
        XCTAssertEqual(decoded.description, "a\n\nb")
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("null"))
    }

    func testRejectsTooManyTracks() {
        let track = BGMusicTrack(id: trackUUID, title: "t", artist: "", album: "", durationSec: 0, audioHash: nil, sources: [])
        let manifest = BGMusicManifest(playlistId: validUUID, revision: 0, title: "t", description: "", updatedAt: 0, authorName: nil,
                                       tracks: Array(repeating: track, count: BGMusicManifest.maxTracks + 1))
        XCTAssertThrowsError(try manifest.normalized())
    }

    // MARK: Track keys (Android row keys)

    func testTrackKeysRoundTrip() {
        XCTAssertEqual(BGMusicTrackKey(string: "ym:123:9"), .yandex(trackId: "123", albumId: "9"))
        XCTAssertEqual(BGMusicTrackKey(string: "ym:123:"), .yandex(trackId: "123", albumId: nil))
        XCTAssertEqual(BGMusicTrackKey(string: "bot:12:abc"), .bot(queryId: 12, resultId: "abc"))
        XCTAssertNil(BGMusicTrackKey(string: "bot:x:abc"))
        XCTAssertEqual(BGMusicTrackKey(string: "ym:123:9")?.string, "ym:123:9")
    }

    // MARK: ZIP container and DEFLATE

    func testInflateStoredPayloadFromFixture() throws {
        let plain = try BGMusicInflate.inflate(deflatedHello, limit: 100)
        XCTAssertEqual(String(decoding: plain, as: UTF8.self), "hello hello hello hello, bgmusic!")
    }

    func testInflateRefusesOutputAboveLimit() {
        XCTAssertThrowsError(try BGMusicInflate.inflate(deflatedHello, limit: 4))
    }

    func testReadDeflatedArchive() {
        guard case let .success(contents) = BGMusicArchive.read(Data(deflatedManifestZip)) else {
            return XCTFail("deflated archive must read")
        }
        XCTAssertNil(contents.cover)
        XCTAssertEqual(BGMusicManifest.decode(contents.manifest).isSuccess, true)
    }

    func testWriteThenReadArchive() {
        let manifest = Data("{\"format\":\"beygram.music\"}".utf8)
        let zip = try! BGMusicArchive.write(manifest: manifest, cover: nil).get()
        guard case let .success(contents) = BGMusicArchive.read(zip) else {
            return XCTFail("written archive must read back")
        }
        XCTAssertEqual(contents.manifest, manifest)
    }

    func testNotZipIsRefused() {
        XCTAssertEqual(BGMusicArchive.read(Data("abc".utf8)).failureValue, .notZip)
    }

    func testCoverNameMustMatchMagicBytes() {
        let png = BGMusicCover(kind: .png, data: Data([0xFF, 0xD8, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BGMusicArchive.write(manifest: Data("{}".utf8), cover: png).failureValue, .badCover)
    }

    func testEmptyCoverIsRefused() {
        let empty = BGMusicCover(kind: .jpg, data: Data())
        XCTAssertEqual(BGMusicArchive.write(manifest: Data("{}".utf8), cover: empty).failureValue, .badCover)
    }
}

private extension Result {
    var failureValue: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private extension BGMusicDecodeResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
