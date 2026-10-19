import Foundation

/// A search hit is identified by both chat and message ID. TDLib message IDs
/// are only unique within their chat; never use message ID alone in SwiftUI.
struct TelegramGlobalSearchHit: Identifiable, Equatable {
    let chatID: Int64
    let messageID: Int64
    let text: String
    let date: Int
    let isOutgoing: Bool

    var id: String { "\(chatID):\(messageID)" }

    var formattedDate: String {
        guard date > 0 else { return "" }
        return Date(timeIntervalSince1970: TimeInterval(date))
            .formatted(date: .abbreviated, time: .shortened)
    }

    static func from(_ raw: [String: Any]) -> Self? {
        let chatID = TelegramJSON.int64(raw["chat_id"])
        let messageID = TelegramJSON.int64(raw["id"])
        guard chatID != 0, messageID != 0 else { return nil }

        let text = TelegramJSON.messageText(raw)
        return Self(
            chatID: chatID, messageID: messageID,
            text: text, date: TelegramJSON.integer(raw["date"]),
            isOutgoing: TelegramJSON.flag(raw["is_outgoing"])
        )
    }
}
