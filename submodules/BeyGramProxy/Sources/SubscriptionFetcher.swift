// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

import Foundation

public enum SubscriptionFetchError: Error, Equatable {
    case invalidAddress
    case httpStatus(Int)
    case transport
    case tooLarge
    case notText
}

/// Downloads a subscription directly, without the proxy: the proxy is not running while it is fetched.
public enum SubscriptionFetcher {
    /// The same bound as the normalizer's MaxProfileBytes.
    public static let maxBytes = 5 * 1024 * 1024

    /// True for an http or https address on one line.
    public static func isWebAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "https" || scheme == "http"
    }

    public static func fetch(_ address: String, completion: @escaping (Result<String, SubscriptionFetchError>) -> Void) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isWebAddress(trimmed), let url = URL(string: trimmed) else {
            completion(.failure(.invalidAddress))
            return
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(.failure(.transport))
                return
            }
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                completion(.failure(.httpStatus(http.statusCode)))
                return
            }
            guard let data = data else {
                completion(.failure(.transport))
                return
            }
            guard data.count <= maxBytes else {
                completion(.failure(.tooLarge))
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                completion(.failure(.notText))
                return
            }
            completion(.success(text))
        }.resume()
    }
}
