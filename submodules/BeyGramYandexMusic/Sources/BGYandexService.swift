import Foundation

/// The Yandex source for the app: credentials, transport, token store, device sign-in, the session (refresh, sign-out and
/// sign-in generations), the API, lyrics and track files. Created only when the flag is on and the warning is accepted.
/// Nothing starts before that. Public completions and the account-state callback run on the main queue.
public final class BGYandexService {
    public let credentials: BGYandexCredentials
    public let tokenStore: BGYandexTokenStore
    public let client: BGYandexClient
    public let api: BGYandexAPI
    public let resolver: BGYandexTrackResolver
    private var authFlow: BGYandexAuthFlow?
    private let defaults: UserDefaults

    /// Called on the main queue after a sign-in, a sign-out, or a refused refresh token.
    public var onAccountStateChange: ((BGYandexAccountState) -> Void)?

    /// Guards `generation`, the refresh state and the lyrics cache. Never held while the network or a callback runs.
    private let lock = NSLock()
    /// Identifies the signed-in account. Bumped on sign-in, sign-out and a refused refresh token. A request that started
    /// under another value drops its result, so it never acts on, or publishes to, another account (as `YandexMusicProvider.kt`).
    private var generation = 0
    private var refreshing = false
    private var refreshWaiters: [(Result<BGYandexStoredTokens, BGYandexError>) -> Void] = []
    private var lyricsCache: [String: LyricsEntry] = [:]

    private struct LyricsEntry {
        let storedAt: TimeInterval
        var lastUsed: TimeInterval
        let result: Result<BGYandexLyrics, BGYandexError>
    }

    private static let deviceIdKey = "beygram.yandex.deviceId.v1"

    public init(credentials: BGYandexCredentials, cacheDirectory: URL, defaults: UserDefaults = .standard, transport: BGYandexTransport = BGYandexURLSessionTransport()) {
        self.credentials = credentials
        self.defaults = defaults
        self.tokenStore = BGYandexTokenStore()
        self.client = BGYandexClient(transport: transport)
        self.api = BGYandexAPI(client: client)
        self.resolver = BGYandexTrackResolver(cacheDirectory: cacheDirectory)
        self.resolver.linkProvider = { [weak self] trackId, completion in
            guard let service = self else {
                completion(.failure(.notSignedIn))
                return
            }
            service.audioLink(trackId: trackId, completion: completion)
        }
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

    /// The stored account, or signed out. Reads the Keychain, so do not call it for every frame.
    public var accountState: BGYandexAccountState {
        guard let stored = tokenStore.load() else {
            return .signedOut
        }
        return .signedIn(BGYandexAccount(uid: stored.uid ?? "", displayName: stored.displayName ?? "", hasPlus: stored.hasPlus ?? false))
    }

    /// Access token that is still valid for at least a minute, or nil. Calls to the service do not need it: they refresh
    /// the token themselves.
    public func validAccessToken() -> String? {
        guard let stored = tokenStore.load(), stored.expiresAt > Date().timeIntervalSince1970 + 60 else {
            return nil
        }
        return stored.accessToken
    }

    // MARK: Sign-in and sign-out

    public func startSignIn(events: @escaping (BGYandexAuthFlow.Event) -> Void) {
        // A sign-in still in progress is stopped first, so only one code is ever shown.
        cancelSignIn()
        let flow = BGYandexAuthFlow(client: client, credentials: credentials, deviceId: deviceId)
        authFlow = flow
        flow.start { [weak self] event in
            switch event {
            case let .finished(tokens):
                guard let service = self else {
                    DispatchQueue.main.async { events(.failed(.unknown)) }
                    return
                }
                service.completeSignIn(tokens, events: events)
            case .code, .failed:
                DispatchQueue.main.async { events(event) }
            }
        }
    }

    /// The device flow gave tokens: the account is read first, so the session carries its uid and subscription.
    private func completeSignIn(_ tokens: BGYandexStoredTokens, events: @escaping (BGYandexAuthFlow.Event) -> Void) {
        api.account(token: tokens.accessToken) { result in
            switch result {
            case let .failure(error):
                DispatchQueue.main.async { events(.failed(BGYandexService.failure(for: error))) }
            case let .success(account):
                let stored = BGYandexStoredTokens(
                    accessToken: tokens.accessToken,
                    refreshToken: tokens.refreshToken,
                    expiresAt: tokens.expiresAt,
                    uid: account.uid,
                    displayName: account.displayName,
                    hasPlus: account.hasPlus
                )
                guard self.commitSignIn(stored) else {
                    DispatchQueue.main.async { events(.failed(.unknown)) }
                    return
                }
                self.publishAccountState()
                DispatchQueue.main.async { events(.finished(stored)) }
            }
        }
    }

    public func cancelSignIn() {
        authFlow?.cancel()
        authFlow = nil
    }

    /// Deletes the token and every cached track, forgets the lyrics, and stops a sign-in in progress.
    /// Requests still in flight drop their results.
    public func signOut() {
        cancelSignIn()
        clearSession()
        publishAccountState()
    }

    static func failure(for error: BGYandexError) -> BGYandexFailure {
        switch error {
        case .network:
            return .network
        case .sessionExpired, .notSignedIn:
            return .sessionExpired
        default:
            return .unknown
        }
    }

    // MARK: Session state (generations, refresh, sign-out)

    /// Current sign-in generation. A radio binds its calls to the generation it started under.
    func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// Saves a new session and moves to a new generation. False when the Keychain refused the save.
    private func commitSignIn(_ tokens: BGYandexStoredTokens) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard tokenStore.save(tokens) else {
            return false
        }
        generation += 1
        lyricsCache = [:]
        return true
    }

