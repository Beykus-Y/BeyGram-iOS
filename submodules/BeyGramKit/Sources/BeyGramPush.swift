import Foundation

// BG Push: уведомления для iOS без платного аккаунта Apple Developer.
//
// Клиент создаёт привязку на сервере, получает от него ingress-описание и передаёт его Telegram
// как web push токен (token_type 10). Контракт сервера: issue #30 в BeyGram-Diagnostics-Server.
// Контракт не подтверждён прототипом на iPhone: go/no-go проверяет владелец.
// Этот файл использует только Foundation. Вызовы Telegram находятся в TelegramCore (BeyGramPushRegistration.swift).

/// Статус привязки на сервере.
public enum BeyGramPushPairingStatus: String, Codable, Equatable {
    case pending
    case completed
    case expired
    case revoked
}

/// Ingress-описание, которое Telegram получает как web push токен.
public struct BeyGramPushIngress: Codable, Equatable {
    public let endpoint: String
    public let p256dh: String
    public let auth: String

    public init(endpoint: String, p256dh: String, auth: String) {
        self.endpoint = endpoint
        self.p256dh = p256dh
        self.auth = auth
    }

    /// JSON для поля `token` в `account.registerDevice` с `token_type` 10. Nil, если сериализация не удалась.
    public func registrationToken() -> String? {
        let object: [String: Any] = [
            "endpoint": self.endpoint,
            "keys": [
                "p256dh": self.p256dh,
                "auth": self.auth,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Результат создания привязки.
public struct BeyGramPushPairing: Equatable {
    public let pairingId: String
    /// Секрет для опроса статуса. Хранится только на устройстве.
    public let pollToken: String
    /// Страница установки PWA, которую открывают в Safari.
    public let setupUrl: String
    public let expiresAt: Date?
}

/// Ответ сервера на опрос привязки.
public struct BeyGramPushPollResult: Equatable {
    public let status: BeyGramPushPairingStatus
    /// Приходит только при статусе `completed`.
    public let ingress: BeyGramPushIngress?
}

public enum BeyGramPushError: Error, Equatable {
    case invalidRequest
    case network
    case http(Int)
    case decoding
}

private struct BeyGramPushPairingWire: Decodable {
    let pairingId: String
    let pollToken: String
    let setupUrl: String
    let expiresAt: String?

    private enum CodingKeys: String, CodingKey {
        case pairingId = "pairing_id"
        case pollToken = "poll_token"
        case setupUrl = "setup_url"
        case expiresAt = "expires_at"
    }
}

private struct BeyGramPushPollKeysWire: Decodable {
    let p256dh: String
    let auth: String
}

private struct BeyGramPushPollIngressWire: Decodable {
    let endpoint: String
    let keys: BeyGramPushPollKeysWire
}

private struct BeyGramPushPollWire: Decodable {
    let status: BeyGramPushPairingStatus
    let ingress: BeyGramPushPollIngressWire?
}

private func beyGramPushParseDate(_ value: String?) -> Date? {
    guard let value = value else {
        return nil
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

/// Идентификаторы в путях запроса принимаются только из безопасного набора символов.
private func beyGramPushIsSafeSegment(_ value: String) -> Bool {
    return !value.isEmpty && value.allSatisfy({ character in
        return character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
    })
}

/// HTTP-клиент BG Push. Колбэки приходят в фоновой очереди, интерфейс сам переходит на main.
public final class BeyGramPushClient {
    public static let defaultBaseUrl = URL(string: "https://beygram.beykus.fun")!

    private let baseUrl: URL
    private let session: URLSession

    public init(baseUrl: URL = BeyGramPushClient.defaultBaseUrl, session: URLSession = .shared) {
        self.baseUrl = baseUrl
        self.session = session
    }

    /// `POST /api/v1/push/pairings`: начинает привязку.
    public func createPairing(installationId: String, appVersion: String, completion: @escaping (Result<BeyGramPushPairing, BeyGramPushError>) -> Void) {
        guard beyGramPushIsSafeSegment(installationId) else {
            completion(.failure(.invalidRequest))
            return
        }
        let body: [String: Any] = [
            "installation_id": installationId,
            "platform": "ios",
            "app_version": appVersion,
        ]
        self.perform(path: "api/v1/push/pairings", method: "POST", bearerToken: nil, body: body) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let wire = try? JSONDecoder().decode(BeyGramPushPairingWire.self, from: data) else {
                    completion(.failure(.decoding))
                    return
                }
                completion(.success(BeyGramPushPairing(pairingId: wire.pairingId, pollToken: wire.pollToken, setupUrl: wire.setupUrl, expiresAt: beyGramPushParseDate(wire.expiresAt))))
            }
        }
    }

    /// `GET /api/v1/push/pairings/{id}`: читает статус привязки. Секрет опроса передаётся в заголовке.
    public func pollPairing(pairingId: String, pollToken: String, completion: @escaping (Result<BeyGramPushPollResult, BeyGramPushError>) -> Void) {
        guard beyGramPushIsSafeSegment(pairingId) else {
            completion(.failure(.invalidRequest))
            return
        }
        self.perform(path: "api/v1/push/pairings/" + pairingId, method: "GET", bearerToken: pollToken, body: nil) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let wire = try? JSONDecoder().decode(BeyGramPushPollWire.self, from: data) else {
                    completion(.failure(.decoding))
                    return
                }
                let ingress = wire.ingress.map({ BeyGramPushIngress(endpoint: $0.endpoint, p256dh: $0.keys.p256dh, auth: $0.keys.auth) })
                completion(.success(BeyGramPushPollResult(status: wire.status, ingress: ingress)))
            }
        }
    }

    /// `DELETE /api/v1/push/installations/{id}`: отзывает установку и её подписки на сервере.
    public func deleteInstallation(installationId: String, pollToken: String, completion: @escaping (Result<Void, BeyGramPushError>) -> Void) {
        guard beyGramPushIsSafeSegment(installationId) else {
            completion(.failure(.invalidRequest))
            return
        }
        self.perform(path: "api/v1/push/installations/" + installationId, method: "DELETE", bearerToken: pollToken, body: nil) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                completion(.success(()))
            }
        }
    }

