import Foundation
import UIKit
import Display
import TelegramPresentationData
import AccountContext
import BeyGramKit
import BeyGramStealth

/// Stealth risk warning on the chat screen (issue #136, Android `StealthRiskGuard`). Asked once per screen: after the user
/// confirms, the risky actions that follow on this screen run without asking. Covers bot buttons; reactions and poll votes
/// are not wired yet (their optimistic local state needs a cancel path first).
extension ChatControllerImpl {
    /// True while the warning applies and the user has not yet confirmed it on this screen.
    func beyGramRiskyActionPending() -> Bool {
        if self.beyGramRiskConfirmed {
            return false
        }
        return BeyGramStealthHooks.riskyActionNeedsConfirmation(accountPeerId: self.context.account.peerId.toInt64())
    }

    /// Shows the warning. On confirm it sets the screen's flag and runs `retry`, which repeats the request.
    func beyGramConfirmRiskyAction(retry: @escaping () -> Void) {
        let sheet = ActionSheetController(presentationData: self.presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: BeyGramL10n.shared.string(.stealthRiskyTitle)),
                ActionSheetTextItem(title: BeyGramL10n.shared.string(.stealthRiskyText)),
                ActionSheetButtonItem(title: BeyGramL10n.shared.string(.stealthRiskyConfirm), color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.beyGramRiskConfirmed = true
                    retry()
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        self.present(sheet, in: .window(.root))
    }
}
