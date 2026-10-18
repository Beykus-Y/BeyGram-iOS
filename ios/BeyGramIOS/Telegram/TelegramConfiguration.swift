import Foundation

struct TelegramConfiguration: Equatable {
    let apiID: Int
    let apiHash: String

    var isValid: Bool {
        apiID > 0 && apiHash.count == 32 &&
            apiHash.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    static func load(from bundle: Bundle = .main) -> TelegramConfiguration? {
        let raw = bundle.object(forInfoDictionaryKey: "TelegramAPIID")
        let id: Int?
        if let number = raw as? NSNumber {
            id = number.intValue
        } else if let string = raw as? String {
            id = Int(string)
        } else {
            id = nil
        }

        guard let apiID = id,
              let hash = bundle.object(forInfoDictionaryKey: "TelegramAPIHash") as? String else {
            return nil
        }
        let configuration = TelegramConfiguration(apiID: apiID, apiHash: hash)
        return configuration.isValid ? configuration : nil
    }
}