    /// Saves tokens only while the session is still the one of generation `gen`.
    private func saveIfCurrent(_ tokens: BGYandexStoredTokens, generation gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == gen else {
            return false
        }
        return tokenStore.save(tokens)
    }

    /// Removes the stored session and the cached tracks. The generation moves first, so a request still in flight
    /// finds that its account is gone.
    private func clearSession() {
        lock.lock()
        generation += 1
        lyricsCache = [:]
        tokenStore.delete()
        lock.unlock()
        resolver.clearAll()
    }

    /// As `clearSession`, but only while the session is still the one of generation `gen`. True when it cleared.
    private func clearSessionIfCurrent(_ gen: Int) -> Bool {
        lock.lock()
        guard generation == gen else {
            lock.unlock()
            return false
        }
        generation += 1
        lyricsCache = [:]
        tokenStore.delete()
        lock.unlock()
        resolver.clearAll()
        publishAccountState()
        return true
    }

    private func publishAccountState() {
        let state = accountState
        DispatchQueue.main.async {
            self.onAccountStateChange?(state)
        }
    }

    /// Runs one request with a valid token of the stored session. The token is refreshed first when it is about to expire,
    /// and once more when the service refuses it (401). `expecting` binds the call to one sign-in: when the account has
    /// changed, the call fails with `notSignedIn` before any request. The completion runs on a background queue.
    func withToken<T>(_ work: @escaping (BGYandexStoredTokens, Int, @escaping (Result<T, BGYandexError>) -> Void) -> Void,
                      expecting expected: Int? = nil,
                      completion: @escaping (Result<T, BGYandexError>) -> Void) {
        let gen = currentGeneration()
        if let expected = expected, expected != gen {
            completion(.failure(.notSignedIn))
            return
        }
        guard let stored = tokenStore.load() else {
            completion(.failure(.notSignedIn))
            return
        }
        freshSession(stored, generation: gen, refreshed: false) { fresh in
            switch fresh {
            case let .failure(error):
                completion(.failure(error))
            case let .success(session):
                work(session, gen) { first in
                    if case .failure(.sessionExpired) = first, session.refreshToken != nil {
                        self.refreshNow(session, generation: gen) { refreshed in
                            switch refreshed {
                            case let .failure(error):
                                completion(.failure(error))
                            case let .success(renewed):
                                work(renewed, gen) { second in
                                    self.settle(second, generation: gen, completion: completion)
                                }
                            }
                        }
                    } else {
                        self.settle(first, generation: gen, completion: completion)
                    }
                }
            }
        }
    }

