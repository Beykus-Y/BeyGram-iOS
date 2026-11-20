import XCTest
import BeyGramMusicFormat
@testable import BeyGramMusicLibrary

/// Tests for the local library, the import and export layers, the file store and the incoming-file loader. Foundation
/// only. Not compiled or run yet: no macOS toolchain was available when they were written.
final class BGMusicLibraryTests: XCTestCase {
    private let fileId = "6f1d2c3a-4b5e-4f60-8a7b-9c0d1e2f3a4b"
    private let trackId = "0d6f3c1e-7a2b-4c5d-9e8f-1a2b3c4d5e6f"
    private let pngCover: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]

    /// An in-memory store, so the library tests do not touch the file system.
    private final class InMemoryStore: BGMusicLibraryStore {
        private(set) var records: [BGMusicLibraryPlaylist] = []
        private var covers: [String: BGMusicCover] = [:]

        func allPlaylists() throws -> [BGMusicLibraryPlaylist] {
            return records
        }

        func playlist(localId: String) throws -> BGMusicLibraryPlaylist? {
            return records.first(where: { $0.localId == localId })
        }

        func cover(localId: String) throws -> BGMusicCover? {
            return covers[localId]
        }

        func save(_ playlist: BGMusicLibraryPlaylist, cover: BGMusicCover?) throws {
            var record = playlist
            record.coverFileName = cover?.kind.rawValue
            if let index = records.firstIndex(where: { $0.localId == playlist.localId }) {
                records[index] = record
            } else {
                records.append(record)
            }
            covers[playlist.localId] = cover
        }

        func delete(localId: String) throws {
            records.removeAll(where: { $0.localId == localId })
            covers[localId] = nil
        }
    }

    /// A library whose new ids count up, so each new playlist gets a distinct canonical UUID.
    private func makeLibrary(store: BGMusicLibraryStore) -> BGMusicLibrary {
        var counter = 0
        return BGMusicLibrary(store: store, now: { 1_000 }, makeId: {
            counter += 1
            return "00000000-0000-4000-8000-00000000000\(counter)"
        })
    }

    private func sampleManifest(revision: Int64 = 2, title: String = "Утро", author: String? = nil) -> BGMusicManifest {
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
            playlistId: fileId,
            revision: revision,
            title: title,
            description: "",
            updatedAt: 1_700_000_000_000,
            authorName: author,
            tracks: [track]
        )
    }

    private func fileData(_ manifest: BGMusicManifest) throws -> Data {
        return try BGMusicPackage.make(manifest, cover: nil).get()
    }

    /// Previews a file and adds it as a new playlist, returning its local id.
    private func addFile(_ library: BGMusicLibrary, _ manifest: BGMusicManifest) throws -> String {
        let preview = try library.previewImport(data: try fileData(manifest))
        guard case let .added(localId) = try library.applyImport(preview, action: .addAsNewPlaylist) else {
            XCTFail("a new file must be added")
            return ""
        }
        return localId
    }

    func testCreatedPlaylistStartsAtRevisionZeroAndIsNotACopy() throws {
        let library = makeLibrary(store: InMemoryStore())
        let playlist = try library.createPlaylist(title: "Мой плейлист", description: "")
        XCTAssertEqual(playlist.revision, 0)
        XCTAssertNil(playlist.source)
        XCTAssertFalse(playlist.isFavorites)
        XCTAssertEqual(try library.playlists().count, 1)
    }

    func testRevisionGrowsOnlyWhenContentChanges() throws {
        let library = makeLibrary(store: InMemoryStore())
        var playlist = try library.createPlaylist(title: "A", description: "")
        let unchanged = try library.saveEdits(playlist, cover: .keep)
        XCTAssertEqual(unchanged.revision, 0)
        playlist.title = "B"
        let changed = try library.saveEdits(playlist, cover: .keep)
        XCTAssertEqual(changed.revision, 1)
    }

    func testAvailabilityIsNotContent() throws {
        let library = makeLibrary(store: InMemoryStore())
        let localId = try addFile(library, sampleManifest(revision: 2))
        var copy = try XCTUnwrap(library.playlist(localId: localId))
        copy.tracks[0].availability = .unavailable
        let saved = try library.saveEdits(copy, cover: .keep)
        XCTAssertEqual(saved.revision, 0)
        XCTAssertEqual(saved.tracks.first?.availability, .unavailable)
    }

    func testImportedFileExportsUnderTheFileIdentityWhileUnchanged() throws {
        let library = makeLibrary(store: InMemoryStore())
        let localId = try addFile(library, sampleManifest(revision: 2))
        let copy = try XCTUnwrap(library.playlist(localId: localId))
        XCTAssertEqual(copy.source?.playlistId, fileId)
        XCTAssertEqual(copy.source?.revision, 2)
        let options = BGMusicExportOptions(includeAuthor: false, includeSources: true, includeCover: false)
        let exported = library.exportManifest(for: copy, options: options)
        XCTAssertEqual(exported.playlistId, fileId)
        XCTAssertEqual(exported.revision, 2)
    }

    func testNewerFileUpdatesTheCopyAndOlderFileOnlyOffersACopy() throws {
        let library = makeLibrary(store: InMemoryStore())
        let localId = try addFile(library, sampleManifest(revision: 2))

        let newer = try library.previewImport(data: try fileData(sampleManifest(revision: 3, title: "Новее")))
        XCTAssertEqual(newer.decision, .newerRevision(localRevision: 2))
        XCTAssertEqual(newer.updateTargetLocalId, localId)
        XCTAssertEqual(try library.applyImport(newer, action: .updateCopy(localId: localId)), .updated(localId: localId))
        let updated = try XCTUnwrap(library.playlist(localId: localId))
        XCTAssertEqual(updated.title, "Новее")
        XCTAssertEqual(updated.source?.revision, 3)
        XCTAssertEqual(updated.source?.revisionAtSource, updated.revision)

        let older = try library.previewImport(data: try fileData(sampleManifest(revision: 1)))
        XCTAssertEqual(older.decision, .olderRevision(localRevision: 3))
        XCTAssertNil(older.updateTargetLocalId)
        XCTAssertThrowsError(try library.applyImport(older, action: .updateCopy(localId: localId))) { error in
            XCTAssertEqual(error as? BGMusicLibraryError, .notAllowed)
        }
    }

    func testSameRevisionOffersNothingToUpdateAndCancelChangesNothing() throws {
        let library = makeLibrary(store: InMemoryStore())
        _ = try addFile(library, sampleManifest(revision: 2))
        let again = try library.previewImport(data: try fileData(sampleManifest(revision: 2)))
        XCTAssertEqual(again.decision, .sameRevision(localRevision: 2))
        XCTAssertNil(again.updateTargetLocalId)
        XCTAssertEqual(try library.applyImport(again, action: .cancel), .cancelled)
        XCTAssertEqual(try library.playlists().count, 1)
    }

    func testFavoritesNeverTakePartInMatchingAndCannotBeDeleted() throws {
        let store = InMemoryStore()
        let library = makeLibrary(store: store)
        let favorites = BGMusicLibraryPlaylist(
            localId: fileId,
            isFavorites: true,
            title: "Избранное",
            description: "",
            authorName: nil,
            tracks: [],
            revision: 9,
            updatedAt: 1,
            source: nil,
            coverFileName: nil
        )
        try store.save(favorites, cover: nil)
        let preview = try library.previewImport(data: try fileData(sampleManifest(revision: 1)))
        XCTAssertEqual(preview.decision, .newPlaylist)
        XCTAssertNil(preview.updateTargetLocalId)
        XCTAssertThrowsError(try library.delete(localId: fileId)) { error in
            XCTAssertEqual(error as? BGMusicLibraryError, .favoritesCannotBeDeleted)
        }
    }

    func testEditedCopyExportsUnderItsOwnIdentity() throws {
        let library = makeLibrary(store: InMemoryStore())
        let localId = try addFile(library, sampleManifest(revision: 2))
        var copy = try XCTUnwrap(library.playlist(localId: localId))
        copy.title = "Моя правка"
        let edited = try library.saveEdits(copy, cover: .keep)
        XCTAssertEqual(edited.revision, 1)
        let options = BGMusicExportOptions(includeAuthor: false, includeSources: false, includeCover: false)
        let exported = library.exportManifest(for: edited, options: options)
        XCTAssertEqual(exported.playlistId, localId)
        XCTAssertEqual(exported.revision, 1)
        XCTAssertNil(exported.tracks.first?.sources.first)
    }

    func testRefusedFileChangesNothing() throws {
        let library = makeLibrary(store: InMemoryStore())
        XCTAssertThrowsError(try library.previewImport(data: Data("not a zip".utf8))) { error in
            XCTAssertEqual(error as? BGMusicLibraryError, .file(.archive(.notZip)))
        }
        XCTAssertEqual(try library.playlists().count, 0)
    }

    func testExportedFileReadsBackWithTheChosenFields() throws {
        let library = makeLibrary(store: InMemoryStore())
        let cover = BGMusicCover(kind: .png, data: Data(pngCover))
        let created = try library.createPlaylist(title: "Утро", description: "Для дороги")
        let withCover = try library.saveEdits(created, cover: .set(cover))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgmusic-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let options = BGMusicExportOptions(includeAuthor: true, includeSources: false, includeCover: true)
        let url = try library.exportFile(for: withCover, options: options, into: directory)
        XCTAssertEqual(url.lastPathComponent, "Утро.bgmusic")
        let bytes = try Data(contentsOf: url)
        guard case let .playlist(manifest, cover: readCover) = BGMusicFileReader.read(bytes) else {
            return XCTFail("the exported file must read back")
        }
        XCTAssertEqual(manifest.title, "Утро")
        XCTAssertEqual(manifest.description, "Для дороги")
        XCTAssertEqual(readCover, cover)
    }

    func testExportWithoutAuthorOrSourcesCarriesNeither() throws {
        let library = makeLibrary(store: InMemoryStore())
        let localId = try addFile(library, sampleManifest(revision: 2, author: "Ilya"))
        let copy = try XCTUnwrap(library.playlist(localId: localId))
        XCTAssertEqual(copy.authorName, "Ilya")
        let options = BGMusicExportOptions(includeAuthor: false, includeSources: false, includeCover: false)
        let exported = library.exportManifest(for: copy, options: options)
        XCTAssertNil(exported.authorName)
        XCTAssertEqual(exported.tracks.first?.sources.count, 0)
    }

    func testFileStoreKeepsRecordsAndCoversAcrossInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bglib-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cover = BGMusicCover(kind: .png, data: Data(pngCover))
        let first = try BGMusicLibraryFileStore(directory: directory)
        let library = makeLibrary(store: first)
        let created = try library.createPlaylist(title: "Сохранённый", description: "")
        _ = try library.saveEdits(created, cover: .set(cover))

        let second = try BGMusicLibraryFileStore(directory: directory)
        XCTAssertEqual(try second.allPlaylists().map { $0.title }, ["Сохранённый"])
        XCTAssertEqual(try second.cover(localId: created.localId), cover)
    }

    func testIncomingFileOverTheLimitIsRefusedBeforeItIsParsed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("big-\(UUID().uuidString).bgmusic")
        try Data(count: BGMusicArchive.maxFileBytes + 1).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try BGMusicIncomingFile.load(from: url)) { error in
            XCTAssertEqual(error as? BGMusicLibraryError, .fileTooLarge)
        }
    }

    func testFileTypesMatchTheFormat() {
        XCTAssertEqual(BGMusicFileTypes.fileExtension, "bgmusic")
        XCTAssertEqual(BGMusicFileTypes.mimeType, "application/vnd.beygram.music+zip")
    }
}
