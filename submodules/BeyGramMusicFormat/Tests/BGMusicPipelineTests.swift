import XCTest
@testable import BeyGramMusicFormat

/// Tests for the reader rules that were brought in line with docs/formats/bgmusic-v1.md and the Android reader, and for
/// the import and export layer. Not compiled or run yet: no macOS toolchain was available when they were written.
final class BGMusicPipelineTests: XCTestCase {
    private let playlistId = "6f1d2c3a-4b5e-4f60-8a7b-9c0d1e2f3a4b"
    private let otherId = "11111111-2222-4333-8444-555555555555"
    private let trackId = "0d6f3c1e-7a2b-4c5d-9e8f-1a2b3c4d5e6f"
    private let pngCover: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]

    // MARK: Text (section 7)

    func testEachLineBreakInASingleLineFieldIsOneSpace() {
        XCTAssertEqual(BGMusicText.singleLine("a\n\nb", maxLength: 100), "a  b")
    }

    func testDescriptionKeepsAtMostTwoLineFeeds() {
        XCTAssertEqual(BGMusicText.multiline("a\n\n\n\nb", maxLength: 100), "a\n\nb")
    }

    // MARK: Strict JSON (section 3)

    func testCanonicallyEqualKeysAreDifferentKeys() {
        // Precomposed and decomposed "é" are different keys to the Android reader, so they are different here too.
        let json = "{\"\u{E9}\":1,\"e\u{301}\":2}"
        XCTAssertNotNil(try? BGMusicStrictJSON.parse(Data(json.utf8)).get())
    }

    func testRepeatedKeyIsStillRefused() {
        XCTAssertEqual(BGMusicStrictJSON.parse(Data("{\"\u{E9}\":1,\"\u{E9}\":2}".utf8)), .failure(.duplicateKey))
    }

    func testMultiByteCharactersDecodeExactly() {
        let parsed = BGMusicStrictJSON.parse(Data("{\"s\":\"Утро 🎵 é\"}".utf8))
        XCTAssertEqual(try? parsed.get(), .object([("s", .string("Утро 🎵 é"))]))
    }

    // MARK: Manifest rules (section 3 and section 11)

    private func manifestData(tracks: String = "[]", extra: String = "") -> Data {
        let text = "{\"format\":\"beygram.music\",\"format_version\":1,\"min_reader_version\":1,\"playlist_id\":\"\(playlistId)\","
            + "\"revision\":1,\"title\":\"T\",\"updated_at\":1,\"tracks\":\(tracks)\(extra)}"
        return Data(text.utf8)
    }

    private var manifestBytes: [UInt8] {
        return [UInt8](manifestData())
    }

    /// A track object. `artist` nil leaves the field out, which the reader must refuse.
    private func trackData(_ extra: String = "", artist: String? = "Artist") -> String {
        let artistField = artist.map { "\"artist\":\"\($0)\"," } ?? ""
        return "{\"id\":\"\(trackId)\",\"title\":\"Song\",\(artistField)\"album\":\"\",\"duration_sec\":60\(extra)}"
    }

    /// The first track of a one-track manifest, or nil when the manifest is refused.
    private func decodedTrack(_ track: String) -> BGMusicTrack? {
        guard case let .success(manifest) = BGMusicManifest.decode(manifestData(tracks: "[\(track)]")) else {
            return nil
        }
        return manifest.tracks.first
    }

    func testDescriptionMustBeText() {
        XCTAssertEqual(BGMusicManifest.decode(manifestData(extra: ",\"description\":5")), .invalid(.badField("description")))
    }

    func testNullDescriptionReadsAsEmpty() {
        guard case let .success(manifest) = BGMusicManifest.decode(manifestData(extra: ",\"description\":null")) else {
            return XCTFail("a null description must read")
        }
        XCTAssertEqual(manifest.description, "")
    }

    func testAuthorIsAnObjectWithAName() {
        XCTAssertEqual(BGMusicManifest.decode(manifestData(extra: ",\"author\":\"Ilya\"")), .invalid(.badField("author")))
        XCTAssertEqual(BGMusicManifest.decode(manifestData(extra: ",\"author\":{}")), .invalid(.badField("author.name")))
        XCTAssertEqual(BGMusicManifest.decode(manifestData(extra: ",\"author\":{\"name\":\"   \"}")), .invalid(.badField("author.name")))
    }

    func testArtistIsRequiredButMayBeEmpty() {
        XCTAssertEqual(BGMusicManifest.decode(manifestData(tracks: "[\(trackData("", artist: nil))]")), .invalid(.badField("tracks")))
        XCTAssertEqual(decodedTrack(trackData("", artist: ""))?.artist, "")
    }

    func testBrokenAudioHashIsDroppedNotRefused() {
        let upper = "sha256:" + String(repeating: "A", count: 64)
        let track = decodedTrack(trackData(",\"audio_hash\":\"\(upper)\""))
        XCTAssertNotNil(track)
        XCTAssertNil(track?.audioHash)
    }

    func testLowercaseAudioHashIsKept() {
        let hash = "sha256:" + String(repeating: "a", count: 64)
        XCTAssertEqual(decodedTrack(trackData(",\"audio_hash\":\"\(hash)\""))?.audioHash, hash)
    }

    func testBrokenSourceHintsAreDroppedAndAtSignPrefixIsAccepted() {
        let sources = "[{\"type\":\"telegram_public\",\"username\":\"ab\",\"message_id\":1},"
            + "{\"type\":\"telegram_public\",\"username\":\"@valid_chan\",\"message_id\":5},"
            + "{\"type\":\"telegram_public\",\"username\":\"valid_chan\",\"message_id\":0},"
            + "{\"type\":\"other\",\"x\":1}]"
        let track = decodedTrack(trackData(",\"sources\":\(sources)"))
        XCTAssertEqual(track?.sources, [.telegramPublic(username: "valid_chan", messageId: 5)])
    }

    func testAtMostEightValidSourceHintsAreKept() {
        let items = (1...9).map { "{\"type\":\"telegram_public\",\"username\":\"channel_x\",\"message_id\":\($0)}" }
        let track = decodedTrack(trackData(",\"sources\":[\(items.joined(separator: ","))]"))
        XCTAssertEqual(track?.sources.count, 8)
        XCTAssertEqual(track?.sources.last, .telegramPublic(username: "channel_x", messageId: 8))
    }

    func testPlaylistIdIsASCIIHexOnly() {
        // U+FF16 (fullwidth 6) is a Unicode hex digit but not an ASCII one, and the spec allows only ASCII.
        let spoofed = "\u{FF16}" + String(playlistId.dropFirst())
        let text = "{\"format\":\"beygram.music\",\"format_version\":1,\"min_reader_version\":1,\"playlist_id\":\"\(spoofed)\","
            + "\"revision\":1,\"title\":\"T\",\"updated_at\":1,\"tracks\":[]}"
        XCTAssertEqual(BGMusicManifest.decode(Data(text.utf8)), .invalid(.badField("playlist_id")))
    }

    // MARK: Container (section 2 and section 6)

    private struct TestEntry {
        let name: String
        let content: [UInt8]
        /// The size written to the directory. Set it to a wrong value to act like a hostile archive.
        var declaredSize: Int?
    }

    /// A ZIP with stored entries, built byte by byte so that a test can declare sizes that do not match the bytes.
    private func zipData(_ entries: [TestEntry]) -> Data {
        var body: [UInt8] = []
        var directory: [UInt8] = []
        var offsets: [Int] = []
        for entry in entries {
            let name = Array(entry.name.utf8)
            let crc = Int(BGMusicCRC32.checksum(entry.content))
            offsets.append(body.count)
            putLittle(&body, 0x0403_4B50, 4)
            putLittle(&body, 20, 2)
            putLittle(&body, 0, 2)
            putLittle(&body, 0, 2)
            putLittle(&body, 0, 2)
            putLittle(&body, 0x21, 2)
            putLittle(&body, crc, 4)
            putLittle(&body, entry.content.count, 4)
            putLittle(&body, entry.content.count, 4)
            putLittle(&body, name.count, 2)
            putLittle(&body, 0, 2)
            body += name
            body += entry.content
        }
        let directoryOffset = body.count
        for (index, entry) in entries.enumerated() {
            let name = Array(entry.name.utf8)
            let crc = Int(BGMusicCRC32.checksum(entry.content))
            putLittle(&directory, 0x0201_4B50, 4)
            putLittle(&directory, 20, 2)
            putLittle(&directory, 20, 2)
            putLittle(&directory, 0, 2)
            putLittle(&directory, 0, 2)
            putLittle(&directory, 0, 2)
            putLittle(&directory, 0x21, 2)
            putLittle(&directory, crc, 4)
            putLittle(&directory, entry.content.count, 4)
            putLittle(&directory, entry.declaredSize ?? entry.content.count, 4)
            putLittle(&directory, name.count, 2)
            putLittle(&directory, 0, 2)
            putLittle(&directory, 0, 2)
            putLittle(&directory, 0, 2)
            putLittle(&directory, 0, 2)
            putLittle(&directory, 0, 4)
            putLittle(&directory, offsets[index], 4)
            directory += name
        }
        var out = body + directory
        putLittle(&out, 0x0605_4B50, 4)
        putLittle(&out, 0, 2)
        putLittle(&out, 0, 2)
        putLittle(&out, entries.count, 2)
        putLittle(&out, entries.count, 2)
        putLittle(&out, directory.count, 4)
        putLittle(&out, directoryOffset, 4)
        putLittle(&out, 0, 2)
        return Data(out)
    }

    private func putLittle(_ out: inout [UInt8], _ value: Int, _ bytes: Int) {
        for index in 0..<bytes {
            out.append(UInt8((value >> (8 * index)) & 0xFF))
        }
    }

    private func manifestEntry() -> TestEntry {
        return TestEntry(name: "manifest.json", content: manifestBytes, declaredSize: nil)
    }

    func testPlainArchiveReadsItsManifest() {
        guard case let .playlist(manifest, cover: cover) = BGMusicFileReader.read(zipData([manifestEntry()])) else {
            return XCTFail("a plain archive must read")
        }
        XCTAssertEqual(manifest.revision, 1)
        XCTAssertNil(cover)
    }

    func testManifestNameIsMatchedExactly() {
        let data = zipData([TestEntry(name: "Manifest.json", content: manifestBytes, declaredSize: nil)])
        XCTAssertEqual(BGMusicFileReader.read(data), .invalid(.archive(.missingManifest)))
    }

    func testSameNameIgnoringCaseIsADuplicate() {
        let data = zipData([manifestEntry(), TestEntry(name: "Manifest.json", content: manifestBytes, declaredSize: nil)])
        XCTAssertEqual(BGMusicFileReader.read(data), .invalid(.archive(.duplicateEntry)))
    }

    func testASecondCoverIsADuplicate() {
        let data = zipData([
            manifestEntry(),
            TestEntry(name: "cover.png", content: pngCover, declaredSize: nil),
            TestEntry(name: "cover.jpg", content: pngCover, declaredSize: nil),
        ])
        XCTAssertEqual(BGMusicFileReader.read(data), .invalid(.archive(.duplicateEntry)))
    }

    func testUnsafeEntryNamesAreRefused() {
        for name in ["../manifest.json", "dir/manifest.json", "a..b.json", ".hidden", "inner.zip"] {
            let data = zipData([TestEntry(name: name, content: manifestBytes, declaredSize: nil)])
            XCTAssertEqual(BGMusicFileReader.read(data), .invalid(.archive(.badEntryName)), name)
        }
    }

    func testNestedArchiveContentIsRefusedInAnyEntry() {
        let inner: [UInt8] = [0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00]
        let data = zipData([manifestEntry(), TestEntry(name: "notes.txt", content: inner, declaredSize: nil)])
        XCTAssertEqual(BGMusicFileReader.read(data), .invalid(.archive(.badEntryName)))
    }

    func testMoreThanEightEntriesAreRefused() {
        let entries = (0..<9).map { TestEntry(name: "note\($0).txt", content: [0x61], declaredSize: nil) }
        XCTAssertEqual(BGMusicArchive.read(zipData(entries)), .failure(.tooManyEntries))
    }

    func testManifestLimitIsCountedNotTakenFromTheHeader() {
        // The header claims 10 bytes; the entry really holds one byte over the manifest limit.
        let big = [UInt8](repeating: 0x20, count: BGMusicArchive.maxManifestBytes + 1)
        let data = zipData([TestEntry(name: "manifest.json", content: big, declaredSize: 10)])
        XCTAssertEqual(BGMusicArchive.read(data), .failure(.manifestTooLarge))
    }

    func testDeclaredSizeMustMatchTheBytesRead() {
        let data = zipData([TestEntry(name: "manifest.json", content: manifestBytes, declaredSize: 5)])
        XCTAssertEqual(BGMusicArchive.read(data), .failure(.corruptArchive))
    }

    func testUnknownEntriesAndUpperCaseCoverNamesAreSkipped() {
        let data = zipData([manifestEntry(), TestEntry(name: "COVER.PNG", content: pngCover, declaredSize: nil)])
        guard case let .success(contents) = BGMusicArchive.read(data) else {
            return XCTFail("unknown safe entries must be skipped")
        }
        XCTAssertNil(contents.cover)
    }

    func testEmptyZipIsNotZip() {
        XCTAssertEqual(BGMusicArchive.read(zipData([])), .failure(.notZip))
    }

    // MARK: Decision and planner (section 10)

    func testDecisionCases() {
        XCTAssertEqual(BGMusicImportDecision.decide(playlistId: playlistId, revision: 3, existing: []), .newPlaylist)
        let existing: [(id: String, revision: Int64)] = [(id: playlistId, revision: 5)]
        XCTAssertEqual(BGMusicImportDecision.decide(playlistId: playlistId, revision: 5, existing: existing), .sameRevision(localRevision: 5))
        XCTAssertEqual(BGMusicImportDecision.decide(playlistId: playlistId, revision: 6, existing: existing), .newerRevision(localRevision: 5))
        XCTAssertEqual(BGMusicImportDecision.decide(playlistId: playlistId, revision: 4, existing: existing), .olderRevision(localRevision: 5))
    }

    func testDecisionIgnoresCaseAndUsesTheHighestRevision() {
        let existing: [(id: String, revision: Int64)] = [(id: playlistId.uppercased(), revision: 2), (id: playlistId, revision: 7)]
        XCTAssertEqual(BGMusicImportDecision.decide(playlistId: playlistId.uppercased(), revision: 7, existing: existing), .sameRevision(localRevision: 7))
    }

    private func ref(
        localId: String,
        favorites: Bool = false,
        sourceId: String? = nil,
        sourceRevision: Int64? = nil,
        revision: Int64,
        revisionAtSource: Int64? = nil
    ) -> BGMusicLocalPlaylistRef {
        return BGMusicLocalPlaylistRef(
            localId: localId,
            isFavorites: favorites,
            sourcePlaylistId: sourceId,
            sourceRevision: sourceRevision,
            revision: revision,
            revisionAtSource: revisionAtSource
        )
    }

    func testFavoritesNeverMatch() {
        let library = [ref(localId: playlistId, favorites: true, revision: 9)]
        XCTAssertEqual(BGMusicImportPlanner.decide(playlistId: playlistId, revision: 1, library: library), .newPlaylist)
        XCTAssertNil(BGMusicImportPlanner.matchingCopy(playlistId: playlistId, library: library))
    }

    func testCopyMatchesTheRevisionOfItsSourceFile() {
        // Edited after import: its own revision moved on, but the file revision it matches is still 3.
        let copy = ref(localId: otherId, sourceId: playlistId, sourceRevision: 3, revision: 6, revisionAtSource: 3)
        XCTAssertEqual(BGMusicImportPlanner.decide(playlistId: playlistId, revision: 3, library: [copy]), .sameRevision(localRevision: 3))
        XCTAssertEqual(BGMusicImportPlanner.matchingCopy(playlistId: playlistId, library: [copy]), copy)
    }

    func testMatchingCopyPicksTheHighestFileRevision() {
        let older = ref(localId: "copy-a", sourceId: playlistId, sourceRevision: 2, revision: 2, revisionAtSource: 2)
        let newer = ref(localId: "copy-b", sourceId: playlistId, sourceRevision: 5, revision: 5, revisionAtSource: 5)
        XCTAssertEqual(BGMusicImportPlanner.matchingCopy(playlistId: playlistId, library: [older, newer]), newer)
    }

    // MARK: Export identity (section 10, "Экспорт копии")

    func testUnchangedCopyExportsAsItsSourceFile() {
        let copy = ref(localId: "copy-1", sourceId: playlistId, sourceRevision: 3, revision: 3, revisionAtSource: 3)
        let identity = BGMusicExportIdentity.resolve(copy, freshId: { "unused" })
        XCTAssertEqual(identity.playlistId, playlistId)
        XCTAssertEqual(identity.revision, 3)
    }

    func testEditedCopyExportsUnderItsOwnRevision() {
        let copy = ref(localId: otherId, sourceId: playlistId, sourceRevision: 3, revision: 4, revisionAtSource: 3)
        let identity = BGMusicExportIdentity.resolve(copy, freshId: { "unused" })
        XCTAssertEqual(identity.playlistId, otherId)
        XCTAssertEqual(identity.revision, 4)
    }

    func testFavoritesAndNonUUIDIdsGetAFreshId() {
        let fresh = "0a0a0a0a-0b0b-4c0c-8d0d-0e0e0e0e0e0e"
        let favorites = ref(localId: playlistId, favorites: true, revision: 2)
        XCTAssertEqual(BGMusicExportIdentity.resolve(favorites, freshId: { fresh }).playlistId, fresh)
        let local = ref(localId: "not-a-uuid", revision: 2)
        XCTAssertEqual(BGMusicExportIdentity.resolve(local, freshId: { fresh }).playlistId, fresh)
    }

    func testDefaultFreshIdIsACanonicalUUID() {
        let favorites = ref(localId: playlistId, favorites: true, revision: 2)
        let generated = BGMusicExportIdentity.resolve(favorites).playlistId
        XCTAssertNotNil(BGMusicManifest.canonicalUUID(generated))
        XCTAssertEqual(generated, generated.lowercased())
    }

    // MARK: File names

    func testFileNameReplacesUnsafeCharacters() {
        XCTAssertEqual(BGMusicFileNaming.fileName(forTitle: "a/b:c*d?e\"f<g>h|i\\j"), "a_b_c_d_e_f_g_h_i_j.bgmusic")
    }

    func testFileNameFallsBackAndTrimsDots() {
        XCTAssertEqual(BGMusicFileNaming.fileName(forTitle: "   ...  "), "playlist.bgmusic")
        XCTAssertEqual(BGMusicFileNaming.fileName(forTitle: "..Утро.."), "Утро.bgmusic")
    }

    func testFileNameIsCappedAtEightyCharacters() {
        let name = BGMusicFileNaming.fileName(forTitle: String(repeating: "a", count: 200))
        XCTAssertEqual(name.count, 80 + ".bgmusic".count)
    }

    // MARK: Writing (section 12) and import round trip

    private func manifest(title: String = "Утро", description: String = "", author: String? = nil) -> BGMusicManifest {
        let track = BGMusicTrack(
            id: trackId,
            title: "Song",
            artist: "Artist",
            album: "",
            durationSec: 215,
            audioHash: nil,
            sources: [.telegramPublic(username: "some_channel", messageId: 42)]
        )
        return BGMusicManifest(
            playlistId: playlistId,
            revision: 2,
            title: title,
            description: description,
            updatedAt: 1_700_000_000_000,
            authorName: author,
            tracks: [track]
        )
    }

    private func writeError<T>(_ result: Result<T, BGMusicWriteError>) -> BGMusicWriteError? {
        if case let .failure(error) = result {
            return error
        }
        return nil
    }

    func testPackageRoundTripKeepsTheManifestAndTheCover() {
        let cover = BGMusicCover(kind: .png, data: Data(pngCover))
        guard case let .success(data) = BGMusicPackage.make(manifest(description: "a\n\n\n\nb", author: "Ilya"), cover: cover) else {
            return XCTFail("a valid manifest must be written")
        }
        guard case let .playlist(decoded, cover: readCover) = BGMusicFileReader.read(data) else {
            return XCTFail("the written file must read back")
        }
        XCTAssertEqual(decoded.description, "a\n\nb")
        XCTAssertEqual(decoded.authorName, "Ilya")
        XCTAssertEqual(decoded.tracks.first?.sources, [.telegramPublic(username: "some_channel", messageId: 42)])
        XCTAssertEqual(readCover, cover)
    }

    func testEmptyTitleIsRefusedBeforeAnyBytesAreMade() {
        XCTAssertEqual(writeError(BGMusicPackage.make(manifest(title: "  "), cover: nil)), .manifest(.badField("title")))
    }

    func testCoverWithTheWrongMagicIsRefused() {
        let wrong = BGMusicCover(kind: .jpg, data: Data(pngCover))
        XCTAssertEqual(writeError(BGMusicPackage.make(manifest(), cover: wrong)), .archive(.badCover))
    }

    func testFileIsWrittenUnderItsTitleAndReadsBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgmusic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard case let .success(url) = BGMusicPackage.writeFile(manifest(), cover: nil, into: directory) else {
            return XCTFail("the file must be written")
        }
        XCTAssertEqual(url.lastPathComponent, "Утро.bgmusic")
        let bytes = try Data(contentsOf: url)
        guard case .playlist = BGMusicFileReader.read(bytes) else {
            return XCTFail("the file on disk must read back")
        }
    }

    func testWritingIntoAMissingFolderReportsIO() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)", isDirectory: true)
        XCTAssertEqual(writeError(BGMusicPackage.writeFile(manifest(), cover: nil, into: missing)), .io)
    }

    func testExportSummaryCountsWhatTheFileCarries() {
        let summary = BGMusicExportSummary(manifest: manifest(author: "Ilya"), cover: BGMusicCover(kind: .png, data: Data(pngCover)))
        XCTAssertEqual(summary.trackCount, 1)
        XCTAssertEqual(summary.publicSourceCount, 1)
        XCTAssertTrue(summary.hasAuthor)
        XCTAssertTrue(summary.hasCover)
    }
}
