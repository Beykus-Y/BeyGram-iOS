import Foundation

/// File names for exports (Android: `BgMusicLibraryMapping.fileNameFor`).
public enum BGMusicFileNaming {
    public static let fileExtension = "bgmusic"

    /// A file name from the playlist title. Characters that are unsafe in file names become `_`. The title is capped at
    /// 80 characters, trimmed of spaces and dots, and an empty result becomes `playlist`. The extension is `.bgmusic`.
    public static func fileName(forTitle title: String) -> String {
        let cleaned = BGMusicText.singleLine(title, maxLength: 80)
        let unsafeCharacters: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        var safe = String(cleaned.map { unsafeCharacters.contains($0) ? "_" : $0 })
        safe = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        safe = safe.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        safe = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safe.isEmpty ? "playlist" : safe
        return base + "." + fileExtension
    }
}

/// The playlist_id and revision that a file carries for a local playlist (section 10, "Экспорт копии").
public enum BGMusicExportIdentity {
    /// A copy without local changes exports as its source file: the same playlist_id and the same revision, so the
    /// receiver sees the same collection at the same revision. Any other playlist, and a copy with changes, exports under
    /// its own id and its own revision. Favorites, and a local id that is not a UUID, get a fresh id.
    public static func resolve(
        _ playlist: BGMusicLocalPlaylistRef,
        freshId: () -> String = { UUID().uuidString.lowercased() }
    ) -> (playlistId: String, revision: Int64) {
        if let sourceId = playlist.sourcePlaylistId.flatMap({ BGMusicManifest.canonicalUUID($0) }),
           let sourceRevision = playlist.sourceRevision,
           playlist.revisionAtSource == playlist.revision {
            return (playlistId: sourceId, revision: max(sourceRevision, 0))
        }
        let ownId: String
        if playlist.isFavorites {
            ownId = freshId()
        } else {
            ownId = BGMusicManifest.canonicalUUID(playlist.localId) ?? freshId()
        }
        return (playlistId: ownId, revision: max(playlist.revision, 0))
    }
}

/// Why a file could not be written.
public enum BGMusicWriteError: Error, Equatable {
    case manifest(BGMusicFormatError)
    case archive(BGMusicArchiveError)
    /// The file could not be written to the target folder.
    case io
}

/// Builds .bgmusic files (section 12, the writer). Text is cleaned and checked first, and the archive is built in memory,
/// so a refused input leaves no file behind.
public enum BGMusicPackage {
    /// The archive bytes for a manifest and an optional cover. The file carries exactly what the manifest holds, so the
    /// caller decides on the author and on the sources before it calls this (section 9).
    public static func make(_ manifest: BGMusicManifest, cover: BGMusicCover?) -> Result<Data, BGMusicWriteError> {
        let json: Data
        do {
            json = try manifest.jsonData()
        } catch let error as BGMusicFormatError {
            return .failure(.manifest(error))
        } catch {
            return .failure(.manifest(.badField("manifest")))
        }
        switch BGMusicArchive.write(manifest: json, cover: cover) {
        case let .success(data):
            return .success(data)
        case let .failure(error):
            return .failure(.archive(error))
        }
    }

    /// Writes the file into `directory`, named from the title, atomically. Returns the file's URL.
    public static func writeFile(_ manifest: BGMusicManifest, cover: BGMusicCover?, into directory: URL) -> Result<URL, BGMusicWriteError> {
        let data: Data
        switch make(manifest, cover: cover) {
        case let .success(bytes):
            data = bytes
        case let .failure(error):
            return .failure(error)
        }
        let url = directory.appendingPathComponent(BGMusicFileNaming.fileName(forTitle: manifest.title))
        do {
            try data.write(to: url, options: .atomic)
            return .success(url)
        } catch {
            return .failure(.io)
        }
    }
}

/// What a file will contain, for the export sheet. The owner sees this before the file is shared (section 9).
public struct BGMusicExportSummary: Equatable {
    public let trackCount: Int
    /// The public post hints across all tracks.
    public let publicSourceCount: Int
    /// True when the file carries the owner's name.
    public let hasAuthor: Bool
    public let hasCover: Bool

    public init(manifest: BGMusicManifest, cover: BGMusicCover?) {
        trackCount = manifest.tracks.count
        publicSourceCount = manifest.tracks.reduce(0) { $0 + $1.sources.count }
        hasAuthor = manifest.authorName != nil
        hasCover = cover != nil
    }
}
