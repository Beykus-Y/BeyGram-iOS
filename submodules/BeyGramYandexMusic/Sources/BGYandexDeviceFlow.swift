import Foundation

/// The device code that the user confirms in the Yandex page (RFC 8628, as Android does it).
public struct BGYandexDeviceCode: Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUrl: String
    public let expiresIn: Int
    public let interval: Int
}

public struct BGYandexTokens: Equatable {
    public let accessToken: String
    public let refreshToken: String?
    /// Lifetime in seconds from the response, or the default when the service omitted it.
    public let expiresIn: Int
}

public enum BGYandexPollOutcome: Equatable {
    case tokens(BGYandexTokens)
    /// Keep polling at the current interval.
    case pending
    /// Keep polling, and lengthen the interval by 5 seconds (RFC 8628).
    case slowDown
    case failed(BGYandexFailure)
}

public enum BGYandexFailure: Equatable {
    case network
    case sessionExpired
    case unknown
}

public enum BGYandexDeviceFlow {
    /// Default lifetime of a token when the response omits expires_in. Tokens last about a year.
    public static let defaultTokenLifetime = 31_535_645

    /// Percent-encoding for form bodies. Only unreserved characters pass through.
    private static let formAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    public static func formBody(_ fields: [(String, String)]) -> Data {
        let encoded = fields.map { pair -> String in
            let key = pair.0
            let value = pair.1
            let k = key.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    public static func deviceCodeRequest(deviceId: String, credentials: BGYandexCredentials) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(BGYandexConfig.oauthBase)/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            ("client_id", credentials.clientId),
            ("device_id", deviceId),
            ("device_name", BGYandexConfig.deviceName),
        ])
        return request
    }

    public static func tokenPollRequest(deviceCode: String, credentials: BGYandexCredentials) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(BGYandexConfig.oauthBase)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            ("grant_type", "device_code"),
            ("code", deviceCode),
            ("client_id", credentials.clientId),
            ("client_secret", credentials.clientSecret),
        ])
        return request
    }

    /// Parses the device code response. Nil when a required field is missing.
    public static func parseDeviceCode(_ body: Data) -> BGYandexDeviceCode? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let deviceCode = json["device_code"] as? String, !deviceCode.isEmpty,
              let userCode = json["user_code"] as? String, !userCode.isEmpty,
              let verification = json["verification_url"] as? String, !verification.isEmpty else {
            return nil
        }
        let expires = (json["expires_in"] as? Int) ?? 300
        let interval = max(1, (json["interval"] as? Int) ?? 5)
        return BGYandexDeviceCode(deviceCode: deviceCode, userCode: userCode, verificationUrl: verification, expiresIn: expires, interval: interval)
    }

    /// Maps one token-poll response to an outcome. `body` is nil when the request never got an answer.
    public static func pollOutcome(statusCode: Int?, body: Data?) -> BGYandexPollOutcome {
        guard let status = statusCode, let body = body else {
            return .failed(.network)
        }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        if (200...299).contains(status) {
            guard let access = json?["access_token"] as? String, !access.isEmpty else {
                return .failed(.unknown)
            }
            let refresh = (json?["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let expires = (json?["expires_in"] as? Int) ?? defaultTokenLifetime
            return .tokens(BGYandexTokens(accessToken: access, refreshToken: refresh, expiresIn: expires))
        }
        let error = json?["error"] as? String
        switch error ?? "" {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown
        case "expired_token":
            return .failed(.sessionExpired)
        case "access_denied":
            return .failed(.unknown)
        default:
            return .failed(.unknown)
        }
    }
}
