import Foundation

/// The user's acceptance of the Yandex warning. Stored in UserDefaults, off until the user accepts it.
/// The warning says the API is unofficial and that an account can be blocked.
public struct BGYandexConsent {
    public static let key = "beygram.yandex.consent.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var isAccepted: Bool {
        return defaults.bool(forKey: BGYandexConsent.key)
    }

    public func accept() {
        defaults.set(true, forKey: BGYandexConsent.key)
    }

    public func revoke() {
        defaults.removeObject(forKey: BGYandexConsent.key)
    }
}

public enum BGYandexAvailability {
    /// The source is shown only when the flag is on, the OAuth pair is set, and the warning is accepted.
    public static func isAvailable(flagEnabled: Bool, credentials: BGYandexCredentials, consentAccepted: Bool) -> Bool {
        return flagEnabled && credentials.isConfigured && consentAccepted
    }
}

public enum BGYandexWarning {
    public static func text(isRussian: Bool) -> String {
        if isRussian {
            return "Яндекс Музыка подключается через неофициальный интерфейс, который Яндекс не публиковал для сторонних приложений. "
                + "Аккаунт могут заблокировать или ограничить, и это может произойти без предупреждения. "
                + "Используйте отдельный аккаунт. Треки Яндекса нельзя пересылать, добавлять в профиль или экспортировать в .bgmusic."
        }
        return "Yandex Music is reached through an unofficial interface that Yandex does not publish for third-party apps. "
            + "The account may be blocked or restricted, without notice. "
            + "Use a separate account. Yandex tracks cannot be forwarded, added to the profile, or exported to .bgmusic."
    }
}
