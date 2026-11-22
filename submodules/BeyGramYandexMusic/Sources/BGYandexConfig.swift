import Foundation

/// Protocol constants shared with the Android client (`YandexConfig.kt`). The OAuth pair is not in source:
/// it is injected at build time, the same way Android reads `secrets.properties`. When it is empty the source is hidden.
public struct BGYandexCredentials: Equatable {
    public let clientId: String
    public let clientSecret: String

    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    /// Reads the pair from the app's Info.plist keys `BGYandexClientId` and `BGYandexClientSecret`, which the build fills in
    /// from a local secrets file. Nothing is committed. Missing keys give an unconfigured pair.
    public static func fromBundle(_ bundle: Bundle = .main) -> BGYandexCredentials {
        let id = bundle.object(forInfoDictionaryKey: "BGYandexClientId") as? String ?? ""
        let secret = bundle.object(forInfoDictionaryKey: "BGYandexClientSecret") as? String ?? ""
        return BGYandexCredentials(clientId: id, clientSecret: secret)
    }

    public var isConfigured: Bool {
        return !clientId.trimmingCharacters(in: .whitespaces).isEmpty && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum BGYandexConfig {
    public static let oauthBase = "https://oauth.yandex.ru"
    public static let apiBase = "https://api.music.yandex.net"
    /// Header values the service expects from a client, identical to Android.
    public static let clientHeader = "YandexMusicAndroid/24024312"
    /// User-Agent of the Android client's HTTP stack (`YandexConfig.USER_AGENT`), sent with every request as Android does.
    public static let userAgent = "okhttp/4.12.0"
    /// Gap between two requests from this app.
    public static let minRequestGap: TimeInterval = 0.25
    /// Pause after 429 when the response has no Retry-After.
    public static let defaultRetryAfter: TimeInterval = 5
    /// Name shown to Yandex during device sign-in.
    public static let deviceName = "BeyGram"
    /// Salt of the legacy download link signature (download-info XML). Public protocol constant, as on Android.
    public static let downloadSignSalt = "XGRlBW9FXlekgbPrRHuSiA"
    /// Timeouts, as on Android.
    public static let connectTimeout: TimeInterval = 10
    public static let readTimeout: TimeInterval = 15
    /// The access token is refreshed this long before it expires (Android: 5 minutes).
    public static let refreshMargin: TimeInterval = 5 * 60
    /// Track lists are requested in chunks of this many ids (Android: 100).
    public static let trackChunk = 100
    /// Only the last tracks of a radio's history are sent back, so the service does not repeat them (Android: 50).
    public static let queueHint = 50
    /// Empty or failed radio batches in a row before a request gives up for now (Android: 2).
    public static let maxEmptyWaveBatches = 2
    /// Where the radio was started from, as the official mobile client reports it for the personal wave.
    public static let waveFrom = "radio-mobile-user-onyourwave"
    /// Lyrics: a text found is kept for 10 minutes, a failure for one minute, at most `lyricsCacheLimit` entries (Android).
    public static let lyricsFoundTTL: TimeInterval = 10 * 60
    public static let lyricsFailedTTL: TimeInterval = 60
    public static let lyricsCacheLimit = 64
}
