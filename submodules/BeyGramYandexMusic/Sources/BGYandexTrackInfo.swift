import Foundation

/// What a player shows for a Yandex track, kept apart from the file the player reads. The row key is the track's identity in
/// the queue, and a file name is never a title: a track copied into a mix folder keeps this value, whatever its name on disk.
public struct BGYandexTrackInfo: Equatable {
    /// The row key the track is queued under: `ym:<trackId>`, or `ym:<trackId>:<albumId>` when the album is known.
    public let rowKey: String
    /// The Yandex track id.
    public let trackId: String
    /// The title as Yandex sent it. Nil when Yandex sent none: the UI supplies its own localized fallback, never a file name.
    public let title: String?
    /// The artists in Yandex's order, without blank names.
    public let artists: [String]
    /// The album title, when Yandex sent one.
    public let albumTitle: String?
    /// The length in seconds, when Yandex sent one.
    public let durationSeconds: Double?
    /// The cover address, when Yandex sent one. The screens load it; the player does not keep it.
    public let coverURL: URL?
    /// False when Yandex marks the track unavailable. Such a track cannot be played.
    public let isAvailable: Bool
    /// Whether the account has the track liked. Nil when Yandex did not say.
    public let liked: Bool?

    public init(track: BGYandexTrack) {
        self.rowKey = track.rowKey
        self.trackId = track.trackId
        self.title = BGYandexTrackInfo.nonBlank(track.title)
        self.artists = track.artists.compactMap { BGYandexTrackInfo.nonBlank($0) }
        self.albumTitle = track.albumTitle.flatMap { BGYandexTrackInfo.nonBlank($0) }
        self.durationSeconds = track.durationMs > 0 ? Double(track.durationMs) / 1000 : nil
        self.coverURL = track.coverUrl.flatMap { URL(string: $0) }
        self.isAvailable = track.isAvailable
        self.liked = track.liked
    }

    /// The text without its surrounding spaces, or nil when nothing is left of it.
    static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
