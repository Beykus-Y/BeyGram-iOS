import Foundation
import Postbox
import BeyGramStealth

/// BeyGram stealth sending (submodules/BeyGramStealth). With the account's "scheduled send" setting on, a message that
/// the user did not schedule is sent as a Telegram scheduled message: the local copy gets the same
/// `OutgoingScheduleInfoMessageAttribute` as a message scheduled by hand, so the send pipeline stores it in the
/// scheduled namespace from the start and the server's reply cannot show it twice.
///
/// Returns nil when the batch must not go out at all: stealth scheduling is on, but a message cannot be scheduled.
/// Such a batch fails; it never goes out at once.
func beyGramStealthPreparedMessages(accountPeerId: PeerId, peerId: PeerId, nowSeconds: Int32, messages: [EnqueueMessage]) -> [EnqueueMessage]? {
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
            return nil
        }
    }
    return result
}
