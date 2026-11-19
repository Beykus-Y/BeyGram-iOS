import Foundation

/// Внешний вид: оригинальные темы Telegram или вид BeyGram рядом с ними.
public enum BeyGramAppearance: String, CaseIterable {
    case telegram
    case beygram
}

/// Настройки BeyGram: флаги функций и выбор внешнего вида.
///
/// Хранится в `UserDefaults`, а не в Postbox, поэтому модуль не зависит от аккаунта и от TelegramCore.
/// Чтение и запись можно вызывать с любого потока. Уведомление `didChangeNotification` приходит
/// в том потоке, где произошло изменение, так что интерфейс должен переходить на main сам.
public final class BeyGramSettings {
    /// Уведомление после любого изменения настроек.
    public static let didChangeNotification = Notification.Name("BeyGramSettings.didChange")

    /// Версия схемы ключей. Растёт, когда меняется формат хранения; нужна для миграций.
    public static let schemaVersion = 1

    /// Общий экземпляр поверх `UserDefaults.standard`.
    public static let shared = BeyGramSettings(defaults: UserDefaults.standard)

    private enum Keys {
        static let schemaVersion = "beygram.settings.schemaVersion"
        static let appearance = "beygram.settings.appearance"

        static func feature(_ feature: BeyGramFeature) -> String {
            return "beygram.feature." + feature.rawValue
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if defaults.integer(forKey: Keys.schemaVersion) != BeyGramSettings.schemaVersion {
            defaults.set(BeyGramSettings.schemaVersion, forKey: Keys.schemaVersion)
        }
    }

    /// Включена ли функция. Пока пользователь её не переключал, возвращается `defaultEnabled`.
    public func isEnabled(_ feature: BeyGramFeature) -> Bool {
        let key = Keys.feature(feature)
        if defaults.object(forKey: key) == nil {
            return feature.defaultEnabled
        }
        return defaults.bool(forKey: key)
    }

    public func setEnabled(_ enabled: Bool, for feature: BeyGramFeature) {
        defaults.set(enabled, forKey: Keys.feature(feature))
        postDidChange()
    }

    /// Выбранный внешний вид. Без сохранённого значения это `telegram`, то есть поведение без BeyGram.
    public var appearance: BeyGramAppearance {
        get {
            guard let raw = defaults.string(forKey: Keys.appearance), let value = BeyGramAppearance(rawValue: raw) else {
                return .telegram
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appearance)
            postDidChange()
        }
    }

    /// Возвращает все флаги к значениям по умолчанию, а внешний вид к `telegram`.
    public func resetToDefaults() {
        for feature in BeyGramFeature.allCases {
            defaults.removeObject(forKey: Keys.feature(feature))
        }
        defaults.removeObject(forKey: Keys.appearance)
        postDidChange()
    }

    private func postDidChange() {
        NotificationCenter.default.post(name: BeyGramSettings.didChangeNotification, object: self)
    }
}
