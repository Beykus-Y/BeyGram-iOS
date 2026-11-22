import Foundation

/// Why an opened .bgmusic file was refused: the container (`BGMusicArchive`) or the manifest (`BGMusicManifest`).
public enum BGMusicFileError: Error, Equatable {
    case archive(BGMusicArchiveError)
    case manifest(BGMusicFormatError)
}

/// The result of reading a whole .bgmusic file, before any library decision is made.
public enum BGMusicFileReadResult: Equatable {
    case playlist(BGMusicManifest, cover: BGMusicCover?)
    /// The file needs a newer reader. Nothing is imported, and the file and the local data are left alone.
    case unsupported(formatVersion: Int64, minReaderVersion: Int64)
    case invalid(BGMusicFileError)
}

/// Reads a whole .bgmusic file: the ZIP container first, then the manifest (sections 2 to 4 and section 8 of the spec).
public enum BGMusicFileReader {
    /// `data` may come from any source, such as a document picker or a share extension. The limits are enforced while
    /// the bytes are read, so the caller needs no size check of its own.
    public static func read(_ data: Data) -> BGMusicFileReadResult {
        switch BGMusicArchive.read(data) {
        case let .failure(error):
            return .invalid(.archive(error))
        case let .success(contents):
            switch BGMusicManifest.decode(contents.manifest) {
            case let .success(manifest):
                return .playlist(manifest, cover: contents.cover)
            case let .unsupported(formatVersion: formatVersion, minReaderVersion: minReaderVersion):
                return .unsupported(formatVersion: formatVersion, minReaderVersion: minReaderVersion)
            case let .invalid(error):
                return .invalid(.manifest(error))
            }
        }
    }
}

/// What to offer when a .bgmusic file is opened (section 10). Pure: nothing is merged, replaced or copied here.
public enum BGMusicImportDecision: Equatable {
    /// No local playlist has this playlist_id. Import it as a new playlist.
    case newPlaylist
    /// The local copy already has this revision. There is nothing new to import.
    case sameRevision(localRevision: Int64)
    /// The file is a newer revision. Offer to update the local copy, or to keep the file as a separate copy.
    case newerRevision(localRevision: Int64)
    /// The file is older than the local copy. Warn, and offer a separate copy or cancel.
    case olderRevision(localRevision: Int64)

    /// Compares an incoming (playlist_id, revision) pair with local pairs. IDs compare ignoring case. When an ID appears
    /// more than once, its highest revision is the one used.
    public static func decide(playlistId: String, revision: Int64, existing: [(id: String, revision: Int64)]) -> BGMusicImportDecision {
        let key = normalizedId(playlistId)
        var localRevision: Int64?
        for item in existing where normalizedId(item.id) == key {
            if let current = localRevision, current >= item.revision {
                continue
            }
            localRevision = item.revision
        }
        guard let local = localRevision else {
            return .newPlaylist
        }
        if revision == local {
            return .sameRevision(localRevision: local)
        }
        if revision > local {
            return .newerRevision(localRevision: local)
        }
        return .olderRevision(localRevision: local)
    }

    static func normalizedId(_ value: String) -> String {
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// A local playlist as the import planner sees it. The library layer fills these in from its own data. The planner only
/// reads them, so matching a file never changes the library.
public struct BGMusicLocalPlaylistRef: Equatable {
    /// The app's own id for the playlist.
    public var localId: String
    /// Favorites has one fixed id on every account, so it never takes part in matching.
    public var isFavorites: Bool
    /// For an imported copy, the playlist_id of the file it was saved from. Nil for any other playlist.
    public var sourcePlaylistId: String?
    /// For an imported copy, the revision of that file. Nil for any other playlist.
    public var sourceRevision: Int64?
    /// The playlist's own revision. It grows with every local change.
    public var revision: Int64
    /// For a copy, the value of `revision` when the copy last matched its file. Nil for any other playlist.
    public var revisionAtSource: Int64?

    public init(localId: String, isFavorites: Bool, sourcePlaylistId: String?, sourceRevision: Int64?, revision: Int64, revisionAtSource: Int64?) {
        self.localId = localId
        self.isFavorites = isFavorites
        self.sourcePlaylistId = sourcePlaylistId
        self.sourceRevision = sourceRevision
        self.revision = revision
        self.revisionAtSource = revisionAtSource
    }

    /// The id that a file is matched by: the source file's id for a copy, the local id otherwise.
    var matchKey: String {
        return sourcePlaylistId ?? localId
    }

    /// The revision that a file is compared with (section 10): the source file's revision for a copy, the playlist's own
    /// revision otherwise. Mirrors `fileRevision` on Android.
    var fileRevision: Int64 {
        if sourcePlaylistId != nil {
            return sourceRevision ?? revision
        }
        return revision
    }
}

/// Matches an incoming file with the local playlists (section 10). Pure, like the decision it builds on.
public enum BGMusicImportPlanner {
    /// The decision for a file with this playlist_id and revision. Favorites never takes part.
    public static func decide(playlistId: String, revision: Int64, library: [BGMusicLocalPlaylistRef]) -> BGMusicImportDecision {
        let existing: [(id: String, revision: Int64)] = matchable(library).map { playlist in
            (id: playlist.matchKey, revision: playlist.fileRevision)
        }
        return BGMusicImportDecision.decide(playlistId: playlistId, revision: revision, existing: existing)
    }

    /// The local copy that a file would update: the match with the highest file revision, or nil when the file is new to
    /// this library. When two matches have the same revision, the first one in the library wins.
    public static func matchingCopy(playlistId: String, library: [BGMusicLocalPlaylistRef]) -> BGMusicLocalPlaylistRef? {
        let key = BGMusicImportDecision.normalizedId(playlistId)
        var best: BGMusicLocalPlaylistRef?
        for playlist in matchable(library) where BGMusicImportDecision.normalizedId(playlist.matchKey) == key {
            if let current = best, current.fileRevision >= playlist.fileRevision {
                continue
            }
            best = playlist
        }
        return best
    }

    private static func matchable(_ library: [BGMusicLocalPlaylistRef]) -> [BGMusicLocalPlaylistRef] {
        return library.filter { !$0.isFavorites }
    }
}
