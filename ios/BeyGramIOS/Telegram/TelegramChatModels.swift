import Foundation

/// Port of Android BeyGram's ChatPreview / ChatMessage domain fields.
/// TDLib IDs are Int64 and must never be converted through floating-point values.
enum TelegramJSON {
    static func object(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    static func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) ?? 0 }
        return 0
    }

    static func integer(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) ?? 0 }
        return 0
    }

    static func string(_ value: Any?) -> String { value as? String ?? "" }
    static func flag(_ value: Any?) -> Bool { value as? Bool ?? false }

    static func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    static func messageText(_ message: [String: Any]) -> String {
        let content = object(message["content"])
        switch string(content["@type"]) {
        case "messageText":
            return string(object(content["text"])["text"])
        case "messagePhoto": return "📷 Фото"
        case "messageVideo": return "🎬 Видео"
        case "messageVideoNote": return "⭕ Видеосообщение"
        case "messageVoiceNote": return "🎤 Голосовое сообщение"
        case "messageAudio": return "🎵 Аудио"
        case "messageDocument": return "📎 Документ"
        case "messageSticker": return "Стикер"
        case "messageAnimation": return "GIF"
        case "messagePoll": return "📊 Опрос"
        case "messageContact": return "👤 Контакт"
        case "messageLocation": return "📍 Местоположение"
        case "messageCall": return "📞 Звонок"
        case "messageService": return "Служебное сообщение"
        default: return "Сообщение"
        }
    }

    static func shortTime(_ timestamp: Int) -> String {
        guard timestamp > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct TelegramChatPreview: Identifiable, Equatable {
    let id: Int64
    let title: String
    let lastMessage: String
    let lastMessageTime: String
    let lastMessageID: Int64
    let lastMessageOutgoing: Bool
    let lastMessageSendingState: String
    let lastReadOutboxMessageID: Int64
    let unreadCount: Int
    let isMarkedAsUnread: Bool
    let canDeleteForSelf: Bool
    let isPinned: Bool
    let isMuted: Bool
    let isGroup: Bool
    let mainOrder: Int64
    let archiveOrder: Int64
    let avatarFile: TelegramMediaFile?

    /// Parity with Android ChatsScreen.previewLine and SendStatusIcon.
    var hasUnread: Bool { unreadCount > 0 || isMarkedAsUnread }

    var previewLine: String {
        if lastMessage.isEmpty {
            return isGroup ? "Пока нет сообщений в группе" : "Начните переписку"
        }
        return lastMessageOutgoing ? "Вы: " + lastMessage : lastMessage
    }

    var lastMessageRead: Bool {
        lastMessageOutgoing && lastMessageID > 0 &&
        lastReadOutboxMessageID >= lastMessageID
    }

    var lastMessageState: String {
        guard lastMessageOutgoing else { return "incoming" }
        switch lastMessageSendingState {
        case "messageSendingStatePending": return "sending"
        case "messageSendingStateFailed": return "failed"
        default: return lastMessageRead ? "read" : "sent"
        }
    }

    var initials: String {
        let pieces = title.split(separator: " ").prefix(2)
        let result = pieces.compactMap(\.first).map(String.init).joined()
        return result.isEmpty ? "?" : result.uppercased()
    }

    static func from(_ raw: [String: Any]) -> TelegramChatPreview? {
        let id = TelegramJSON.int64(raw["id"])
        guard id != 0 else { return nil }
        let type = TelegramJSON.object(raw["type"])
        let message = TelegramJSON.object(raw["last_message"])
        let positions = raw["positions"] as? [[String: Any]] ?? []
        var main: Int64 = 0
        var archive: Int64 = 0
        var pinned = false
        for position in positions {
            let list = TelegramJSON.object(position["list"])
            let order = TelegramJSON.int64(position["order"])
            switch TelegramJSON.string(list["@type"]) {
            case "chatListMain":
                main = order
                pinned = TelegramJSON.flag(position["is_pinned"])
            case "chatListArchive":
                archive = order
                pinned = TelegramJSON.flag(position["is_pinned"])
            default: break
            }
        }
        let notification = TelegramJSON.object(raw["notification_settings"])
        let muted = TelegramJSON.integer(notification["mute_for"]) > 0
        let typeName = TelegramJSON.string(type["@type"])
        return TelegramChatPreview(
            id: id,
            title: TelegramJSON.string(raw["title"]),
            lastMessage: message.isEmpty ? "" : TelegramJSON.messageText(message),
            lastMessageTime: TelegramJSON.shortTime(TelegramJSON.integer(message["date"])),
            lastMessageID: TelegramJSON.int64(message["id"]),
            lastMessageOutgoing: TelegramJSON.flag(message["is_outgoing"]),
            lastMessageSendingState: TelegramJSON.string(
                TelegramJSON.object(message["sending_state"])["@type"]
            ),
            lastReadOutboxMessageID: TelegramJSON.int64(raw["last_read_outbox_message_id"]),
            unreadCount: max(0, TelegramJSON.integer(raw["unread_count"])),
            isMarkedAsUnread: TelegramJSON.flag(raw["is_marked_as_unread"]),
            canDeleteForSelf: TelegramJSON.flag(raw["can_be_deleted_only_for_self"]),
            isPinned: pinned,
            isMuted: muted,
            isGroup: typeName == "chatTypeBasicGroup" || typeName == "chatTypeSupergroup",
            mainOrder: main,
            archiveOrder: archive,
            avatarFile: TelegramMediaFile.from(
                TelegramJSON.object(TelegramJSON.object(raw["photo"])["small"])
            )
        )
    }
}

struct TelegramMessageReaction: Identifiable, Equatable {
    let emoji: String
    let count: Int
    let isChosen: Bool
    var id: String { emoji }

    static func from(_ raw: [String: Any]) -> Self? {
        let type = TelegramJSON.object(raw["type"])
        guard TelegramJSON.string(type["@type"]) == "reactionTypeEmoji" else {
            return nil
        }
        let emoji = TelegramJSON.string(type["emoji"])
        guard !emoji.isEmpty else { return nil }
        return Self(
            emoji: emoji,
            count: TelegramJSON.integer(raw["total_count"]),
            isChosen: TelegramJSON.flag(raw["is_chosen"])
        )
    }

    static func fromInteraction(_ interaction: [String: Any]) -> [Self] {
        let summary = TelegramJSON.object(interaction["reactions"])
        let items = summary["reactions"] as? [[String: Any]] ?? []
        return items.compactMap(from)
    }
}

struct TelegramChatMessage: Identifiable, Equatable {
    let id: Int64
    let chatId: Int64
    let text: String
    let outgoing: Bool
    let timestamp: Int
    let status: String
    let isText: Bool
    let media: TelegramMessageMedia?
    let reactions: [TelegramMessageReaction]

    var time: String { TelegramJSON.shortTime(timestamp) }

    func withReactions(_ updated: [TelegramMessageReaction]) -> Self {
        Self(
            id: id, chatId: chatId, text: text, outgoing: outgoing,
            timestamp: timestamp, status: status, isText: isText,
            media: media, reactions: updated
        )
    }

    static func from(_ raw: [String: Any]) -> TelegramChatMessage? {
        let id = TelegramJSON.int64(raw["id"])
        let chatId = TelegramJSON.int64(raw["chat_id"])
        guard id != 0, chatId != 0 else { return nil }
        let content = TelegramJSON.object(raw["content"])
        let sendState = TelegramJSON.string(TelegramJSON.object(raw["sending_state"])["@type"])
        return TelegramChatMessage(
            id: id,
            chatId: chatId,
            text: TelegramJSON.messageText(raw),
            outgoing: TelegramJSON.flag(raw["is_outgoing"]),
            timestamp: TelegramJSON.integer(raw["date"]),
            status: sendState,
            isText: TelegramJSON.string(content["@type"]) == "messageText",
            media: TelegramMessageMedia.from(raw),
            reactions: TelegramMessageReaction.fromInteraction(
                TelegramJSON.object(raw["interaction_info"])
            )
        )
    }
}
