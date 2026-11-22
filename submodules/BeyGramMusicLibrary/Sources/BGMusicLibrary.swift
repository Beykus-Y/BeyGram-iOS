import Foundation
import BeyGramMusicFormat

/// The local playlist library: creation, edits and deletion. Edits go through `saveEdits`, which keeps the revision honest.
/// A change of content grows the revision, so an edited copy stops exporting under its source id (section 10).
public final class BGMusicLibrary {
    let store: BGMusicLibraryStore
    let now: () -> Int64
    let makeId: () -> String

    /// `now` is milliseconds since 1970. `makeId` must return a lowercase UUID (section 3, `playlist_id`).
    public init(
        store: BGMusicLibraryStore,
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        makeId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.now = now
        self.makeId = makeId
    }

    public func playlists() throws -> [BGMusicLibraryPlaylist] {
        return try store.allPlaylists()
    }

    public func playlist(localId: String) throws -> BGMusicLibraryPlaylist? {
        return try store.playlist(localId: localId)
    }

    public func cover(localId: String) throws -> BGMusicCover? {
        return try store.cover(localId: localId)
    }

    /// A playlist made in the app. It starts at revision 0 and is not a copy of any file.
    public func createPlaylist(title: String, description: String) throws -> BGMusicLibraryPlaylist {
        let playlist = BGMusicLibraryPlaylist(
            localId: makeId(),
            isFavorites: false,
            title: title,
            description: description,
            authorName: nil,
            tracks: [],
            revision: 0,
            updatedAt: now(),
            source: nil,
            coverFileName: nil
        )
        try store.save(playlist, cover: nil)
        return playlist
    }

    /// Saves edits made in the app and returns the record as stored. The local id, the favorites flag and the source come
    /// from the stored record, never from the edit. The revision grows only when the content changes (title, description,
    /// author or tracks, compared without availability).
    public func saveEdits(_ edited: BGMusicLibraryPlaylist, cover: BGMusicCoverChange) throws -> BGMusicLibraryPlaylist {
        guard let stored = try store.playlist(localId: edited.localId) else {
            throw BGMusicLibraryError.notFound
        }
        var next = edited
        next.isFavorites = stored.isFavorites
        next.source = stored.source
        next.revision = stored.revision
        next.updatedAt = stored.updatedAt
        if !BGMusicLibrary.sameContent(next, stored) {
            next.revision = stored.revision + 1
            next.updatedAt = now()
        }
        let resolvedCover: BGMusicCover?
        switch cover {
        case .keep:
            resolvedCover = try store.cover(localId: edited.localId)
        case let .set(newCover):
            resolvedCover = newCover
        case .remove:
            resolvedCover = nil
        }
        try store.save(next, cover: resolvedCover)
        return try store.playlist(localId: edited.localId) ?? next
    }

    /// Deletes a playlist made in the app, or a copy. Favorites cannot be deleted.
    public func delete(localId: String) throws {
        guard let stored = try store.playlist(localId: localId) else {
            throw BGMusicLibraryError.notFound
        }
        guard !stored.isFavorites else {
            throw BGMusicLibraryError.favoritesCannotBeDeleted
        }
        try store.delete(localId: localId)
    }

    /// Whether two records have the same content. Availability and the revision bookkeeping are not content.
    static func sameContent(_ lhs: BGMusicLibraryPlaylist, _ rhs: BGMusicLibraryPlaylist) -> Bool {
        let lhsTracks = lhs.tracks.map { $0.manifestTrack(includeSources: true) }
        let rhsTracks = rhs.tracks.map { $0.manifestTrack(includeSources: true) }
        return lhs.title == rhs.title
            && lhs.description == rhs.description
            && lhs.authorName == rhs.authorName
            && lhsTracks == rhsTracks
    }
}
