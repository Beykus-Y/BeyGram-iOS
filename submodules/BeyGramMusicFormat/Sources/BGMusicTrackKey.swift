import Foundation

/// Row keys for music that is not stored as a local file. The same strings are used on Android,
/// so a playlist or queue written there reads back here.
///
/// - `ym:<trackId>` or `ym:<trackId>:<albumId>` for Yandex Music. The album part is dropped when blank.
/// - `bot:<queryId>:<resultId>` for a music bot result. The query id is a decimal Int64.
public enum BGMusicTrackKey: Equatable {
    case yandex(trackId: String, albumId: String?)
    case bot(queryId: Int64, resultId: String)

    private static let yandexPrefix = "ym:"
    private static let botPrefix = "bot:"

    /// Parses a key. Returns nil for anything that is not a well-formed key of either kind.
    public init?(string: String) {
        if string.hasPrefix(BGMusicTrackKey.yandexPrefix) {
            let rest = String(string.dropFirst(BGMusicTrackKey.yandexPrefix.count))
            let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = parts.first, !first.trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }
            var album: String?
            if parts.count == 2 {
                let value = String(parts[1])
                if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    album = value
                }
            }
            self = .yandex(trackId: String(first), albumId: album)
            return
        }
        if string.hasPrefix(BGMusicTrackKey.botPrefix) {
            let rest = String(string.dropFirst(BGMusicTrackKey.botPrefix.count))
            let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let queryId = Int64(parts[0]), !parts[1].isEmpty else {
                return nil
            }
            self = .bot(queryId: queryId, resultId: String(parts[1]))
            return
        }
        return nil
    }

    /// The key string. A blank album is not written.
    public var string: String {
        switch self {
        case let .yandex(trackId, albumId):
            if let albumId = albumId, !albumId.isEmpty {
                return "\(BGMusicTrackKey.yandexPrefix)\(trackId):\(albumId)"
            }
            return "\(BGMusicTrackKey.yandexPrefix)\(trackId)"
        case let .bot(queryId, resultId):
            return "\(BGMusicTrackKey.botPrefix)\(queryId):\(resultId)"
        }
    }
}
