import Foundation
import BeyGramMusicFormat

/// What a .bgmusic file would do to the library. `BGMusicLibrary.previewImport` builds it and saves nothing.
public struct BGMusicImportPreview: Equatable {
    public let manifest: BGMusicManifest
    public let cover: BGMusicCover?
    public let decision: BGMusicImportDecision
    /// The copy that a newer file would update. Nil for every other decision. A playlist made in the app is never
    /// overwritten by a file, so a match with one is offered only as a separate copy.
    public let updateTargetLocalId: String?

    public var summary: BGMusicExportSummary {
        return BGMusicExportSummary(manifest: manifest, cover: cover)
    }
}

/// What the user chose for a previewed file. `applyImport` checks that the choice fits the decision.
public enum BGMusicImportAction: Equatable {
    /// Add the file as a new playlist. When the library already has this playlist_id, the result is a separate copy.
    case addAsNewPlaylist
    /// Replace a copy's content with a newer file. Allowed only when `updateTargetLocalId` names this copy.
    case updateCopy(localId: String)
    case cancel
}

/// What `applyImport` did.
public enum BGMusicImportOutcome: Equatable {
    case added(localId: String)
    case updated(localId: String)
    case cancelled
}

public extension BGMusicLibrary {
    /// Reads a file and decides what it would do (section 10). Nothing is saved, and a refused file leaves the library
    /// as it was.
    func previewImport(data: Data) throws -> BGMusicImportPreview {
        switch BGMusicFileReader.read(data) {
        case let .playlist(manifest, cover: cover):
            let refs = try playlists().map { $0.planningRef }
            let decision = BGMusicImportPlanner.decide(
                playlistId: manifest.playlistId,
                revision: manifest.revision,
                library: refs
            )
            var updateTarget: String?
            if case .newerRevision = decision,
               let match = BGMusicImportPlanner.matchingCopy(playlistId: manifest.playlistId, library: refs),
               match.sourcePlaylistId != nil {
                updateTarget = match.localId
            }
            return BGMusicImportPreview(
                manifest: manifest,
                cover: cover,
                decision: decision,
                updateTargetLocalId: updateTarget
            )
        case let .unsupported(formatVersion: formatVersion, minReaderVersion: minReaderVersion):
            throw BGMusicLibraryError.unsupportedFormat(formatVersion: formatVersion, minReaderVersion: minReaderVersion)
        case let .invalid(error):
            throw BGMusicLibraryError.file(error)
        }
    }

    /// Applies the user's choice for a previewed file. An update is allowed only for the copy that the preview names, and
    /// a file that is not newer never updates anything.
    func applyImport(_ preview: BGMusicImportPreview, action: BGMusicImportAction) throws -> BGMusicImportOutcome {
        switch action {
        case .cancel:
            return .cancelled
        case .addAsNewPlaylist:
            let localId = makeId()
            let playlist = BGMusicLibraryPlaylist(
                localId: localId,
                isFavorites: false,
                title: preview.manifest.title,
                description: preview.manifest.description,
                authorName: preview.manifest.authorName,
                tracks: preview.manifest.tracks.map { BGMusicLibraryTrack($0) },
                revision: 0,
                updatedAt: preview.manifest.updatedAt,
                source: BGMusicLibrarySource(
                    playlistId: preview.manifest.playlistId,
                    revision: preview.manifest.revision,
                    revisionAtSource: 0
                ),
                coverFileName: nil
            )
            try store.save(playlist, cover: preview.cover)
            return .added(localId: localId)
        case let .updateCopy(localId):
            guard preview.updateTargetLocalId == localId,
                  let stored = try store.playlist(localId: localId),
                  stored.source != nil,
                  !stored.isFavorites else {
                throw BGMusicLibraryError.notAllowed
            }
            var updated = stored
            updated.title = preview.manifest.title
            updated.description = preview.manifest.description
            updated.authorName = preview.manifest.authorName
            updated.tracks = preview.manifest.tracks.map { BGMusicLibraryTrack($0) }
            updated.updatedAt = preview.manifest.updatedAt
            updated.revision = stored.revision + 1
            // The copy now matches the file, so it exports under the file's id and revision until it is edited again.
            updated.source = BGMusicLibrarySource(
                playlistId: preview.manifest.playlistId,
                revision: preview.manifest.revision,
                revisionAtSource: updated.revision
            )
            try store.save(updated, cover: preview.cover)
            return .updated(localId: localId)
        }
    }
}