    /// A result of the account it started under. A token refused even after a refresh ends the session.
    private func settle<T>(_ result: Result<T, BGYandexError>, generation gen: Int, completion: @escaping (Result<T, BGYandexError>) -> Void) {
        if case .failure(.sessionExpired) = result {
            let error: BGYandexError = clearSessionIfCurrent(gen) ? .sessionExpired : .notSignedIn
            completion(.failure(error))
            return
        }
        completion(currentGeneration() == gen ? result : .failure(.notSignedIn))
    }

    /// The stored session, refreshed when it is about to expire. Tokens saved by an earlier build carry no account:
    /// the account is read once and kept.
    private func freshSession(_ stored: BGYandexStoredTokens, generation gen: Int, refreshed: Bool,
                              completion: @escaping (Result<BGYandexStoredTokens, BGYandexError>) -> Void) {
        let remaining = stored.expiresAt - Date().timeIntervalSince1970
        if !refreshed, stored.refreshToken != nil, remaining <= BGYandexConfig.refreshMargin {
            refreshNow(stored, generation: gen) { result in
                switch result {
                case let .failure(error):
                    completion(.failure(error))
                case let .success(renewed):
                    self.freshSession(renewed, generation: gen, refreshed: true, completion: completion)
                }
            }
            return
        }
        if stored.uid != nil {
            completion(.success(stored))
            return
        }
        api.account(token: stored.accessToken) { result in
            switch result {
            case let .failure(error):
                guard case .sessionExpired = error else {
                    completion(.failure(error))
                    return
                }
                // The service refuses the token: one refresh, as in `withToken`. A token refused after that ends the session.
                if !refreshed, stored.refreshToken != nil {
                    self.refreshNow(stored, generation: gen) { refreshedResult in
                        switch refreshedResult {
                        case let .failure(refreshError):
                            completion(.failure(refreshError))
                        case let .success(renewed):
                            self.freshSession(renewed, generation: gen, refreshed: true, completion: completion)
                        }
                    }
                } else {
                    let ended: BGYandexError = self.clearSessionIfCurrent(gen) ? .sessionExpired : .notSignedIn
                    completion(.failure(ended))
                }
            case let .success(account):
                let updated = BGYandexStoredTokens(
                    accessToken: stored.accessToken,
                    refreshToken: stored.refreshToken,
                    expiresAt: stored.expiresAt,
                    uid: account.uid,
                    displayName: account.displayName,
                    hasPlus: account.hasPlus
                )
                if self.saveIfCurrent(updated, generation: gen) {
                    completion(.success(updated))
                } else {
                    completion(.failure(.notSignedIn))
                }
            }
        }
    }

    /// Refreshes the access token once for all callers: a refresh already in flight answers them too, and a stored token
    /// that is already newer is used as it is. A refused refresh token ends the session.
    private func refreshNow(_ stored: BGYandexStoredTokens, generation gen: Int,
                            completion: @escaping (Result<BGYandexStoredTokens, BGYandexError>) -> Void) {
        lock.lock()
        if generation != gen {
            lock.unlock()
            completion(.failure(.notSignedIn))
            return
        }
        if refreshing {
            refreshWaiters.append(completion)
            lock.unlock()
            return
        }
        if let latest = tokenStore.load(), latest.accessToken != stored.accessToken {
            lock.unlock()
            completion(.success(latest))
            return
        }
        guard let refreshToken = stored.refreshToken else {
            lock.unlock()
            completion(.failure(.sessionExpired))
            return
        }
        refreshing = true
        refreshWaiters = [completion]
        lock.unlock()
        client.sendRaw(BGYandexOAuth.refreshRequest(refreshToken: refreshToken, credentials: credentials), token: nil, paced: true) { response in
            self.finishRefresh(response, previous: stored, generation: gen)
        }
    }

