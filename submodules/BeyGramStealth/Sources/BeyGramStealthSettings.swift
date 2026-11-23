import Foundation

/// What stealth mode can hide. Presence is account-wide; read receipts, typing and story views can also be decided per chat.
public enum BeyGramStealthEffect: Sendable {
    case readHistory
    case onlinePresence
    case typing
    case storyView
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
    /// Stealth scheduling is on, but this message cannot be scheduled, for the reason given. Nothing goes out: the batch is stored as failed messages, never sent at once and never dropped.
    case refused(BeyGramStealthRefusal)
}

/// Stealth settings of one account.
public struct BeyGramStealthSettings: Codable, Equatable, Sendable {
    /// Telegram publishes anything due within 10 seconds at once, so a shorter lead could leak the send.
    public static let minimumServerLeadSeconds: Int32 = 15
    /// Lead choices offered by the settings screen.
    public static let scheduleDelayChoices: [Int32] = [15, 30, 60, 120]
    /// What applies while the stored settings cannot be read: every protection that has a hook is on, and every send is scheduled
    /// (Android's `StealthSettings.FailClosed`). Android also turns on its content-open and risky-action switches, which iOS does
    /// not have yet. The state is not stored: the first valid write replaces it.
    public static let failClosedFallback = BeyGramStealthSettings(
        hideReadReceipts: true,
        hideOnline: true,
        hideTyping: true,
        serverScheduledSend: true,
        scheduledSendDelaySeconds: BeyGramStealthSettings.minimumServerLeadSeconds,
        chatModes: [:],
        noStoryViews: true,
        warnRiskyActions: true,
        noContentOpen: true,
        failClosed: true
    )

    public var hideReadReceipts: Bool
    public var hideOnline: Bool
    public var hideTyping: Bool
    /// Story views are not reported to the server (`stories.readStories`, `stories.incrementStoryViews`).
    public var noStoryViews: Bool
    /// Ask before a reaction or a bot button while `hideOnline` is on (Android `warnRiskyActions`, `StealthRiskGuard`).
    public var warnRiskyActions: Bool
    /// Opening a one-time media (view-once) is not reported to the server (`messages.readMessageContents`), Android `noContentOpen`.
    public var noContentOpen: Bool
    public var serverScheduledSend: Bool
    public var scheduledSendDelaySeconds: Int32
    /// Per-chat overrides keyed by the chat's peer id as a decimal string.
    public var chatModes: [String: BeyGramStealthChatMode]
    /// True while the stored settings cannot be read (see `failClosedFallback`). Never stored.
    public internal(set) var failClosed: Bool

    /// The stored keys are the Android ones (`StealthSettingsStore.kt`), so the two apps name each setting alike.
    private enum CodingKeys: String, CodingKey {
        case hideReadReceipts = "no_read_receipts"
        case hideOnline = "hide_online"
        case hideTyping = "hide_typing"
        case noStoryViews = "no_story_views"
        case warnRiskyActions = "warn_risky_actions"
        case noContentOpen = "no_content_open"
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
        chatModes: [String: BeyGramStealthChatMode] = [:],
        noStoryViews: Bool = false,
        warnRiskyActions: Bool = false,
        noContentOpen: Bool = false,
        failClosed: Bool = false
    ) {
        self.hideReadReceipts = hideReadReceipts
        self.hideOnline = hideOnline
        self.hideTyping = hideTyping
        self.serverScheduledSend = serverScheduledSend
        self.scheduledSendDelaySeconds = scheduledSendDelaySeconds
        self.chatModes = chatModes
        self.noStoryViews = noStoryViews
        self.warnRiskyActions = warnRiskyActions
        self.noContentOpen = noContentOpen
        self.failClosed = failClosed
    }

    /// A key missing from stored data takes its default, so settings written before a key existed keep what the user chose.
    /// A value of the wrong type still fails the decode, and the store then fails closed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hideReadReceipts = try container.decodeIfPresent(Bool.self, forKey: .hideReadReceipts) ?? false
        self.hideOnline = try container.decodeIfPresent(Bool.self, forKey: .hideOnline) ?? false
        self.hideTyping = try container.decodeIfPresent(Bool.self, forKey: .hideTyping) ?? false
        self.noStoryViews = try container.decodeIfPresent(Bool.self, forKey: .noStoryViews) ?? false
        self.warnRiskyActions = try container.decodeIfPresent(Bool.self, forKey: .warnRiskyActions) ?? false
        self.noContentOpen = try container.decodeIfPresent(Bool.self, forKey: .noContentOpen) ?? false
        self.serverScheduledSend = try container.decodeIfPresent(Bool.self, forKey: .serverScheduledSend) ?? false
        self.scheduledSendDelaySeconds = try container.decodeIfPresent(Int32.self, forKey: .scheduledSendDelaySeconds) ?? 15
        self.chatModes = try container.decodeIfPresent([String: BeyGramStealthChatMode].self, forKey: .chatModes) ?? [:]
        self.failClosed = false
    }

    /// Whether a risky action (a reaction, a bot button) should ask first: hidden presence is on and the warning is on.
    /// Fail closed gives both, so the question is asked.
    public var confirmsRiskyActions: Bool {
        return self.hideOnline && self.warnRiskyActions
    }

    /// Whether `effect` may happen in the chat `chatPeerId` (nil for account-wide actions).
    public func allows(_ effect: BeyGramStealthEffect, chatPeerId: Int64?) -> Bool {
        if self.failClosed {
            return false
        }
        switch effect {
        case .onlinePresence:
            // Presence is account-wide: no chat override applies to it.
            return !self.hideOnline
        case .readHistory:
            return self.allowsInChat(chatPeerId: chatPeerId, accountAllows: !self.hideReadReceipts)
        case .typing:
            return self.allowsInChat(chatPeerId: chatPeerId, accountAllows: !self.hideTyping)
        case .storyView:
            return self.allowsInChat(chatPeerId: chatPeerId, accountAllows: !self.noStoryViews)
        }
    }

    /// The decision for one outgoing message.
    /// - Parameters:
    ///   - explicitScheduleTime: the date the user picked, if any. Such a message is already scheduled and is left alone.
    ///   - unschedulableReason: why Telegram cannot schedule this message (a secret chat or a paid message), or nil when it can.
    ///   - nowSeconds: the server clock (`network.globalTime`) at the moment of the request.
    public func sendDecision(explicitScheduleTime: Int32?, unschedulableReason: BeyGramStealthRefusal?, nowSeconds: Int32) -> BeyGramStealthSendDecision {
        guard self.serverScheduledSend || self.failClosed else {
            return .unchanged
        }
        if explicitScheduleTime != nil {
            return .unchanged
        }
        if let reason = unschedulableReason {
            return .refused(reason)
        }
        guard self.scheduledSendDelaySeconds >= BeyGramStealthSettings.minimumServerLeadSeconds else {
            return .refused(.leadTooShort)
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
