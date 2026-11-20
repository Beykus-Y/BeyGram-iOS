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
}
