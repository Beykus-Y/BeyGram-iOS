import Foundation

/// Runs the alert policy for one incoming message and records the mention. The app calls it for each new
/// incoming message from the account's update stream; it does not post notifications itself.
///
/// Returns the decision, or nil when the message is not checked. The caller posts the alert only when
/// `postAlert` is true. The feed keeps text only when `feedKeepsText` is true.
public enum TriggerWordsIngestor {
    public static func ingest(
        _ message: TriggerWordIncomingMessage,
        store: TriggerWordsStore,
        account: TriggerWordAccountSettings,
        now: Date
    ) -> TriggerWordDecision? {
        guard let decision = TriggerWordAlertPolicy.decide(
            message: message,
            rules: store.state.rules,
            scope: store.state.scope,
            account: account,
            now: now
        ) else {
            return nil
        }
        for pattern in decision.matchedPatterns {
            store.recordMention(TriggerWordMention(
                accountId: message.accountId,
                chatId: message.chatId,
                messageId: message.messageId,
                messageDate: message.messageDate,
                matchedPattern: pattern,
                text: decision.feedKeepsText ? message.text : nil,
                senderName: decision.feedKeepsText ? message.senderName : nil
            ))
            // One entry per message is enough: the feed is keyed by account, chat and message.
            break
        }
        return decision
    }
}
