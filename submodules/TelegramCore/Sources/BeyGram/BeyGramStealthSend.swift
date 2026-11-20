import Foundation
import Postbox
import BeyGramStealth

/// What the send path does with a batch under BeyGram stealth sending (submodules/BeyGramStealth).
enum BeyGramStealthBatch {
    /// The batch goes out as prepared: unchanged, or every message carries the server-side schedule date.
    case send([EnqueueMessage])
    /// Stealth scheduling is on, but a message cannot be scheduled. Nothing goes out and nothing is dropped: the caller
    /// stores the batch as failed messages, so the user sees it and decides (resend as it was, or delete it).
    case refused
}

/// BeyGram stealth sending. With the account's "scheduled send" setting on, a message that the user did not schedule
/// is sent as a Telegram scheduled message: the local copy gets the same `OutgoingScheduleInfoMessageAttribute` as a
/// message scheduled by hand, so the send pipeline stores it in the scheduled namespace from the start, and the
/// server's reply cannot show it twice.
func beyGramStealthBatch(accountPeerId: PeerId, peerId: PeerId, nowSeconds: Int32, messages: [EnqueueMessage]) -> BeyGramStealthBatch {
    var result: [EnqueueMessage] = []
    result.reserveCapacity(messages.count)
    // Secret chats cannot be scheduled by Telegram. Their sends would not carry the schedule attribute, so they are refused here.
    let chatCanBeScheduled = peerId.namespace != Namespaces.Peer.SecretChat
    for message in messages {
        var explicitScheduleTime: Int32? = nil
        var isSchedulable = chatCanBeScheduled
        for attribute in message.attributes {
            if let scheduleAttribute = attribute as? OutgoingScheduleInfoMessageAttribute {
                explicitScheduleTime = scheduleAttribute.scheduleTime
            } else if attribute is PaidStarsMessageAttribute {
                isSchedulable = false
            }
        }
        let decision = BeyGramStealthHooks.sendDecision(
            accountPeerId: accountPeerId.toInt64(),
            explicitScheduleTime: explicitScheduleTime,
            isSchedulable: isSchedulable,
            nowSeconds: nowSeconds
        )
        switch decision {
        case .unchanged:
            result.append(message)
        case let .scheduled(scheduleTime):
            result.append(message.withUpdatedAttributes { attributes in
                var updated: [MessageAttribute] = attributes
                updated.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: nil))
                return updated
            })
        case .refused:
            return .refused
        }
    }
    return .send(result)
}

/// Marks a message that `transaction` has just stored as failed. A failed message is not pending, so the pending manager
/// never sends it, and the chat shows the usual failed marker with its resend and delete actions. This is the rewrite
/// that `failMessages` (PendingMessageManager.swift) makes, done in the caller's transaction, so the message is never
/// pending between the store and the mark.
func beyGramStealthMarkFailed(transaction: Transaction, id: MessageId) {
    transaction.updateMessage(id, update: { currentMessage in
        var storeForwardInfo: StoreMessageForwardInfo?
        if let forwardInfo = currentMessage.forwardInfo {
            storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
        }
        return .update(StoreMessage(id: id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: [.Failed], tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: currentMessage.attributes, media: currentMessage.media))
    })
}
