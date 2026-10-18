import Foundation

enum TelegramConnectionState: Equatable {
    case unavailable(String)
    case disconnected
    case connecting
    case ready
}

@MainActor
final class TelegramService: ObservableObject {
    @Published private(set) var state: TelegramConnectionState

    init(configuration: TelegramConfiguration? = TelegramConfiguration.load()) {
        if configuration == nil {
            state = .unavailable("Укажите Telegram API ID и API Hash для iOS-сборки.")
        } else {
            state = .unavailable("TDLib для iOS ещё не подключена. Авторизация недоступна.")
        }
    }

    // An iOS-compatible TDLib client and C/Swift bridge must be integrated
    // before any connection attempt can be implemented safely.
}
