import Foundation
import BeyGramKit

/// The entry points that TelegramCore calls. While the BeyGram feature `privacyPolicy` is off, every call returns the
/// upstream behaviour, so a hook costs one settings read and changes nothing.
public enum BeyGramStealthHooks {
    /// Whether `effect` may happen. `chatPeerId` is nil for account-wide actions such as presence.
    public static func allows(_ effect: BeyGramStealthEffect, accountPeerId: Int64, chatPeerId: Int64?) -> Bool {
        guard BeyGramSettings.shared.isEnabled(.privacyPolicy) else {
            return true
        }
        return BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId).allows(effect, chatPeerId: chatPeerId)
    }

    /// Whether opening a one-time media may be reported to the server. Off while `noContentOpen` is on.
    public static func allowsOpenContentReceipt(accountPeerId: Int64) -> Bool {
        guard BeyGramSettings.shared.isEnabled(.privacyPolicy) else {
            return true
        }
        return !BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId).noContentOpen
    }

    /// The decision for one outgoing message. See `BeyGramStealthSettings.sendDecision`.
    public static func sendDecision(accountPeerId: Int64, explicitScheduleTime: Int32?, unschedulableReason: BeyGramStealthRefusal?, nowSeconds: Int32) -> BeyGramStealthSendDecision {
        guard BeyGramSettings.shared.isEnabled(.privacyPolicy) else {
            return .unchanged
        }
        return BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId).sendDecision(explicitScheduleTime: explicitScheduleTime, unschedulableReason: unschedulableReason, nowSeconds: nowSeconds)
    }
}
