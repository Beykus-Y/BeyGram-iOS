import Foundation

// BG Push: уведомления для iOS без платного аккаунта Apple Developer.
//
// Клиент создаёт регистрацию на сервере и получает от него ingress-адрес. Затем Telegram получает этот адрес
// как web push токен (token_type 10). Контракт: раздел «API для нативного клиента» в docs/bg-push.md
// репозитория BeyGram-Diagnostics-Server (issue #30). Контракт не подтверждён прототипом на iPhone:
// go/no-go проверяет владелец. Секреты лежат в Keychain (BeyGramPushSecrets.swift), вызовы Telegram в TelegramCore.

/// Статус регистрации на сервере. Совпадает с полем `state` ответа.
public enum BeyGramPushRegistrationState: String, Codable, Equatable {
    case pending
    case active
    case expired
    case revoked
}

/// Ключи ingress, которыми Telegram шифрует уведомления. Сервер отдаёт их владельцу, когда регистрация `active`.
public struct BeyGramPushTelegramKeys: Codable, Equatable {
    public let p256dh: String
    public let auth: String

    public init(p256dh: String, auth: String) {
        self.p256dh = p256dh
        self.auth = auth
    }
}

/// Web push токен для `account.registerDevice` с `token_type` 10: адрес ingress и его ключи.
public struct BeyGramPushTelegramToken: Codable, Equatable {
    public let endpoint: String
    public let keys: BeyGramPushTelegramKeys

    public init(endpoint: String, keys: BeyGramPushTelegramKeys) {
        self.endpoint = endpoint
        self.keys = keys
    }

    /// JSON для поля `token`. Nil, если кодирование не удалось.
    public func registrationToken() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Bearer владельца: 256 случайных бит в base64url без дополнения, то есть 43 символа, как ожидает сервер.
public enum BeyGramPushBearer {
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min ... UInt8.max)
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Регистрация, которую вернул сервер при создании. Адрес ingress и ссылка установки отдаются один раз.
public struct BeyGramPushRegistration: Equatable {
    public let registrationId: String
    public let state: BeyGramPushRegistrationState
    public let expiresAt: Date?
    public let ingressUrl: String
    /// Страница установки PWA. Одноразовый код привязки передаётся в её фрагменте.
    public let setupUrl: String
}

/// Ответ сервера на опрос регистрации.
public struct BeyGramPushRegistrationStatus: Equatable {
    public let state: BeyGramPushRegistrationState
    /// Срок установки. Приходит, пока регистрация `pending`.
    public let expiresAt: Date?
    /// Ключи Telegram. Приходят владельцу, когда регистрация `active`.
    public let telegramKeys: BeyGramPushTelegramKeys?
    /// Когда сервер получил подтверждение от клиента. Nil, пока его нет.
    public let telegramConfirmedAt: Date?
}

public enum BeyGramPushError: Error, Equatable {
    case invalidRequest
    case network
    case http(Int)
    case decoding
}

private struct BeyGramPushCreateWire: Decodable {
    let registrationId: String
    let state: BeyGramPushRegistrationState
    let expiresAt: Double?
    let ingressUrl: String
    let setupUrl: String
}

private struct BeyGramPushStatusWire: Decodable {
    let state: BeyGramPushRegistrationState
    let expiresAt: Double?
    let telegramConfirmedAt: Double?
    let telegramKeys: BeyGramPushTelegramKeys?
}

/// Ключи ответа сервера приходят в snake_case (`registration_id`, `ingress_url`, `telegram_keys`).
private func beyGramPushDecode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(type, from: data)
}

/// Временные метки сервера приходят как Unix-время в секундах.
private func beyGramPushDate(_ seconds: Double?) -> Date? {
    guard let seconds = seconds else {
        return nil
    }
    return Date(timeIntervalSince1970: seconds)
}

/// Идентификаторы в путях запроса принимаются только из безопасного набора символов.
private func beyGramPushIsSafeSegment(_ value: String) -> Bool {
    return !value.isEmpty && value.allSatisfy({ character in
        return character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
    })
}

/// HTTP-клиент BG Push. Колбэки приходят в фоновой очереди, интерфейс сам переходит на main.
/// Все запросы владельца авторизуются его bearer. Ingress и PWA сюда не ходят.
public final class BeyGramPushClient {
    public static let defaultBaseUrl = URL(string: "https://beygram.beykus.fun")!

