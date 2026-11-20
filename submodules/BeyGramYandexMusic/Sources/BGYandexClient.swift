import Foundation

public struct BGYandexHTTPResponse {
    public let statusCode: Int
    public let body: Data
    public let retryAfterHeader: String?

    public init(statusCode: Int, body: Data, retryAfterHeader: String?) {
        self.statusCode = statusCode
        self.body = body
        self.retryAfterHeader = retryAfterHeader
    }
}

/// Sends one request and reports the raw answer. `nil` means the network failed. Completion may run on any thread.
public protocol BGYandexTransport: AnyObject {
    func perform(_ request: URLRequest, completion: @escaping (BGYandexHTTPResponse?) -> Void)
}

/// URLSession transport. System proxies are ignored: Android sends Yandex requests directly, not through the local proxy,
/// because the service answers "unavailable" outside its regions.
public final class BGYandexURLSessionTransport: BGYandexTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = BGYandexConfig.readTimeout
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
    }

    public func perform(_ request: URLRequest, completion: @escaping (BGYandexHTTPResponse?) -> Void) {
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let http = response as? HTTPURLResponse else {
                completion(nil)
                return
            }
            completion(BGYandexHTTPResponse(statusCode: http.statusCode, body: data ?? Data(), retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After")))
        }.resume()
    }
}

public enum BGYandexError: Error, Equatable {
    case network
    case sessionExpired
    case unavailable
    case notFound
    case rateLimited
    case serviceChanged
    case unknown
}

/// The only path to Yandex. One queue, the gap between requests, and a whole-queue pause after 429.
/// Mirrors `YandexHttp.kt`. Token and body are never logged.
public final class BGYandexClient {
    private let transport: BGYandexTransport
    private let queue = DispatchQueue(label: "beygram.yandex.http")
    private var gate = BGYandexRequestGate()
    private let now: () -> TimeInterval

    public init(transport: BGYandexTransport, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.transport = transport
        self.now = now
    }

    /// Raw answer for callers that read error bodies (device flow polls answer 400 with a JSON reason).
    /// Completion runs on the client queue. `nil` means no answer.
    public func sendRaw(_ request: URLRequest, token: String?, paced: Bool, completion: @escaping (BGYandexHTTPResponse?) -> Void) {
        queue.async {
            var prepared = request
            prepared.setValue(BGYandexConfig.clientHeader, forHTTPHeaderField: "X-Yandex-Music-Client")
            prepared.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = token {
                prepared.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
            }
            let current = self.now()
            let wait = paced ? self.gate.reserve(now: current) : self.gate.pauseRemaining(now: current)
            self.queue.asyncAfter(deadline: .now() + wait) {
                self.transport.perform(prepared) { response in
                    self.queue.async {
                        guard let response = response else {
                            completion(nil)
                            return
                        }
                        if response.statusCode == 429 {
                            self.gate.reportRateLimited(retryAfterHeader: response.retryAfterHeader, now: self.now())
                        }
                        completion(response)
                    }
                }
            }
        }
    }

    /// Body of a 2xx answer, or the error that the status maps to (the same mapping as `YandexAuth.failureForCode`).
    public func send(_ request: URLRequest, token: String?, paced: Bool = true, completion: @escaping (Result<Data, BGYandexError>) -> Void) {
        sendRaw(request, token: token, paced: paced) { response in
            guard let response = response else {
                completion(.failure(.network))
                return
            }
            completion(BGYandexClient.map(response))
        }
    }

    static func map(_ response: BGYandexHTTPResponse) -> Result<Data, BGYandexError> {
        switch response.statusCode {
        case 200...299:
            return .success(response.body)
        case 401:
            return .failure(.sessionExpired)
        case 404:
            return .failure(.notFound)
        case 429:
            return .failure(.rateLimited)
        case 403, 500...599:
            return .failure(.unavailable)
        default:
            return .failure(.unknown)
        }
    }
}
