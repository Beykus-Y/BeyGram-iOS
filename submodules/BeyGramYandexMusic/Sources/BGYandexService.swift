import Foundation

/// The Yandex source for the app: credentials, transport, token store, device sign-in, API, and track files.
/// Created only when the flag is on and the warning is accepted. Nothing starts before that.
public final class BGYandexService {
    public let credentials: BGYandexCredentials
    public let tokenStore: BGYandexTokenStore
    public let client: BGYandexClient
    public let api: BGYandexAPI
    public let resolver: BGYandexTrackResolver
    private var authFlow: BGYandexAuthFlow?
    /// Guards the refresh state and `sessionGeneration`. Sign-in and sign-out bump the generation, so an answer to a
    /// refresh that started before them is dropped instead of being written to the store.
    private let refreshLock = NSLock()
    private var refreshWaiters: [(AccessResult) -> Void] = []
    private var refreshInFlight = false
    private var sessionGeneration = 0
    private let defaults: UserDefaults

    private static let deviceIdKey = "beygram.yandex.deviceId.v1"
    /// Refresh starts this long before the access token expires, as on Android (`REFRESH_MARGIN_MS`).
    private static let refreshMargin: TimeInterval = 5 * 60

    public init(credentials: BGYandexCredentials, cacheDirectory: URL, defaults: UserDefaults = .standard, transport: BGYandexTransport = BGYandexURLSessionTransport()) {
        self.credentials = credentials
        self.defaults = defaults
        self.tokenStore = BGYandexTokenStore()
        self.client = BGYandexClient(transport: transport)
        self.api = BGYandexAPI(client: client)
        self.resolver = BGYandexTrackResolver(api: api, cacheDirectory: cacheDirectory)
    }

    /// Device id sent during sign-in. Random once per install, kept in UserDefaults; it is not a secret.
    public var deviceId: String {
        if let existing = defaults.string(forKey: BGYandexService.deviceIdKey) {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: BGYandexService.deviceIdKey)
        return fresh
    }

    public var isSignedIn: Bool {
        return tokenStore.load() != nil
    }

    /// What `accessToken(completion:)` hands back.
    public enum AccessResult: Equatable {
        case token(String)
        /// The session is over: there is no refresh token, or the service refused it. The user signs in again.
        case signInRequired
        /// The refresh failed for now (no network, a server error). The stored tokens stay.
        case unavailable
    }

    /// An access token that is valid for at least five more minutes. A stored token about to expire is refreshed first.
    /// The completion runs on the caller's thread when the stored token is fresh, and on the client queue otherwise.
    /// Callers that arrive during a refresh wait for it: the service may rotate the refresh token, so it is used one
    /// request at a time.
    public func accessToken(completion: @escaping (AccessResult) -> Void) {
        if let stored = tokenStore.load(), stored.expiresAt > Date().timeIntervalSince1970 + BGYandexService.refreshMargin {
            completion(.token(stored.accessToken))
            return
        }
        refreshLock.lock()
        refreshWaiters.append(completion)
        let starts = !refreshInFlight
        refreshInFlight = true
        refreshLock.unlock()
        guard starts else {
            return
        }
        refreshNow { result in
            self.refreshLock.lock()
            let waiters = self.refreshWaiters
            self.refreshWaiters = []
            self.refreshInFlight = false
            self.refreshLock.unlock()
            for waiter in waiters {
                waiter(result)
            }
        }
    }

    /// One refresh with the stored refresh token. The answer is written to the store under the lock, unless a sign-in or
    /// sign-out started meanwhile: that one owns the store now.
    private func refreshNow(completion: @escaping (AccessResult) -> Void) {
        refreshLock.lock()
        let generation = sessionGeneration
        refreshLock.unlock()
        guard let stored = tokenStore.load(), let refreshToken = stored.refreshToken, !refreshToken.isEmpty else {
            completion(.signInRequired)
            return
        }
        client.sendRaw(BGYandexTokenRefresh.request(refreshToken: refreshToken, credentials: credentials), token: nil, paced: true) { [weak self] response in
            guard let self = self else {
                completion(.unavailable)
                return
            }
            let outcome = BGYandexTokenRefresh.outcome(statusCode: response?.statusCode, body: response?.body)
            self.refreshLock.lock()
            let sameSession = self.sessionGeneration == generation
            let result: AccessResult
            switch outcome {
            case let .tokens(tokens):
                if sameSession {
                    // The service may omit a new refresh token. The old one stays valid, as on Android.
                    self.tokenStore.save(BGYandexStoredTokens(
                        accessToken: tokens.accessToken,
                        refreshToken: tokens.refreshToken ?? refreshToken,
                        expiresAt: Date().timeIntervalSince1970 + Double(tokens.expiresIn)
                    ))
                    result = .token(tokens.accessToken)
                } else {
                    result = .signInRequired
                }
            case .sessionExpired:
                // A refused refresh token ends the session, as on Android (`store.clear()`).
                if sameSession {
                    self.tokenStore.delete()
                }
                result = .signInRequired
            case .unavailable:
                result = .unavailable
            }
            self.refreshLock.unlock()
            completion(result)
        }
    }

    public func startSignIn(events: @escaping (BGYandexAuthFlow.Event) -> Void) {
        refreshLock.lock()
        sessionGeneration += 1
        refreshLock.unlock()
        let flow = BGYandexAuthFlow(client: client, credentials: credentials, deviceId: deviceId)
        authFlow = flow
        flow.start { [weak self] event in
            if case let .finished(tokens) = event {
                self?.tokenStore.save(tokens)
            }
            events(event)
        }
    }

    public func cancelSignIn() {
        authFlow?.cancel()
        authFlow = nil
    }

    /// Deletes the token and every cached track.
    public func signOut() {
        refreshLock.lock()
        sessionGeneration += 1
        refreshLock.unlock()
        cancelSignIn()
        tokenStore.delete()
        resolver.clearAll()
    }
}