    private func perform(path: String, method: String, bearerToken: String?, body: [String: Any]?, completion: @escaping (Result<Data, BeyGramPushError>) -> Void) {
        var request = URLRequest(url: self.baseUrl.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken = bearerToken {
            request.setValue("Bearer " + bearerToken, forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
                completion(.failure(.invalidRequest))
                return
            }
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let task = self.session.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(.failure(.network))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.network))
                return
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                completion(.failure(.http(httpResponse.statusCode)))
                return
            }
            completion(.success(data ?? Data()))
        }
        task.resume()
    }
}

/// Состояние BG Push на устройстве. Хранится в `UserDefaults`, как и остальные настройки BeyGram.
public struct BeyGramPushState: Codable, Equatable {
    /// Случайный id установки (UUID). Создаётся при первой настройке и удаляется вместе с привязкой.
    public var installationId: String
    public var pairingId: String?
    public var pollToken: String?
    public var setupUrl: String?
    public var expiresAt: Date?
    public var status: BeyGramPushPairingStatus?
    public var ingress: BeyGramPushIngress?
    /// Подтвердил ли Telegram регистрацию web push токена для текущего ingress.
    public var telegramRegistered: Bool

    public init(installationId: String) {
        self.installationId = installationId
        self.telegramRegistered = false
    }
}

/// Хранилище состояния BG Push поверх `UserDefaults`.
public final class BeyGramPushStore {
    public static let shared = BeyGramPushStore(defaults: UserDefaults.standard)

    private static let key = "beygram.push.state.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Текущее состояние или nil, если BG Push ещё не настраивали.
    public func load() -> BeyGramPushState? {
        guard let data = self.defaults.data(forKey: BeyGramPushStore.key) else {
            return nil
        }
        return try? JSONDecoder().decode(BeyGramPushState.self, from: data)
    }

    /// Текущее состояние. Если его нет, создаёт новое с новым id установки.
    public func loadOrCreate() -> BeyGramPushState {
        if let state = self.load() {
            return state
        }
        let state = BeyGramPushState(installationId: UUID().uuidString)
        self.save(state)
        return state
    }

    public func save(_ state: BeyGramPushState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        self.defaults.set(data, forKey: BeyGramPushStore.key)
    }

    public func clear() {
        self.defaults.removeObject(forKey: BeyGramPushStore.key)
    }
}

/// Открытие чата из уведомления. PWA строит ссылку локально: `beygram://push/open?account=<id>&peer=<id>&msg=<id>`.
/// Нативный клиент проверяет параметры сам. Если аккаунт не совпадает или чата нет, открывается список чатов.
public struct BeyGramPushOpenRequest: Equatable {
    /// Telegram user id аккаунта, которому пришло уведомление. Nil, если параметра нет.
    public let accountUserId: Int64?
    /// Id чата. Nil означает, что нужно открыть список чатов.
    public let peerId: Int64?
    /// Id сообщения. В интерфейсе пока не используется.
    public let messageId: Int32?

    /// Nil для любой ссылки, кроме `beygram://push/open`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "beygram", url.host?.lowercased() == "push", url.path == "/open" else {
            return nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func positiveValue(_ name: String) -> Int64? {
            guard let raw = items.first(where: { $0.name == name })?.value, let value = Int64(raw), value > 0 else {
                return nil
            }
            return value
        }
        self.accountUserId = positiveValue("account")
        self.peerId = positiveValue("peer")
        self.messageId = positiveValue("msg").flatMap({ Int32(exactly: $0) })
    }
}
