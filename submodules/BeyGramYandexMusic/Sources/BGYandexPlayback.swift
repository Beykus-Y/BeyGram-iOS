import Foundation

/// The process-wide Yandex service. Playback and the screens must share one session, one request gate and one token store:
/// two services would refresh the same token separately and pace their requests apart.
public enum BGYandexRuntime {
    /// `Application Support/beygram/yandex`: where the downloaded tracks live. The folder is excluded from backups.
    public static var trackFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support.appendingPathComponent("beygram/yandex", isDirectory: true)
    }

    /// The service of the app, created on first use.
    public static let shared = BGYandexService(credentials: BGYandexCredentials.fromBundle(), cacheDirectory: BGYandexRuntime.trackFolder)
}

/// Why a track cannot be played from the Yandex source. None of these logs the user out. `notSignedIn` and
/// `subscriptionRequired` concern the whole account, the others one track. The caller decides what to show.
public enum BGYandexPlaybackError: Error, Equatable {
    /// Nobody is signed in to the Yandex source.
    case notSignedIn
    /// The account has no subscription. Only previews exist for it, and previews are never played as full tracks.
    case subscriptionRequired
    /// The track is removed, not available in the account's region, or the service refused its link.
    case unavailable
    /// The service asked to slow down. Try again later.
    case rateLimited
    /// There is no connection, or the download failed on the way.
    case network
    /// The file Yandex sent is not a readable track: an error page, a text body or a cut-off file. Nothing is kept; the next try downloads it again.
    case invalidFile
}

/// The playback side of the Yandex source: row keys and the file the player reads.
public enum BGYandexPlayback {
    /// The track id of a `ym:` row key (`ym:<trackId>` or `ym:<trackId>:<albumId>`), or nil for any other row.
    public static func trackId(rowKey: String) -> String? {
        let parts = rowKey.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3, parts[0] == "ym", BGYandexLink.isNumericId(parts[1]) else {
            return nil
        }
        if parts.count == 3 && !BGYandexLink.isNumericId(parts[2]) {
            return nil
        }
        return parts[1]
    }

    /// The player's error for a service error. Failures the service does not classify count as unavailable, so the player
    /// does not retry them forever.
    static func error(for error: BGYandexError) -> BGYandexPlaybackError {
        switch error {
        case .notSignedIn, .sessionExpired:
            return .notSignedIn
        case .subscriptionRequired:
            return .subscriptionRequired
        case .rateLimited:
            return .rateLimited
        case .network:
            return .network
        case .invalidFile:
            return .invalidFile
        case .unavailable, .notFound, .serviceChanged, .unknown:
            return .unavailable
        }
    }
}

extension BGYandexService {
    /// A file the player can read for a `ym:` row: the downloaded MP3 when it is on disk, otherwise a fresh download. Needs a
    /// signed-in account with a subscription. Completes on the main queue.
    public func playableFile(rowKey: String, completion: @escaping (Result<URL, BGYandexPlaybackError>) -> Void) {
        guard let trackId = BGYandexPlayback.trackId(rowKey: rowKey) else {
            completion(.failure(.unavailable))
            return
        }
        switch accountState {
        case .signedOut:
            completion(.failure(.notSignedIn))
            return
        case let .signedIn(account):
            guard account.hasPlus else {
                completion(.failure(.subscriptionRequired))
                return
            }
        }
        resolver.localFile(trackId: trackId) { result in
            completion(result.mapError(BGYandexPlayback.error(for:)))
        }
    }
}
