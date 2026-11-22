import Foundation

/// Функции BeyGram, которые включаются флагами.
///
/// Каждый флаг относится к блоку плана переноса. Новый флаг выключен по умолчанию,
/// пока функция не проверена на устройстве.
public enum BeyGramFeature: String, CaseIterable {
    /// Блок B: политика чтения, присутствия и набора текста, отправка без следов.
    case privacyPolicy
    /// Блок C: триггер-слова и лента упоминаний.
    case triggerWords
    /// Блок D: экспорт чата.
    case chatExport
    /// Блок E: лог подключения и отчёты через бота.
    case diagnostics
    /// Блок E: проверка обновлений по GitHub Releases.
    case updateCheck
    /// Блок F: прокси Mihomo.
    case mihomoProxy
    /// Блок G: уведомления через BG Push.
    case bgPush
    /// Блок I: музыкальная библиотека и BG Mix.
    case musicLibrary
    /// Блок J: BG Media и BG Wave.
    case bgMedia
    /// Блок K: Яндекс Музыка, решение владельца отложено.
    case yandexMusic

    /// Значение, которое получает функция, пока пользователь её не переключил.
    public var defaultEnabled: Bool {
        return false
    }

    /// Название в настройках из единой системы локализации `BeyGramL10n`.
    public func title(languageCode: String?) -> String {
        switch self {
        case .privacyPolicy:
            return BeyGramL10n.shared.string(.settingsPrivacyTitle, languageCode: languageCode)
        case .triggerWords:
            return BeyGramL10n.shared.string(.settingsTriggerWordsTitle, languageCode: languageCode)
        case .chatExport:
            return BeyGramL10n.shared.string(.exportTitle, languageCode: languageCode)
        case .diagnostics:
            return BeyGramL10n.shared.string(.settingsDiagnosticsTitle, languageCode: languageCode)
        case .updateCheck:
            return BeyGramL10n.shared.string(.settingsUpdatesTitle, languageCode: languageCode)
        case .mihomoProxy:
            return BeyGramL10n.shared.string(.settingsMihomoTitle, languageCode: languageCode)
        case .bgPush:
            return BeyGramL10n.shared.string(.settingsBgPushTitle, languageCode: languageCode)
        case .musicLibrary:
            return BeyGramL10n.shared.string(.settingsMusicTitle, languageCode: languageCode)
        case .bgMedia:
            return BeyGramL10n.shared.string(.bgWaveTitle, languageCode: languageCode)
        case .yandexMusic:
            return BeyGramL10n.shared.string(.yandexTitle, languageCode: languageCode)
        }
    }
}