    private func finishRefresh(_ response: BGYandexHTTPResponse?, previous: BGYandexStoredTokens, generation gen: Int) {
        let outcome: Result<BGYandexStoredTokens, BGYandexError>
        if let response = response, (200...299).contains(response.statusCode) {
            if let parsed = BGYandexOAuth.parseRefresh(response.body) {
                let updated = BGYandexStoredTokens(
                    accessToken: parsed.accessToken,
                    refreshToken: parsed.refreshToken ?? previous.refreshToken,
                    expiresAt: Date().timeIntervalSince1970 + Double(parsed.expiresIn),
                    uid: previous.uid,
                    displayName: previous.displayName,
                    hasPlus: previous.hasPlus
                )
                if saveIfCurrent(updated, generation: gen) {
                    outcome = .success(updated)
                } else {
                    outcome = .failure(.notSignedIn)
                }
            } else {
                outcome = .failure(.serviceChanged)
            }
        } else if let response = response, (400...403).contains(response.statusCode) {
            // The refresh token is refused: the account has to sign in again.
            _ = clearSessionIfCurrent(gen)
            outcome = .failure(.sessionExpired)
        } else {
            outcome = .failure(BGYandexClient.error(for: response))
        }
        lock.lock()
        refreshing = false
        let waiters = refreshWaiters
        refreshWaiters = []
        lock.unlock()
        for waiter in waiters {
            waiter(outcome)
        }
    }

    /// Reloads uid, name and subscription from the service and keeps them with the session.
    public func refreshAccount(completion: @escaping (Result<BGYandexAccount, BGYandexError>) -> Void) {
        withToken({ stored, gen, done in
            self.api.account(token: stored.accessToken) { result in
                switch result {
                case let .failure(error):
                    done(.failure(error))
                case let .success(account):
                    let updated = BGYandexStoredTokens(
                        accessToken: stored.accessToken,
                        refreshToken: stored.refreshToken,
                        expiresAt: stored.expiresAt,
                        uid: account.uid,
                        displayName: account.displayName,
                        hasPlus: account.hasPlus
                    )
                    if self.saveIfCurrent(updated, generation: gen) {
                        done(.success(account))
                    } else {
                        done(.failure(.notSignedIn))
                    }
                }
            }
        }, completion: bgYandexMain(completion))
    }

    // MARK: Library and search

