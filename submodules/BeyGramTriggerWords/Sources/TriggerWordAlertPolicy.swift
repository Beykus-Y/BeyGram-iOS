import Foundation

/// Decides, for one incoming message, whether to record a feed entry and whether to post an alert.
/// Caller gates: incoming only, not a secret chat, not outgoing. This type does not check those.
public struct TriggerWordIncomingMessage: Equatable {
    public var accountId: Int64
    public var chatId: Int64
    public var messageId: Int64
    public var messageDate: Date
    public var text: String
    public var senderName: String
    public var isChatMuted: Bool
    public var isChatOpenOnScreen: Bool
    public var isProtectedContent: Bool

    public init(accountId: Int64, chatId: Int64, messageId: Int64, messageDate: Date, text: String, senderName: String,
                isChatMuted: Bool, isChatOpenOnScreen: Bool, isProtectedContent: Bool) {
        self.accountId = accountId
        self.chatId = chatId
        self.messageId = messageId
        self.messageDate = messageDate
        self.text = text
        self.senderName = senderName
        self.isChatMuted = isChatMuted
        self.isChatOpenOnScreen = isChatOpenOnScreen
        self.isProtectedContent = isProtectedContent
    }
}

public struct TriggerWordAccountSettings: Equatable {
    public var notificationsEnabled: Bool
    public var backgroundEnabled: Bool
    public var previewsEnabled: Bool
    public var chatPreviewsEnabled: Bool

    public init(notificationsEnabled: Bool, backgroundEnabled: Bool, previewsEnabled: Bool, chatPreviewsEnabled: Bool) {
        self.notificationsEnabled = notificationsEnabled
        self.backgroundEnabled = backgroundEnabled
        self.previewsEnabled = previewsEnabled
        self.chatPreviewsEnabled = chatPreviewsEnabled
    }
}

public struct TriggerWordDecision: Equatable {
    public var postAlert: Bool
    /// The alert shows the sender and text only when true. Otherwise it names only the trigger word.
    public var alertShowsText: Bool
    /// The feed keeps text only under the same condition.
    public var feedKeepsText: Bool
    public var matchedPatterns: [String]
}

public enum TriggerWordAlertPolicy {
    /// No alert for a message older than 10 minutes, so a reconnect catch-up does not ring for old matches.
    public static let maxAlertAge: TimeInterval = 10 * 60

    /// Returns nil when the message is not checked (scope limits it to muted chats) or nothing matches.
    public static func decide(
        message: TriggerWordIncomingMessage,
        rules: [TriggerWordRule],
        scope: TriggerWordScope,
        account: TriggerWordAccountSettings,
        now: Date
    ) -> TriggerWordDecision? {
        if scope == .onlyMutedChats && !message.isChatMuted {
            return nil
        }
        let matches = TriggerWordMatcher.matchingRules(in: rules, text: message.text)
        guard !matches.isEmpty else {
            return nil
        }
        // Protected content keeps no text, same as previews off.
        let showText = account.previewsEnabled && account.chatPreviewsEnabled && !message.isProtectedContent
        let alertAllowed = account.notificationsEnabled
            && account.backgroundEnabled
            && !message.isChatOpenOnScreen
            && message.isChatMuted
            && now.timeIntervalSince(message.messageDate) <= maxAlertAge
        return TriggerWordDecision(
            postAlert: alertAllowed,
            alertShowsText: alertAllowed && showText,
            feedKeepsText: showText,
            matchedPatterns: matches.map { $0.pattern }
        )
    }
}
