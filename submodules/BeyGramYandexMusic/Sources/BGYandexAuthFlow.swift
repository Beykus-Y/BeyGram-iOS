import Foundation

/// Device sign-in: asks for a code, shows it to the user, then polls the token endpoint at the interval the
/// service gives (RFC 8628). It stops on success, on a refusal, or when the code expires. Never asks for a password.
public final class BGYandexAuthFlow {
    public enum Event: Equatable {
        case code(BGYandexDeviceCode)
        case finished(BGYandexStoredTokens)
        case failed(BGYandexFailure)
    }

    private let client: BGYandexClient
    private let credentials: BGYandexCredentials
    private let deviceId: String
    private let now: () -> TimeInterval
    private var cancelled = false

    public init(client: BGYandexClient, credentials: BGYandexCredentials, deviceId: String, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.client = client
        self.credentials = credentials
        self.deviceId = deviceId
        self.now = now
    }

    public func cancel() {
        cancelled = true
    }

    public func start(events: @escaping (Event) -> Void) {
        client.sendRaw(BGYandexDeviceFlow.deviceCodeRequest(deviceId: deviceId, credentials: credentials), token: nil, paced: true) { [weak self] response in
            guard let self = self, !self.cancelled else {
                return
            }
            guard let response = response, (200...299).contains(response.statusCode),
                  let code = BGYandexDeviceFlow.parseDeviceCode(response.body) else {
                events(.failed(.network))
                return
            }
            events(.code(code))
            self.poll(deviceCode: code.deviceCode, interval: Double(code.interval), deadline: self.now() + Double(code.expiresIn), events: events)
        }
    }

    private func poll(deviceCode: String, interval: Double, deadline: TimeInterval, events: @escaping (Event) -> Void) {
        if cancelled {
            return
        }
        if now() >= deadline {
            events(.failed(.sessionExpired))
            return
        }
        client.sendRaw(BGYandexDeviceFlow.tokenPollRequest(deviceCode: deviceCode, credentials: credentials), token: nil, paced: true) { [weak self] response in
            guard let self = self, !self.cancelled else {
                return
            }
            switch BGYandexDeviceFlow.pollOutcome(statusCode: response?.statusCode, body: response?.body) {
            case let .tokens(tokens):
                let stored = BGYandexStoredTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, expiresAt: self.now() + Double(tokens.expiresIn))
                events(.finished(stored))
            case let .failed(reason):
                events(.failed(reason))
            case .pending:
                self.schedule(deviceCode: deviceCode, interval: interval, deadline: deadline, events: events)
            case .slowDown:
                self.schedule(deviceCode: deviceCode, interval: interval + 5, deadline: deadline, events: events)
            }
        }
    }

    private func schedule(deviceCode: String, interval: Double, deadline: TimeInterval, events: @escaping (Event) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.poll(deviceCode: deviceCode, interval: interval, deadline: deadline, events: events)
        }
    }
}
