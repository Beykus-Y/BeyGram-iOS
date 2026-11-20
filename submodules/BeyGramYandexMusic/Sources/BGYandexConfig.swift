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
}
