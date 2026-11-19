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

    /// Название в настройках. Сейчас есть ru и en; для остальных языков возвращается en.
    public func title(languageCode: String?) -> String {
        let isRussian = languageCode == "ru"
        switch self {
        case .privacyPolicy:
            return isRussian ? "Приватность: чтение и присутствие" : "Privacy: read receipts and presence"
        case .triggerWords:
            return isRussian ? "Триггер-слова" : "Trigger words"
        case .chatExport:
            return isRussian ? "Экспорт чата" : "Chat export"
        case .diagnostics:
            return isRussian ? "Диагностика и отчёты" : "Diagnostics and reports"
        case .updateCheck:
            return isRussian ? "Проверка обновлений" : "Update check"
        case .mihomoProxy:
            return isRussian ? "Прокси Mihomo" : "Mihomo proxy"
        case .bgPush:
            return isRussian ? "Уведомления BG Push" : "BG Push notifications"
        case .musicLibrary:
            return isRussian ? "Музыкальная библиотека и BG Mix" : "Music library and BG Mix"
        case .bgMedia:
            return isRussian ? "BG Media и BG Wave" : "BG Media and BG Wave"
        case .yandexMusic:
            return isRussian ? "Яндекс Музыка" : "Yandex Music"
        }
    }
}
