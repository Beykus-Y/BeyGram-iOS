import Foundation
import Postbox
import BeyGramStealth

/// What the send path does with a batch under BeyGram stealth sending (submodules/BeyGramStealth).
enum BeyGramStealthBatch {
    /// The batch goes out as prepared: unchanged, or every message carries the server-side schedule date. `stealthDelays` has
    /// one entry per message: the delay of a message decided as a server-scheduled send, nil for a message sent as before.
    case send([EnqueueMessage], stealthDelays: [Int32?])
    /// Stealth scheduling is on, but a message cannot be scheduled. Nothing goes out and nothing is dropped: the caller
    /// stores the batch as failed messages, so the user sees it and decides (resend as it was, or delete it).
    case refused
}

/// BeyGram stealth sending. With the account's "scheduled send" setting on, a message that the user did not schedule
/// is sent as a Telegram scheduled message: the local copy gets the same `OutgoingScheduleInfoMessageAttribute` as a
/// message scheduled by hand, so the send pipeline stores it in the scheduled namespace from the start, and the
/// server's reply cannot show it twice. The date given here is provisional: it is set again when the request is built
/// (`beyGramStealthAtDispatch`), after the media is uploaded.
func beyGramStealthBatch(accountPeerId: PeerId, peerId: PeerId, nowSeconds: Int32, messages: [EnqueueMessage]) -> BeyGramStealthBatch {
    var result: [EnqueueMessage] = []
    result.reserveCapacity(messages.count)
    var stealthDelays: [Int32?] = []
    stealthDelays.reserveCapacity(messages.count)
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
            stealthDelays.append(nil)
        case let .scheduled(scheduleTime):
            result.append(message.withUpdatedAttributes { attributes in
                var updated: [MessageAttribute] = attributes
                updated.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: nil))
                return updated
            })
            stealthDelays.append(scheduleTime - nowSeconds)
        case .refused:
            return .refused
        }
    }
    return .send(result, stealthDelays: stealthDelays)
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

/// The key under which the stealth registry keeps a message. A message keeps its local id from the store until the server
/// acknowledges it, and the upload does not change that id, so the key is the same from the store to the request.
func beyGramStealthMessageKey(_ id: MessageId) -> String {
    return "\(id.peerId.toInt64()):\(id.namespace):\(id.id)"
}

/// Records, in the caller's transaction, the stored messages that were decided as server-scheduled sends, so that their date is
/// set when their request is built (`beyGramStealthAtDispatch`). A message that cannot be recorded is stored as failed instead: it
/// would otherwise keep its enqueue-time date, which can pass before its request is sent. The ids in `refusedIds` (ephemeral sends,
/// which take another path that does not know the date) are refused the same way. Returns the ids that were stored as failed.
@discardableResult
func beyGramStealthRecordScheduled(transaction: Transaction, accountPeerId: PeerId, ids: [MessageId?], stealthDelays: [Int32?], nowSeconds: Int32, refusedIds: Set<MessageId>) -> Set<MessageId> {
    var failedIds = Set<MessageId>()
    for index in 0 ..< min(ids.count, stealthDelays.count) {
        guard let delaySeconds = stealthDelays[index], let id = ids[index] else {
            continue
        }
        if !refusedIds.contains(id), let scheduleTime = transaction.getMessage(id)?.scheduleTime {
            BeyGramStealthScheduleRegistry.shared.register(accountPeerId: accountPeerId.toInt64(), messageKey: beyGramStealthMessageKey(id), delaySeconds: delaySeconds, scheduleTime: scheduleTime, nowSeconds: nowSeconds)
        } else {
            beyGramStealthMarkFailed(transaction: transaction, id: id)
            failedIds.insert(id)
        }
    }
    return failedIds
}

/// BeyGram stealth at dispatch, called when a message's request is built, after its media is uploaded. A message with a waiting
/// entry gets the date of its chosen delay from the server clock now. The stored message gets the same date in the same
/// transaction, because the server's reply is recognised as a scheduled message by comparing the local date with its own
/// (`applySentGroupMessages`): a different local date would store the reply as an ordinary message with a future date. The entry
/// is rewritten with the new date, so a retried request moves the date forward again. A message without an entry, or whose stored
/// date is not the one its entry was written with (a date the user picked, or the entry of a deleted message), is returned unchanged.
func beyGramStealthAtDispatch(transaction: Transaction, accountPeerId: PeerId, message: Message, nowSeconds: Int32) -> Message {
    guard let schedule = message.attributes.compactMap({ $0 as? OutgoingScheduleInfoMessageAttribute }).first else {
        return message
    }
    let accountId = accountPeerId.toInt64()
    let key = beyGramStealthMessageKey(message.id)
    guard let waiting = BeyGramStealthScheduleRegistry.shared.scheduledSend(accountPeerId: accountId, messageKey: key), waiting.scheduleTime == schedule.scheduleTime else {
        return message
    }
    let scheduleTime = beyGramStealthScheduleTime(nowSeconds: nowSeconds, delaySeconds: waiting.delaySeconds)
    BeyGramStealthScheduleRegistry.shared.register(accountPeerId: accountId, messageKey: key, delaySeconds: waiting.delaySeconds, scheduleTime: scheduleTime, nowSeconds: nowSeconds)
    let updatedSchedule = OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: schedule.repeatPeriod)
    transaction.updateMessage(message.id, update: { currentMessage in
        var attributes: [MessageAttribute] = currentMessage.attributes
        if let index = attributes.firstIndex(where: { $0 is OutgoingScheduleInfoMessageAttribute }) {
            attributes[index] = updatedSchedule
        } else {
            attributes.append(updatedSchedule)
        }
        var storeForwardInfo: StoreMessageForwardInfo?
        if let forwardInfo = currentMessage.forwardInfo {
            storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
        }
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
    })
    var updatedAttributes: [MessageAttribute] = message.attributes
    if let index = updatedAttributes.firstIndex(where: { $0 is OutgoingScheduleInfoMessageAttribute }) {
        updatedAttributes[index] = updatedSchedule
    }
    return message.withUpdatedAttributes(updatedAttributes)
}
