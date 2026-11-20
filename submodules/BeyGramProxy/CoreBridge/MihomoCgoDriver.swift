// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

// Mihomo core driver over the C archive built from core/cmd/beygram-mihomo.
//
// This file is not part of the Bazel target, which globs Sources/ only. It is compiled only
// in the build that links libbeygram-mihomo.a, and that build waits for the owner's license
// decision (see ../README.md). Until then the app uses UnlinkedMihomoCoreDriver.

import Foundation
import BeyGramMihomoCore

public final class MihomoCgoDriver: MihomoCoreDriver {
    public init() {}

    public func call(_ method: String, data: [String: Any]) throws -> Any? {
        let request: [String: Any] = ["id": UUID().uuidString, "method": method, "data": data]
        let requestData = try JSONSerialization.data(withJSONObject: request, options: [])
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            throw MihomoCoreError.malformedReply
        }

        // The core allocates the reply. It is copied into a Swift String, then freed.
        let replyText: String? = requestText.withCString { pointer -> String? in
            guard let reply = BGMihomoInvoke(pointer) else {
                return nil
            }
            defer {
                BGMihomoFree(reply)
            }
            return String(cString: reply)
        }

        guard let replyText = replyText,
              let replyData = replyText.data(using: .utf8),
              let envelope = try JSONSerialization.jsonObject(with: replyData) as? [String: Any],
              let code = envelope["code"] as? Int else {
            throw MihomoCoreError.malformedReply
        }
        if code != 0 {
            throw MihomoCoreError.refused(envelope["message"] as? String ?? "")
        }
        return envelope["data"]
    }
}
