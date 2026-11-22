import Foundation

/// The signed-in account, as the service describes it. `uid` only tells accounts apart; it is never shown.
public struct BGYandexAccount: Equatable {
    public let uid: String
    public let displayName: String
    public let hasPlus: Bool

    public init(uid: String, displayName: String, hasPlus: Bool) {
        self.uid = uid
        self.displayName = displayName
        self.hasPlus = hasPlus
    }
}

/// Sign-in state for the screens: signed out, or the account of the stored session.
public enum BGYandexAccountState: Equatable {
    case signedOut
    case signedIn(BGYandexAccount)
}

/// An artist of a track: the service id and the name shown.
public struct BGYandexArtistRef: Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A track of the service. Its row in the shared queue is `rowKey`: `ym:<trackId>`, or `ym:<trackId>:<albumId>` when the
/// album is known (the `BGMusicTrackKey` form). Tracks of this source may not be forwarded, exported or added to a profile.
public struct BGYandexTrack: Equatable {
    public let trackId: String
    public let title: String
    public let artists: [String]
    public let albumId: String?
    public let albumTitle: String?
    public let durationMs: Int64
    /// Cover for display. The UI loads it; it is not stored in the library.
    public let coverUrl: String?
    /// False for tracks removed, or not available in the account's region. Such tracks cannot be played.
    public let isAvailable: Bool
    /// Known only where the service reports likes (liked list, radio). Nil when unknown.
    public let liked: Bool?
    /// Artists with their ids, for a radio of an artist. Empty when the service gives no ids.
    public let artistRefs: [BGYandexArtistRef]

    public init(trackId: String, title: String, artists: [String], albumId: String?, albumTitle: String?, durationMs: Int64,
                coverUrl: String? = nil, isAvailable: Bool = true, liked: Bool? = nil, artistRefs: [BGYandexArtistRef] = []) {
        self.trackId = trackId
        self.title = title
        self.artists = artists
        self.albumId = albumId
        self.albumTitle = albumTitle
        self.durationMs = durationMs
        self.coverUrl = coverUrl
        self.isAvailable = isAvailable
        self.liked = liked
        self.artistRefs = artistRefs
    }

    /// Row key in the shared queue: `ym:<trackId>`, or `ym:<trackId>:<albumId>` when the album is known.
    public var rowKey: String {
        if let albumId = albumId, !albumId.isEmpty {
            return "ym:\(trackId):\(albumId)"
        }
        return "ym:\(trackId)"
    }

    public var performer: String {
        return artists.joined(separator: ", ")
    }

    func with(albumId newAlbumId: String) -> BGYandexTrack {
        return BGYandexTrack(trackId: trackId, title: title, artists: artists, albumId: newAlbumId, albumTitle: albumTitle,
                             durationMs: durationMs, coverUrl: coverUrl, isAvailable: isAvailable, liked: liked, artistRefs: artistRefs)
    }

    func with(liked newLiked: Bool) -> BGYandexTrack {
        return BGYandexTrack(trackId: trackId, title: title, artists: artists, albumId: albumId, albumTitle: albumTitle,
                             durationMs: durationMs, coverUrl: coverUrl, isAvailable: isAvailable, liked: newLiked, artistRefs: artistRefs)
    }
}

/// A playlist of the account (own), or one it follows (`isOwn` false, `ownerUid` needed to read its tracks).
public struct BGYandexPlaylist: Equatable {
    /// Playlist id inside the service, passed to `BGYandexService.playlistTracks`.
    public let kind: String
    public let title: String
    public let trackCount: Int
    public let coverUrl: String?
    public let isOwn: Bool
    public let ownerUid: String?
    public let ownerName: String?
    /// Uuid of the playlist's web address (`/playlists/<uuid>`). Nil when the service does not report it.
    public let uuid: String?

    public init(kind: String, title: String, trackCount: Int, coverUrl: String?, isOwn: Bool, ownerUid: String?, ownerName: String?, uuid: String?) {
        self.kind = kind
        self.title = title
        self.trackCount = trackCount
        self.coverUrl = coverUrl
        self.isOwn = isOwn
        self.ownerUid = ownerUid
        self.ownerName = ownerName
        self.uuid = uuid
    }

    /// True when the playlist's uuid is the wanted one (compared trimmed and lower-cased, as the links are).
    func matchesUuid(_ wanted: String) -> Bool {
        guard let uuid = uuid else {
            return false
        }
        return uuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == wanted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct BGYandexAlbum: Equatable {
    public let id: String
    public let title: String
    public let artists: [String]
    /// Release year, nil when unknown.
    public let year: Int?
    public let trackCount: Int
    public let coverUrl: String?

    public init(id: String, title: String, artists: [String], year: Int?, trackCount: Int, coverUrl: String?) {
        self.id = id
        self.title = title
        self.artists = artists
        self.year = year
        self.trackCount = trackCount
        self.coverUrl = coverUrl
    }

    public var performer: String {
        return artists.joined(separator: ", ")
    }
}

/// An album with its tracks, in disc and track order.
public struct BGYandexAlbumTracks: Equatable {
    public let album: BGYandexAlbum
    public let tracks: [BGYandexTrack]

    public init(album: BGYandexAlbum, tracks: [BGYandexTrack]) {
        self.album = album
        self.tracks = tracks
    }
}

/// A short-lived direct link to the audio of a full track. Never stored: it is requested right before playback.
public struct BGYandexAudio: Equatable {
    public let url: URL
    /// Codec as reported by the service. Full tracks are MP3 here.
    public let codec: String
    public let bitrateKbps: Int

    public init(url: URL, codec: String, bitrateKbps: Int) {
        self.url = url
        self.codec = codec
        self.bitrateKbps = bitrateKbps
    }
}

/// One batch of radio tracks and the session it belongs to.
public struct BGYandexWaveBatch: Equatable {
    public let sessionId: String
    public let batchId: String?
    public let tracks: [BGYandexTrack]
    /// The service no longer knows the session: a new one has to be started.
    public let unknownSession: Bool
    /// The session ended on the service side: a new one has to be started.
    public let terminated: Bool

    public init(sessionId: String, batchId: String?, tracks: [BGYandexTrack], unknownSession: Bool, terminated: Bool) {
        self.sessionId = sessionId
        self.batchId = batchId
        self.tracks = tracks
        self.unknownSession = unknownSession
        self.terminated = terminated
    }
}
