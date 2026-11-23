import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import BeyGramKit
import BeyGramStealth

/// Per-chat stealth mode in the peer info screen (issue #135, Android `ChatStealthSection`).
/// Shown only while the stealth master switch (`BeyGramFeature.privacyPolicy`) is on.

func beyGramChatStealthRowVisible() -> Bool {
    return BeyGramSettings.shared.isEnabled(.privacyPolicy)
}

func beyGramChatStealthMode(accountPeerId: Int64, chatPeerId: EnginePeer.Id) -> BeyGramStealthChatMode {
    return BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId).chatModes[String(chatPeerId.toInt64())] ?? .inherit
}

func beyGramChatStealthModeTitle(_ mode: BeyGramStealthChatMode) -> String {
    switch mode {
    case .inherit:
        return BeyGramL10n.shared.string(.chatStealthInherit)
    case .allow:
        return BeyGramL10n.shared.string(.chatStealthAllow)
    case .block:
        return BeyGramL10n.shared.string(.chatStealthBlock)
    }
}

/// Opens the choice of the per-chat mode. The chosen mode is stored per account and per chat; `inherit` removes the override.
func presentBeyGramChatStealthSheet(accountPeerId: Int64, chatPeerId: EnginePeer.Id, presentationData: PresentationData, controller: ViewController?) {
    guard let controller else {
        return
    }
    let chatKey = String(chatPeerId.toInt64())
    let current = beyGramChatStealthMode(accountPeerId: accountPeerId, chatPeerId: chatPeerId)

    let actionSheet = ActionSheetController(presentationData: presentationData)

    func choice(_ mode: BeyGramStealthChatMode) -> ActionSheetItem {
        let title = beyGramChatStealthModeTitle(mode) + (mode == current ? " ✓" : "")
        return ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            BeyGramStealthStore.shared.update(accountPeerId: accountPeerId) { settings in
                if mode == .inherit {
                    settings.chatModes[chatKey] = nil
                } else {
                    settings.chatModes[chatKey] = mode
                }
            }
        })
    }

    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: BeyGramL10n.shared.string(.chatStealthSheetTitle)),
            choice(.inherit),
            choice(.allow),
            choice(.block)
        ]),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    controller.present(actionSheet, in: .window(.root))
}
