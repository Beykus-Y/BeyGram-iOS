import Foundation

/// Safe subset of TDLib's authorizationStateWaitCode.code_info.
/// No confirmation code, full phone number or credential is stored here.
struct TelegramCodeDeliveryInfo {
    let instructions: String
    let nextMethod: String?
    let resendAvailableAt: Date

    init?(raw: [String: Any], now: Date = Date()) {
        guard let current = raw["type"] as? [String: Any],
              let currentType = current["@type"] as? String else { return nil }

        self.instructions = Self.description(for: currentType)

        if let next = raw["next_type"] as? [String: Any],
           let nextType = next["@type"] as? String {
            self.nextMethod = Self.shortName(for: nextType)
        } else {
            self.nextMethod = nil
        }

        // The server controls the timeout. Never allow the UI to request
        // repeated codes before this value has elapsed.
        let timeout = max(0, raw["timeout"] as? Int ?? 0)
        self.resendAvailableAt = now.addingTimeInterval(TimeInterval(timeout))
    }

    private static func shortName(for type: String) -> String {
        switch type {
        case "authenticationCodeTypeTelegramMessage": return "Telegram"
        case "authenticationCodeTypeSms",
             "authenticationCodeTypeSmsWord",
             "authenticationCodeTypeSmsPhrase": return "SMS"
        case "authenticationCodeTypeCall",
             "authenticationCodeTypeFlashCall",
             "authenticationCodeTypeMissedCall": return "звонок"
        case "authenticationCodeTypeFragment": return "Fragment"
        case "authenticationCodeTypeFirebaseAndroid",
             "authenticationCodeTypeFirebaseIos": return "подтверждение устройства"
        default: return "другой способ"
        }
    }

    private static func description(for type: String) -> String {
        switch type {
        case "authenticationCodeTypeTelegramMessage":
            return "Telegram отправил код в служебный чат «Telegram» другого активного сеанса. Откройте официальный Telegram на устройстве, где уже выполнен вход."
        case "authenticationCodeTypeSms":
            return "Telegram выбрал SMS. Проверьте сообщения на номере аккаунта. Для сторонних клиентов Telegram может ограничивать SMS-вход."
        case "authenticationCodeTypeSmsWord", "authenticationCodeTypeSmsPhrase":
            return "Telegram выбрал SMS с текстовым кодом. Проверьте приложение «Сообщения» на номере аккаунта."
        case "authenticationCodeTypeCall":
            return "Telegram выбрал код по телефонному звонку. Проверьте входящие звонки."
        case "authenticationCodeTypeMissedCall", "authenticationCodeTypeFlashCall":
            return "Telegram выбрал подтверждение коротким звонком. Проверьте последние входящие вызовы."
        case "authenticationCodeTypeFragment":
            return "Telegram направил код через Fragment. Проверьте Fragment для номера вашего аккаунта."
        case "authenticationCodeTypeFirebaseIos", "authenticationCodeTypeFirebaseAndroid":
            return "Telegram ожидает Firebase-подтверждение в официальном приложении. BeyGram пока не поддерживает этот способ. Проверьте, доступна ли альтернатива после тайм-аута."
        default:
            return "Telegram запрашивает код способом «\\(shortName(for: type))». Проверьте уведомления и активные сеансы."
        }
    }
}
