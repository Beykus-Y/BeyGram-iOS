import Foundation

/// Refresh of the access token with the refresh token (grant `refresh_token`), as `YandexAuth.refresh` does on Android.
public enum BGYandexTokenRefresh {
    public enum Outcome: Equatable {
        case tokens(BGYandexTokens)
        /// The service refused the refresh token (HTTP 400 to 403). The session is over, and the user signs in again.
        case sessionExpired
        /// No answer, a server error, or an answer without an access token. The stored tokens stay; a later call tries again.
        case unavailable
    }

    public static func request(refreshToken: String, credentials: BGYandexCredentials) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(BGYandexConfig.oauthBase)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = BGYandexDeviceFlow.formBody([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", credentials.clientId),
            ("client_secret", credentials.clientSecret),
        ])
        return request
    }

    /// Maps one answer of the token endpoint to an outcome. `statusCode` is nil when the request got no answer.
    public static func outcome(statusCode: Int?, body: Data?) -> Outcome {
        guard let status = statusCode else {
            return .unavailable
        }
        if (200...299).contains(status) {
            guard let body = body,
                  let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
                  let access = json["access_token"] as? String, !access.isEmpty else {
                return .unavailable
            }
            let refresh = (json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let expires = (json["expires_in"] as? Int) ?? BGYandexDeviceFlow.defaultTokenLifetime
            return .tokens(BGYandexTokens(accessToken: access, refreshToken: refresh, expiresIn: expires))
        }
        if (400...403).contains(status) {
            return .sessionExpired
        }
        return .unavailable
    }
}
