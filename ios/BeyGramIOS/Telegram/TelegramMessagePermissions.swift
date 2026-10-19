import Foundation

/// Scoped to one message id. Never reuse a response for another message.
struct TelegramMessagePermissions: Equatable {
    let canReply: Bool
    let canEdit: Bool
    let canCopy: Bool
    let canDeleteForSelf: Bool
    let canDeleteForEveryone: Bool

    static func from(_ raw: [String: Any]) -> Self? {
        guard TelegramJSON.string(raw["@type"]) == "messageProperties" else { return nil }
        return Self(
            canReply: TelegramJSON.flag(raw["can_be_replied"]),
            canEdit: TelegramJSON.flag(raw["can_be_edited"]),
            canCopy: TelegramJSON.flag(raw["can_be_copied"]),
            canDeleteForSelf: TelegramJSON.flag(raw["can_be_deleted_only_for_self"]),
            canDeleteForEveryone: TelegramJSON.flag(raw["can_be_deleted_for_all_users"])
        )
    }
}
