import Foundation
import BeyGramMusicFormat

/// Keeps the library in one folder: `library.json` for the records, and `covers/<localId>/<file>` for covers. Writes are
/// atomic. A file whose schema this build does not know is refused and never overwritten.
public final class BGMusicLibraryFileStore: BGMusicLibraryStore {
    /// The version of `library.json`. Bump it with a migration when a record changes shape.
    public static let schemaVersion = 1

    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL) throws {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw BGMusicLibraryError.io
        }
    }

    private struct IndexFile: Codable {
        var schema: Int
        var playlists: [BGMusicLibraryPlaylist]
    }

    private var indexURL: URL {
        return directory.appendingPathComponent("library.json")
    }

    private func folderURL(localId: String) -> URL {
        return directory
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent(localId, isDirectory: true)
    }

    public func allPlaylists() throws -> [BGMusicLibraryPlaylist] {
        lock.lock()
        defer { lock.unlock() }
        return try readIndex()
    }

    public func playlist(localId: String) throws -> BGMusicLibraryPlaylist? {
        lock.lock()
        defer { lock.unlock() }
        return try readIndex().first(where: { $0.localId == localId })
    }

    public func cover(localId: String) throws -> BGMusicCover? {
        lock.lock()
        defer { lock.unlock() }
        let playlists = try readIndex()
        guard let record = playlists.first(where: { $0.localId == localId }),
              let fileName = record.coverFileName,
              let kind = BGMusicCoverKind(rawValue: fileName) else {
            return nil
        }
        let url = folderURL(localId: localId).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else {
            throw BGMusicLibraryError.io
        }
        return BGMusicCover(kind: kind, data: data)
    }

    public func save(_ playlist: BGMusicLibraryPlaylist, cover: BGMusicCover?) throws {
        try checkLocalId(playlist.localId)
        lock.lock()
        defer { lock.unlock() }
        var playlists = try readIndex()
        var record = playlist
        // The cover is written before the index, and the other cover files are removed after it. A failed index write then
        // leaves the old record with a cover file it can still read.
        record.coverFileName = try writeCover(cover, localId: playlist.localId)
        if let index = playlists.firstIndex(where: { $0.localId == playlist.localId }) {
            playlists[index] = record
        } else {
            playlists.append(record)
        }
        try writeIndex(playlists)
        removeCoverFiles(localId: playlist.localId, keeping: record.coverFileName)
    }

    public func delete(localId: String) throws {
        try checkLocalId(localId)
        lock.lock()
        defer { lock.unlock() }
        var playlists = try readIndex()
        guard let index = playlists.firstIndex(where: { $0.localId == localId }) else {
            throw BGMusicLibraryError.notFound
        }
        playlists.remove(at: index)
        try writeIndex(playlists)
        try? FileManager.default.removeItem(at: folderURL(localId: localId))
    }

    private func readIndex() throws -> [BGMusicLibraryPlaylist] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: indexURL)
        } catch {
            throw BGMusicLibraryError.io
        }
        let index: IndexFile
        do {
            index = try JSONDecoder().decode(IndexFile.self, from: data)
        } catch {
            throw BGMusicLibraryError.corruptIndex
        }
        guard index.schema == BGMusicLibraryFileStore.schemaVersion else {
            throw BGMusicLibraryError.unsupportedSchema(index.schema)
        }
        return index.playlists
    }

    private func writeIndex(_ playlists: [BGMusicLibraryPlaylist]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let index = IndexFile(schema: BGMusicLibraryFileStore.schemaVersion, playlists: playlists)
        do {
            let data = try encoder.encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            throw BGMusicLibraryError.io
        }
    }

    /// Writes the cover file of a playlist and returns its name, or nil when there is no cover. Other cover files of the
    /// playlist stay until `removeCoverFiles` runs.
    private func writeCover(_ cover: BGMusicCover?, localId: String) throws -> String? {
        guard let cover = cover else {
            return nil
        }
        let folder = folderURL(localId: localId)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try cover.data.write(to: folder.appendingPathComponent(cover.kind.rawValue), options: .atomic)
        } catch {
            throw BGMusicLibraryError.io
        }
        return cover.kind.rawValue
    }

    /// Removes the cover files that the index does not name: the whole folder when the playlist has no cover, and every
    /// other file otherwise. It runs after the index is saved.
    private func removeCoverFiles(localId: String, keeping fileName: String?) {
        let folder = folderURL(localId: localId)
        guard let fileName = fileName else {
            try? FileManager.default.removeItem(at: folder)
            return
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where file != fileName {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    private func checkLocalId(_ localId: String) throws {
        let allowed = localId.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
        guard !localId.isEmpty, localId.count <= 64, allowed else {
            throw BGMusicLibraryError.invalidLocalId
        }
    }
}
