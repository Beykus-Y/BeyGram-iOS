import Foundation
import UIKit
import Display
import AccountContext
import TelegramCore
import BeyGramChatExportUI

extension PeerInfoScreenNode {
    /// Opens the BeyGram export screen for this peer. Called only from the export row, which is behind the chatExport flag.
    func openBeyGramChatExport(peer: EnginePeer) {
        let controller = chatExportController(
            context: self.context,
            peerId: peer.id,
            chatTitle: peer.beyGramDisplayTitle,
            accountLabel: "BeyGram",
            hasProtectedContent: peer.beyGramIsCopyProtectionEnabled
        )
        self.controller?.push(controller)
    }
}
