import Foundation

/// What stealth mode can hide. Presence is account-wide; read receipts and typing can also be decided per chat.
public enum BeyGramStealthEffect: Sendable {
    case readHistory
    case onlinePresence
    case typing
}

/// A per-chat override. `inherit` follows the account setting.
public enum BeyGramStealthChatMode: String, Codable, Sendable {
    case inherit
    case allow
    case block
}

/// What to do with one outgoing message.
public enum BeyGramStealthSendDecision: Equatable, Sendable {
    /// Send as before: stealth scheduling is off, or the user already picked a date.
    case unchanged
    /// Send as a server-side scheduled message at this Unix time. Telegram publishes it itself.
    case scheduled(Int32)
    /// Stealth scheduling is on, but this message cannot be scheduled. It must fail, never go out at once.
    case refused
}

/// Stealth settings of one account.
public struct BeyGramStealthSettings: Codable, Equatable, Sendable {
    /// Telegram publishes anything due within 10 seconds at once, so a shorter lead could leak the send.
    public static let minimumServerLeadSeconds: Int32 = 15
    /// Lead choices offered by the settings screen.
    public static let scheduleDelayChoices: [Int32] = [15, 30, 60, 120]

    public var hideReadReceipts: Bool
    public var hideOnline: Bool
    public var hideTyping: Bool
    public var serverScheduledSend: Bool
    public var scheduledSendDelaySeconds: Int32
    /// Per-chat overrides keyed by the chat's peer id as a decimal string.
    public var chatModes: [String: BeyGramStealthChatMode]

    /// The stored keys are the Android ones (`StealthSettingsStore.kt`), so the two apps name each setting alike.
    private enum CodingKeys: String, CodingKey {
        case hideReadReceipts = "no_read_receipts"
        case hideOnline = "hide_online"
        case hideTyping = "hide_typing"
        case serverScheduledSend = "scheduled_send"
        case scheduledSendDelaySeconds = "scheduled_send_delay"
        case chatModes = "chats"
    }

    public init(
        hideReadReceipts: Bool = false,
        hideOnline: Bool = false,
        hideTyping: Bool = false,
        serverScheduledSend: Bool = false,
        scheduledSendDelaySeconds: Int32 = 15,
        chatModes: [String: BeyGramStealthChatMode] = [:]
    ) {
        self.hideReadReceipts = hideReadReceipts
        self.hideOnline = hideOnline
        self.hideTyping = hideTyping
        self.serverScheduledSend = serverScheduledSend
        self.scheduledSendDelaySeconds = scheduledSendDelaySeconds
        self.chatModes = chatModes
    }

    /// Whether `effect` may happen in the chat `chatPeerId` (nil for account-wide actions).
    public func allows(_ effect: BeyGramStealthEffect, chatPeerId: Int64?) -> Bool {
        switch effect {
        case .onlinePresence:
            // Presence is account-wide: no chat override applies to it.
            return !self.hideOnline
        case .readHistory:
            return self.allowsInChat(chatPeerId: chatPeerId, accountAllows: !self.hideReadReceipts)
        case .typing:
            return self.allowsInChat(chatPeerId: chatPeerId, accountAllows: !self.hideTyping)
        }
    }

    /// The decision for one outgoing message.
    /// - Parameters:
    ///   - explicitScheduleTime: the date the user picked, if any. Such a message is already scheduled and is left alone.
    ///   - isSchedulable: false for secret chats and paid messages, which Telegram cannot schedule.
    ///   - nowSeconds: the server clock (`network.globalTime`) at the moment of the request.
    public func sendDecision(explicitScheduleTime: Int32?, isSchedulable: Bool, nowSeconds: Int32) -> BeyGramStealthSendDecision {
        guard self.serverScheduledSend else {
            return .unchanged
        }
        if explicitScheduleTime != nil {
            return .unchanged
        }
        guard isSchedulable, self.scheduledSendDelaySeconds >= BeyGramStealthSettings.minimumServerLeadSeconds else {
            return .refused
        }
        return .scheduled(nowSeconds + self.scheduledSendDelaySeconds)
    }

    private func allowsInChat(chatPeerId: Int64?, accountAllows: Bool) -> Bool {
        if let chatPeerId = chatPeerId, let mode = self.chatModes[String(chatPeerId)] {
            switch mode {
            case .allow:
                return true
            case .block:
                return false
            case .inherit:
                break
            }
        }
        return accountAllows
    }
}
