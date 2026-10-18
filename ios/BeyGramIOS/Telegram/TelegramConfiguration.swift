import Foundation

struct TelegramConfiguration: Equatable {
    let apiID: Int
    let apiHash: String

    var isValid: Bool {
        apiID > 0 && !apiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(from bundle: Bundle = .main) -> TelegramConfiguration? {
        guard let id = bundle.object(forInfoDictionaryKey: "TelegramAPIID") as? String,
              let apiID = Int(id),
              let hash = bundle.object(forInfoDictionaryKey: "TelegramAPIHash") as? String else {
            return nil
        }
        let configuration = TelegramConfiguration(apiID: apiID, apiHash: hash)
        return configuration.isValid ? configuration : nil
    }
}
