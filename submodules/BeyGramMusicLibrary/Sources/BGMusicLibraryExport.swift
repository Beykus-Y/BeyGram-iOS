import Foundation
import BeyGramMusicFormat

/// What a shared file carries. The owner decides each one before the file is made (section 9). There are no defaults:
/// the caller passes the owner's choice every time.
public struct BGMusicExportOptions: Equatable {
    /// Writes the owner's name as the author (section 9: only with the owner's consent).
    public var includeAuthor: Bool
    /// Writes the public post hints of each track.
    public var includeSources: Bool
    /// Writes the playlist's cover.
    public var includeCover: Bool

    public init(includeAuthor: Bool, includeSources: Bool, includeCover: Bool) {
        self.includeAuthor = includeAuthor
        self.includeSources = includeSources
        self.includeCover = includeCover
    }
}

public extension BGMusicLibrary {
    /// The manifest that a playlist exports as. A copy without local changes keeps its source playlist_id and revision.
    /// An edited copy, and a playlist made in the app, export under their own id and revision (section 10).
    func exportManifest(for playlist: BGMusicLibraryPlaylist, options: BGMusicExportOptions) -> BGMusicManifest {
        let identity = BGMusicExportIdentity.resolve(playlist.planningRef, freshId: makeId)
        return BGMusicManifest(
            playlistId: identity.playlistId,
            revision: identity.revision,
            title: playlist.title,
            description: playlist.description,
            updatedAt: playlist.updatedAt,
            authorName: options.includeAuthor ? playlist.authorName : nil,
            tracks: playlist.tracks.map { $0.manifestTrack(includeSources: options.includeSources) }
        )
    }

    /// Writes the playlist as a .bgmusic file into `directory`, named from its title, and returns the file's URL. A
    /// playlist that the format refuses leaves no file behind (see `BGMusicPackage.writeFile`).
    func exportFile(for playlist: BGMusicLibraryPlaylist, options: BGMusicExportOptions, into directory: URL) throws -> URL {
        let manifest = exportManifest(for: playlist, options: options)
        var cover: BGMusicCover?
        if options.includeCover {
            cover = try store.cover(localId: playlist.localId)
        }
        switch BGMusicPackage.writeFile(manifest, cover: cover, into: directory) {
        case let .success(url):
            return url
        case let .failure(error):
            throw BGMusicLibraryError.write(error)
        }
    }
}
