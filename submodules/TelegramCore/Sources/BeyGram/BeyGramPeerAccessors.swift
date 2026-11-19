import Foundation
import Postbox

/// Read-only accessors for BeyGram's chat export. They wrap internal peer helpers so other modules can use them.
public extension EnginePeer {
    var beyGramDisplayTitle: String {
        return self._asPeer().debugDisplayTitle
    }

    var beyGramIsCopyProtectionEnabled: Bool {
        return self._asPeer().isCopyProtectionEnabled
    }
}
