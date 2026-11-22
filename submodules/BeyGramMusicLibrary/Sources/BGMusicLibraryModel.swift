import Foundation
import BeyGramMusicFormat

/// Why a library operation, a file operation or an import was refused.
public enum BGMusicLibraryError: Error, Equatable {
    case notFound
    /// Local ids are ASCII letters, digits, `-` and `_`, at most 64 characters, because each one is a folder name.
    case invalidLocalId
    /// Favorites cannot be deleted.
    case favoritesCannotBeDeleted
    /// The action does not fit the import decision, for example an update of a playlist that is not a copy.
    case notAllowed
    case unsupportedSchema(Int)
    case corruptIndex
    case io
    case fileNotReadable
    case fileTooLarge
    case file(BGMusicFileError)
    /// The file needs a newer reader (section 8). Nothing is changed.
    case unsupportedFormat(formatVersion: Int64, minReaderVersion: Int64)
    case write(BGMusicWriteError)
}

/// Whether the app can play a track. The file does not say this. The app sets it after it looks for the track.
public enum BGMusicTrackAvailability: String, Codable, Equatable {
    case unknown
    case available
    case unavailable
}

/// A public post where a track can be heard (section 5). The stored form has no `@`.
public struct BGMusicLibrarySourceHint: Codable, Equatable {
    public var username: String
    public var messageId: Int64

    public init(username: String, messageId: Int64) {
        self.username = username
        self.messageId = messageId
    }
}

/// A track in a local playlist. Metadata comes from the file or from the app. `availability` is local state, not
/// content: changing it never makes a copy look edited (see `BGMusicLibrary.saveEdits`).
public struct BGMusicLibraryTrack: Codable, Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationSec: Int64
    public var audioHash: String?
    public var sources: [BGMusicLibrarySourceHint]
    public var availability: BGMusicTrackAvailability

    /// A track as a file carries it. It starts with unknown availability.
    public init(_ track: BGMusicTrack) {
        self.id = track.id
        self.title = track.title
        self.artist = track.artist
        self.album = track.album
        self.durationSec = track.durationSec
        self.audioHash = track.audioHash
        self.sources = track.sources.map { source -> BGMusicLibrarySourceHint in
            switch source {
            case let .telegramPublic(username, messageId):
                return BGMusicLibrarySourceHint(username: username, messageId: messageId)
            }
        }
        self.availability = .unknown
    }

    /// The track as a .bgmusic file carries it. Public post hints are kept only when `includeSources` is true (section 9).
    public func manifestTrack(includeSources: Bool) -> BGMusicTrack {
        let hints: [BGMusicSource] = includeSources
            ? sources.map { BGMusicSource.telegramPublic(username: $0.username, messageId: $0.messageId) }
            : []
        return BGMusicTrack(
            id: id,
            title: title,
            artist: artist,
            album: album,
            durationSec: durationSec,
            audioHash: audioHash,
            sources: hints
        )
    }
}

/// For a copy made by import: the file it was made from, and the local revision at which the copy last matched that file.
public struct BGMusicLibrarySource: Codable, Equatable {
    public var playlistId: String
    public var revision: Int64
    public var revisionAtSource: Int64

    public init(playlistId: String, revision: Int64, revisionAtSource: Int64) {
        self.playlistId = playlistId
        self.revision = revision
        self.revisionAtSource = revisionAtSource
    }
}

/// A playlist in the local library. `isFavorites` marks the Favorites list, which never takes part in matching (section 10).
/// A copy made by import has `source` set. A playlist made in the app has none.
public struct BGMusicLibraryPlaylist: Codable, Equatable {
    public var localId: String
    public var isFavorites: Bool
    public var title: String
    public var description: String
    public var authorName: String?
    public var tracks: [BGMusicLibraryTrack]
    /// Grows with every change of content. Availability changes do not count.
    public var revision: Int64
    public var updatedAt: Int64
    public var source: BGMusicLibrarySource?
    /// File name of the cover inside the playlist's folder (`cover.webp`, `cover.jpg` or `cover.png`), or nil.
    public var coverFileName: String?

    public init(
        localId: String,
        isFavorites: Bool,
        title: String,
        description: String,
        authorName: String?,
        tracks: [BGMusicLibraryTrack],
        revision: Int64,
        updatedAt: Int64,
        source: BGMusicLibrarySource?,
        coverFileName: String?
    ) {
        self.localId = localId
        self.isFavorites = isFavorites
        self.title = title
        self.description = description
        self.authorName = authorName
        self.tracks = tracks
        self.revision = revision
        self.updatedAt = updatedAt
        self.source = source
        self.coverFileName = coverFileName
    }

    /// The record as the import planner and the export identity read it (section 10).
    public var planningRef: BGMusicLocalPlaylistRef {
        return BGMusicLocalPlaylistRef(
            localId: localId,
            isFavorites: isFavorites,
            sourcePlaylistId: source?.playlistId,
            sourceRevision: source?.revision,
            revision: revision,
            revisionAtSource: source?.revisionAtSource
        )
    }
}

/// Where playlist records live. The app uses `BGMusicLibraryFileStore`. Tests use an in-memory store.
public protocol BGMusicLibraryStore: AnyObject {
    func allPlaylists() throws -> [BGMusicLibraryPlaylist]
    func playlist(localId: String) throws -> BGMusicLibraryPlaylist?
    func cover(localId: String) throws -> BGMusicCover?
    /// Replaces the whole record. A nil `cover` means the playlist has no cover.
    func save(_ playlist: BGMusicLibraryPlaylist, cover: BGMusicCover?) throws
    func delete(localId: String) throws
}

/// What to do with a playlist's cover when its edits are saved.
public enum BGMusicCoverChange: Equatable {
    case keep
    case set(BGMusicCover)
    case remove
}
