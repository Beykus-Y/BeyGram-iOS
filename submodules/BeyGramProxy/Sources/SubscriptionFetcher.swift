// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

import Foundation

public enum SubscriptionFetchError: Error, Equatable {
    case invalidAddress
    case httpStatus(Int)
    case transport
    case tooLarge
    case notText
    /// The host redirected to another site. The request stops there, so the installation ID is not sent to that site.
    case redirectedToOtherSite
}

/// Downloads a subscription directly, without the proxy: the proxy is not running while it is fetched.
public enum SubscriptionFetcher {
    /// The same bound as the normalizer's MaxProfileBytes.
    public static let maxBytes = 5 * 1024 * 1024
    /// The header that carries the installation identifier. The Android client sends the same header.
    public static let installationHeader = "X-BeyGram-HWID"

    /// True for an http or https address on one line.
    public static func isWebAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "https" || scheme == "http"
    }

    /// The scheme, host and port of a URL, with the default port filled in, for example "https://host:443".
    /// Two addresses with the same origin are the same site for the installation ID.
    static func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\((url.host ?? "").lowercased()):\(port)"
    }

    /// Downloads the address. `installationId` goes in `X-BeyGram-HWID`, and a redirect to another origin stops the
    /// request, so the identifier never reaches another site. Each fetch uses its own session for that rule.
    public static func fetch(_ address: String, installationId: String? = nil, completion: @escaping (Result<String, SubscriptionFetchError>) -> Void) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isWebAddress(trimmed), let url = URL(string: trimmed) else {
            completion(.failure(.invalidAddress))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if let installationId = installationId {
            request.setValue(installationId, forHTTPHeaderField: installationHeader)
        }
        let redirects = SubscriptionRedirectGuard(origin: origin(of: url))
        let session = URLSession(configuration: .default, delegate: redirects, delegateQueue: nil)
        session.dataTask(with: request) { data, response, error in
            session.finishTasksAndInvalidate()
            if redirects.refusedRedirect {
                completion(.failure(.redirectedToOtherSite))
                return
            }
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

/// Follows a redirect only to the origin of the first request, and refuses any other. Both callbacks run on the
/// session's serial delegate queue, so `refusedRedirect` needs no lock.
private final class SubscriptionRedirectGuard: NSObject, URLSessionTaskDelegate {
    private let origin: String
    private(set) var refusedRedirect = false

    init(origin: String) {
        self.origin = origin
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, SubscriptionFetcher.origin(of: url) == origin {
            completionHandler(request)
        } else {
            refusedRedirect = true
            completionHandler(nil)
        }
    }
}
