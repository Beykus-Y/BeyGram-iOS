import Foundation
import TDLibKit

/// TDLib accepts snake_case JSON keys (api_id, phone_number, etc.).
/// DTO's default JSONEncoder keeps Swift camelCase names, which makes
/// TDLib silently treat required fields such as api_id as missing.
enum TelegramRequestFactory {
    enum EncodingFailure: LocalizedError {
        case invalidParameters

        var errorDescription: String? {
            "Не удалось корректно сформировать параметры TDLib. Запрос не отправлен."
        }
    }

    static func make<Payload: Codable>(_ payload: Payload) -> TdQuery {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return DTO(payload, encoder: encoder)
    }

    static func makeVerifiedParameters(
        _ parameters: SetTdlibParameters,
        expectedConfiguration: TelegramConfiguration
    ) throws -> TdQuery {
        let request = make(parameters)
        let encoded = try request.make(with: nil)

        guard let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              let type = json["@type"] as? String,
              type == "setTdlibParameters",
              let apiID = json["api_id"] as? Int,
              apiID == expectedConfiguration.apiID,
              let apiHash = json["api_hash"] as? String,
              apiHash == expectedConfiguration.apiHash,
              let databaseDirectory = json["database_directory"] as? String,
              !databaseDirectory.isEmpty else {
            throw EncodingFailure.invalidParameters
        }

        // Do not log encoded JSON: it contains Telegram API credentials and
        // the on-device database encryption key.
        return request
    }
}