    public func search(text: String, limit: Int, completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            self.api.search(token: stored.accessToken, text: text, limit: limit, completion: done)
        }, completion: bgYandexMain(completion))
    }

    /// Liked tracks, newest first, with `liked` set.
    public func likedTracks(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.likedTrackIds(token: stored.accessToken, uid: uid) { idResult in
                switch idResult {
                case let .failure(error):
                    done(.failure(error))
                case let .success(ids):
                    self.api.tracks(token: stored.accessToken, ids: ids) { trackResult in
                        switch trackResult {
                        case let .failure(error):
                            done(.failure(error))
                        case let .success(tracks):
                            done(.success(tracks.map { $0.with(liked: true) }))
                        }
                    }
                }
            }
        }, completion: bgYandexMain(completion))
    }

    public func likedTrackIds(completion: @escaping (Result<[String], BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.likedTrackIds(token: stored.accessToken, uid: uid, completion: done)
        }, completion: bgYandexMain(completion))
    }

    /// Tracks by id, in the order given.
    public func tracks(ids: [String], completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        if ids.isEmpty {
            DispatchQueue.main.async { completion(.success([])) }
            return
        }
        withToken({ stored, _, done in
            self.api.tracks(token: stored.accessToken, ids: ids, completion: done)
        }, completion: bgYandexMain(completion))
    }

    public func setLiked(trackId: String, liked: Bool, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.setLiked(token: stored.accessToken, uid: uid, trackId: trackId, liked: liked, completion: done)
        }, completion: bgYandexMain(completion))
    }

    /// Dislikes a track so the radio stops giving it, or undoes that. See `BGYandexAPI.setDisliked` on its status.
    public func setDisliked(trackId: String, disliked: Bool, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.setDisliked(token: stored.accessToken, uid: uid, trackId: trackId, disliked: disliked, completion: done)
        }, completion: bgYandexMain(completion))
    }

    /// Playlists the account owns.
    public func playlists(completion: @escaping (Result<[BGYandexPlaylist], BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.playlists(token: stored.accessToken, uid: uid, completion: done)
        }, completion: bgYandexMain(completion))
    }

    /// Playlists of other users the account follows.
    public func likedPlaylists(completion: @escaping (Result<[BGYandexPlaylist], BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.likedPlaylists(token: stored.accessToken, uid: uid, completion: done)
        }, completion: bgYandexMain(completion))
    }

    /// Tracks of one playlist. `ownerUid` nil means the account's own playlist.
    public func playlistTracks(kind: String, ownerUid: String?, completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.playlistTracks(token: stored.accessToken, ownerUid: ownerUid ?? uid, kind: kind, completion: done)
        }, completion: bgYandexMain(completion))
    }

    /// The playlist with this uuid, when the account owns it or follows it. A playlist the account does not follow is
    /// `notFound`: the caller opens it in the browser instead. A failed list is reported when the other one does not match.
    public func playlistByUuid(_ uuid: String, completion: @escaping (Result<BGYandexPlaylist, BGYandexError>) -> Void) {
        let wanted = uuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.playlists(token: stored.accessToken, uid: uid) { ownResult in
                if case let .success(own) = ownResult, let found = own.first(where: { $0.matchesUuid(wanted) }) {
                    done(.success(found))
                    return
                }
                self.api.likedPlaylists(token: stored.accessToken, uid: uid) { likedResult in
                    switch likedResult {
                    case let .success(liked):
                        if let found = liked.first(where: { $0.matchesUuid(wanted) }) {
                            done(.success(found))
                        } else if case let .failure(error) = ownResult {
                            done(.failure(error))
                        } else {
                            done(.failure(.notFound))
                        }
                    case let .failure(error):
                        done(.failure(error))
                    }
                }
            }
        }, completion: bgYandexMain(completion))
    }

    public func likedAlbums(completion: @escaping (Result<[BGYandexAlbum], BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard let uid = stored.uid else {
                done(.failure(.notSignedIn))
                return
            }
            self.api.likedAlbums(token: stored.accessToken, uid: uid, completion: done)
        }, completion: bgYandexMain(completion))
    }

    public func album(albumId: String, completion: @escaping (Result<BGYandexAlbumTracks, BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            self.api.album(token: stored.accessToken, albumId: albumId, completion: done)
        }, completion: bgYandexMain(completion))
    }

    // MARK: Lyrics

    /// Lyrics of a track. A found text is kept for `BGYandexConfig.lyricsFoundTTL`, a failure for `lyricsFailedTTL`.
    /// The cache is emptied on every sign-in change.
    public func lyrics(trackId: String, completion: @escaping (Result<BGYandexLyrics, BGYandexError>) -> Void) {
        let gen = currentGeneration()
        let key = "\(gen):\(trackId)"
        if let cached = cachedLyrics(key) {
            bgYandexMain(completion)(cached)
            return
        }
        withToken({ stored, _, done in
            self.api.lyrics(token: stored.accessToken, trackId: trackId, completion: done)
        }, expecting: gen, completion: { (result: Result<BGYandexLyrics, BGYandexError>) in
            self.storeLyrics(result, key: key, generation: gen)
            bgYandexMain(completion)(result)
        })
    }

    private func cachedLyrics(_ key: String) -> Result<BGYandexLyrics, BGYandexError>? {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        guard var entry = lyricsCache[key] else {
            return nil
        }
        if now - entry.storedAt >= BGYandexService.lyricsTTL(entry.result) {
            lyricsCache[key] = nil
            return nil
        }
        entry.lastUsed = now
        lyricsCache[key] = entry
        return entry.result
    }

    private func storeLyrics(_ result: Result<BGYandexLyrics, BGYandexError>, key: String, generation gen: Int) {
        guard BGYandexService.isCacheable(result) else {
            return
        }
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        guard generation == gen else {
            return
        }
        lyricsCache = lyricsCache.filter { now - $0.value.storedAt < BGYandexService.lyricsTTL($0.value.result) }
        lyricsCache[key] = LyricsEntry(storedAt: now, lastUsed: now, result: result)
        while lyricsCache.count > BGYandexConfig.lyricsCacheLimit {
            guard let oldest = lyricsCache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else {
                break
            }
            lyricsCache[oldest] = nil
        }
    }

    static func lyricsTTL(_ result: Result<BGYandexLyrics, BGYandexError>) -> TimeInterval {
        if case .success = result {
            return BGYandexConfig.lyricsFoundTTL
        }
        return BGYandexConfig.lyricsFailedTTL
    }

    /// A failure about the track is kept; one about the session or the network is not (as `YandexMusicProvider.kt`).
    static func isCacheable(_ result: Result<BGYandexLyrics, BGYandexError>) -> Bool {
        switch result {
        case .success:
            return true
        case let .failure(error):
            return error == .notFound || error == .serviceChanged || error == .unknown
        }
    }

    // MARK: Audio

    /// A temporary direct link to a full track. Fails with `subscriptionRequired` without a subscription, so a preview is
    /// never played as a full track. Do not store the link.
    public func audio(trackId: String, completion: @escaping (Result<BGYandexAudio, BGYandexError>) -> Void) {
        audioLink(trackId: trackId, completion: bgYandexMain(completion))
    }

    /// The link for the track resolver. Not on the main queue.
    func audioLink(trackId: String, completion: @escaping (Result<BGYandexAudio, BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard stored.hasPlus == true else {
                done(.failure(.subscriptionRequired))
                return
            }
            self.api.audioLink(token: stored.accessToken, trackId: trackId, completion: done)
        }, completion: completion)
    }

    /// Local MP3 of a track: the cached copy, or a download with a fresh link. Completes on the main queue.
    public func localFile(trackId: String, completion: @escaping (Result<URL, BGYandexError>) -> Void) {
        resolver.localFile(trackId: trackId, completion: completion)
    }

    // MARK: Radio

    /// A radio («Моя волна» or another seed set). Start it with `first`; it belongs to the sign-in it starts under.
    public func makeWave(seeds: [String]) -> BGYandexWaveSession {
        return BGYandexWaveSession(service: self, seeds: seeds)
    }

    func startRadio(seeds: [String], queue: [String], generation gen: Int, completion: @escaping (Result<BGYandexWaveBatch, BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            guard stored.hasPlus == true else {
                done(.failure(.subscriptionRequired))
                return
            }
            self.api.waveStart(token: stored.accessToken, seeds: seeds, queue: queue, completion: done)
        }, expecting: gen, completion: completion)
    }

    func nextRadioBatch(sessionId: String, queue: [String], generation gen: Int, completion: @escaping (Result<BGYandexWaveBatch, BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            self.api.waveNext(token: stored.accessToken, sessionId: sessionId, queue: queue, completion: done)
        }, expecting: gen, completion: completion)
    }

    func sendRadioFeedback(sessionId: String, event: BGYandexWaveEvent, batchId: String?, generation gen: Int,
                           completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        withToken({ stored, _, done in
            self.api.waveFeedback(token: stored.accessToken, sessionId: sessionId, event: event, batchId: batchId, completion: done)
        }, expecting: gen, completion: completion)
    }
}

/// The refresh request and answer of the OAuth token endpoint (as `YandexAuth.refresh` on Android).
enum BGYandexOAuth {
    struct Refreshed: Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
    }

    static func refreshRequest(refreshToken: String, credentials: BGYandexCredentials) -> URLRequest {
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

    static func parseRefresh(_ body: Data) -> Refreshed? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let access = json["access_token"] as? String, !access.isEmpty else {
            return nil
        }
        let refresh = (json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let expires = (json["expires_in"] as? Int) ?? BGYandexDeviceFlow.defaultTokenLifetime
        return Refreshed(accessToken: access, refreshToken: refresh, expiresIn: expires)
    }
}
