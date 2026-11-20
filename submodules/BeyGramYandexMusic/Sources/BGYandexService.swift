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
    private let defaults: UserDefaults

    private static let deviceIdKey = "beygram.yandex.deviceId.v1"

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

    /// Access token that is still valid for at least a minute. Refresh with the refresh token is not implemented yet,
    /// so an expired token means the user signs in again.
    public func validAccessToken() -> String? {
        guard let stored = tokenStore.load(), stored.expiresAt > Date().timeIntervalSince1970 + 60 else {
            return nil
        }
        return stored.accessToken
    }

    public func startSignIn(events: @escaping (BGYandexAuthFlow.Event) -> Void) {
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
        cancelSignIn()
        tokenStore.delete()
        resolver.clearAll()
    }
}
