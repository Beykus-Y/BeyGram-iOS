import Foundation
import Postbox
import TelegramCore
import AccountContext
import BeyGramKit
import BeyGramTriggerWords

private func triggerWordSenderName(_ peer: Peer?) -> String {
    if let user = peer as? TelegramUser {
        return [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
    }
    if let channel = peer as? TelegramChannel {
        return channel.title
    }
    if let group = peer as? TelegramGroup {
        return group.title
    }
    return ""
}

/// Feeds new incoming messages of one account to the trigger-word ingestor. Called from the app's
/// new-message stream (`stateManager.notificationMessages`), one call per batch.
///
/// Nothing is recorded while the flag is off or there are no rules. Secret chats and outgoing messages are skipped.
/// Previews are treated as off for now: the feed keeps no text until the global preview setting is read.
/// Alerts are not posted from here yet.
public func ingestTriggerWordsFromAccount(
    context: AccountContext,
    batches: [([Message], PeerGroupId, Bool, MessageHistoryThreadData?)]
) {
    guard BeyGramSettings.shared.isEnabled(.triggerWords) else {
        return
    }
    let store = TriggerWordsStore.shared
    guard !store.state.rules.isEmpty else {
        return
    }
    let accountSettings = TriggerWordAccountSettings(
        notificationsEnabled: true,
        backgroundEnabled: true,
        previewsEnabled: false,
        chatPreviewsEnabled: false
    )
    let accountId = context.account.id.int64
    let now = Date()
    for (messages, _, notify, _) in batches {
        for message in messages {
            guard message.flags.contains(.Incoming), message.id.peerId.namespace != Namespaces.Peer.SecretChat else {
                continue
            }
            let incoming = TriggerWordIncomingMessage(
                accountId: accountId,
                chatId: message.id.peerId.toInt64(),
                messageId: Int64(message.id.id),
                messageDate: Date(timeIntervalSince1970: TimeInterval(message.timestamp)),
                text: message.text,
                senderName: triggerWordSenderName(message.author),
                isChatMuted: !notify,
                isChatOpenOnScreen: false,
                isProtectedContent: message.flags.contains(.CopyProtected)
            )
            _ = TriggerWordsIngestor.ingest(incoming, store: store, account: accountSettings, now: now)
        }
    }
}