    private let baseUrl: URL
    private let session: URLSession

    public init(baseUrl: URL = BeyGramPushClient.defaultBaseUrl, session: URLSession = .shared) {
        self.baseUrl = baseUrl
        self.session = session
    }

    /// `POST /api/v1/push/registrations`: создаёт регистрацию. Тело запроса не нужно.
    public func createRegistration(bearer: String, completion: @escaping (Result<BeyGramPushRegistration, BeyGramPushError>) -> Void) {
        self.perform(path: "api/v1/push/registrations", method: "POST", bearer: bearer) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let wire = beyGramPushDecode(BeyGramPushCreateWire.self, from: data) else {
                    completion(.failure(.decoding))
                    return
                }
                completion(.success(BeyGramPushRegistration(registrationId: wire.registrationId, state: wire.state, expiresAt: beyGramPushDate(wire.expiresAt), ingressUrl: wire.ingressUrl, setupUrl: wire.setupUrl)))
            }
        }
    }

    /// `GET /api/v1/push/registrations/{id}`: статус регистрации.
    public func pollRegistration(registrationId: String, bearer: String, completion: @escaping (Result<BeyGramPushRegistrationStatus, BeyGramPushError>) -> Void) {
        guard beyGramPushIsSafeSegment(registrationId) else {
            completion(.failure(.invalidRequest))
            return
        }
        self.perform(path: "api/v1/push/registrations/" + registrationId, method: "GET", bearer: bearer) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let wire = beyGramPushDecode(BeyGramPushStatusWire.self, from: data) else {
                    completion(.failure(.decoding))
                    return
                }
                completion(.success(BeyGramPushRegistrationStatus(state: wire.state, expiresAt: beyGramPushDate(wire.expiresAt), telegramKeys: wire.telegramKeys, telegramConfirmedAt: beyGramPushDate(wire.telegramConfirmedAt))))
            }
        }
    }

    /// `POST /api/v1/push/registrations/{id}/telegram-confirm`: клиент сообщает, что Telegram принял регистрацию.
    public func confirmTelegram(registrationId: String, bearer: String, completion: @escaping (Result<Void, BeyGramPushError>) -> Void) {
        guard beyGramPushIsSafeSegment(registrationId) else {
            completion(.failure(.invalidRequest))
            return
        }
        self.perform(path: "api/v1/push/registrations/" + registrationId + "/telegram-confirm", method: "POST", bearer: bearer) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                completion(.success(()))
            }
        }
    }

    /// `DELETE /api/v1/push/registrations/{id}`: отзывает регистрацию. Повторный вызов безопасен.
    public func deleteRegistration(registrationId: String, bearer: String, completion: @escaping (Result<Void, BeyGramPushError>) -> Void) {
        guard beyGramPushIsSafeSegment(registrationId) else {
            completion(.failure(.invalidRequest))
            return
        }
        self.perform(path: "api/v1/push/registrations/" + registrationId, method: "DELETE", bearer: bearer) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                completion(.success(()))
            }
        }
    }

    private func perform(path: String, method: String, bearer: String, completion: @escaping (Result<Data, BeyGramPushError>) -> Void) {
        var request = URLRequest(url: self.baseUrl.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
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

/// Состояние регистрации, которое можно хранить в UserDefaults. Секретов здесь нет: они в BeyGramPushSecrets (Keychain).
public struct BeyGramPushState: Codable, Equatable {
    public var registrationId: String
    public var state: BeyGramPushRegistrationState
    public var expiresAt: Date?
    public var telegramConfirmedAt: Date?

    public init(registrationId: String, state: BeyGramPushRegistrationState, expiresAt: Date?, telegramConfirmedAt: Date?) {
        self.registrationId = registrationId
        self.state = state
        self.expiresAt = expiresAt
        self.telegramConfirmedAt = telegramConfirmedAt
    }
}

/// Хранилище состояния BG Push поверх `UserDefaults`.
public final class BeyGramPushStore {
    public static let shared = BeyGramPushStore(defaults: UserDefaults.standard)

    private static let key = "beygram.push.state.v2"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Текущее состояние или nil, если регистрации нет.
    public func load() -> BeyGramPushState? {
        guard let data = self.defaults.data(forKey: BeyGramPushStore.key) else {
            return nil
        }
        return try? JSONDecoder().decode(BeyGramPushState.self, from: data)
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

/// Открытие чата из уведомления. Два формата, оба строятся PWA локально (issue #74, BG Push Navigation v2):
/// - v2: `beygram://push/open?v=2&account=<userId>&kind=user|chat|channel&rawPeer=<id>&msg=<id>`, rawPeer это сырой
///   облачный id в пространстве kind, а не упакованный PeerId;
/// - legacy: `beygram://push/open?account=<id>&peer=<packed PeerId>&msg=<id>`, как раньше.
/// Нативный клиент проверяет параметры сам. Неверная, неполная или неизвестная версия даёт обычное открытие приложения
/// (все поля nil), и никогда не читается как legacy. NOT CHECKED BY COMPILATION.
public struct BeyGramPushOpenRequest: Equatable {
    public enum Kind: String, Equatable {
        case user
        case chat
        case channel
    }

    /// Адресный переход v2: чат и, возможно, сообщение в облачном пространстве имён.
    public struct Target: Equatable {
        public let kind: Kind
        /// Сырой положительный Telegram id в пространстве kind. Не упакованный PeerId.
        public let rawPeerId: Int64
        public let messageId: Int32?
    }

    /// Telegram user id аккаунта, которому пришло уведомление. Nil, если параметра нет или ссылка недействительна.
    public let accountUserId: Int64?
    /// Legacy: упакованный iOS PeerId. Nil для v2.
    public let peerId: Int64?
    /// Legacy: id сообщения. Для v2 смотри `target`.
    public let messageId: Int32?
    /// v2: проверенная цель. Nil для legacy, bare и недействительных v2.
    public let target: Target?

    /// Nil для любой ссылки, кроме `beygram://push/open`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "beygram", url.host?.lowercased() == "push", url.path == "/open" else {
            return nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.contains(where: { $0.name == "v" }) {
            // Версия 2 или ничего: неизвестная версия не читается как legacy.
            if let target = BeyGramPushOpenRequest.parseV2(url: url, items: items) {
                self.accountUserId = target.account
                self.peerId = nil
                self.messageId = nil
                self.target = target.target
            } else {
                self.accountUserId = nil
                self.peerId = nil
                self.messageId = nil
                self.target = nil
            }
            return
        }
        func positiveValue(_ name: String) -> Int64? {
            guard let raw = items.first(where: { $0.name == name })?.value, let value = Int64(raw), value > 0 else {
                return nil
            }
            return value
        }
        self.accountUserId = positiveValue("account")
        self.peerId = positiveValue("peer")
        self.messageId = positiveValue("msg").flatMap({ Int32(exactly: $0) })
        self.target = nil
    }

    /// Каноническое положительное десятичное число: ASCII, без знака, пробелов и ведущих нулей.
    private static func canonicalPositive(_ raw: String) -> Int64? {
        guard !raw.isEmpty, raw.utf8.count <= 19, raw.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), raw.utf8.first != 0x30 else {
            return nil
        }
        return Int64(raw)
    }

    private static func parseV2(url: URL, items: [URLQueryItem]) -> (account: Int64, target: Target)? {
        let absolute = url.absoluteString
        guard absolute.utf8.count <= 200, absolute.utf8.allSatisfy({ $0 < 0x80 }), !absolute.contains("%"), !absolute.contains("#") else {
            return nil
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.user == nil, components.password == nil, components.port == nil, components.fragment == nil else {
            return nil
        }
        let allowed: Set<String> = ["v", "account", "kind", "rawPeer", "msg"]
        var values: [String: String] = [:]
        for item in items {
            guard allowed.contains(item.name), let value = item.value, values[item.name] == nil else {
                return nil
            }
            values[item.name] = value
        }
        guard values["v"] == "2", let accountRaw = values["account"], let account = canonicalPositive(accountRaw), let kindRaw = values["kind"], let kind = Kind(rawValue: kindRaw), let rawPeerRaw = values["rawPeer"], let rawPeer = canonicalPositive(rawPeerRaw) else {
            return nil
        }
        var messageId: Int32?
        if let msgRaw = values["msg"] {
            guard let msg = canonicalPositive(msgRaw), let exact = Int32(exactly: msg) else {
                return nil
            }
            messageId = exact
        }
        return (account, Target(kind: kind, rawPeerId: rawPeer, messageId: messageId))
    }
}
