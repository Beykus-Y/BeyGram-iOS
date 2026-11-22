import Foundation

/// Diversity of the personal radio, sent as an extra seed (as `YandexWave.Diversity` on Android).
public enum BGYandexWaveDiversity: Equatable {
    case standard
    case discover
    case popular

    /// The extra seed. Its format is not checked on the live service yet, as on Android: a wrong value only leaves the seed
    /// out of the request, and never breaks the radio.
    public var seed: String? {
        switch self {
        case .standard:
            return nil
        case .discover:
            return "settingDiversity:discover"
        case .popular:
            return "settingDiversity:popular"
        }
    }
}

/// Seeds of a radio. The personal wave is the one verified against the service's behaviour; the others are the Android
/// formats, and are not checked on the live service yet.
public enum BGYandexWaveSeed {
    public static let myWave = "user:onyourwave"

    public static func track(_ trackId: String) -> String {
        return "track:\(trackId)"
    }

    public static func artist(_ artistId: String) -> String {
        return "artist:\(artistId)"
    }

    public static func album(_ albumId: String) -> String {
        return "album:\(albumId)"
    }

    public static func playlist(ownerUid: String, kind: String) -> String {
        return "playlist:\(ownerUid)_\(kind)"
    }

    /// The seeds of a radio that starts from `base` with the chosen diversity.
    public static func seeds(base: String, diversity: BGYandexWaveDiversity) -> [String] {
        if let extra = diversity.seed {
            return [base, extra]
        }
        return [base]
    }
}

public enum BGYandexWaveEventType: String, Equatable {
    case radioStarted
    case trackStarted
    case trackFinished
    case skip
    case like
    case unlike
}

/// One listening event of a radio. `trackId` is the radio's `id:albumId` (or the bare id). `playedSeconds` is set for
/// finished and skipped tracks.
public struct BGYandexWaveEvent: Equatable {
    public let type: BGYandexWaveEventType
    public let timestampMs: Int64
    public let trackId: String?
    public let playedSeconds: Double?

    public init(type: BGYandexWaveEventType, timestampMs: Int64, trackId: String? = nil, playedSeconds: Double? = nil) {
        self.type = type
        self.timestampMs = timestampMs
        self.trackId = trackId
        self.playedSeconds = playedSeconds
    }

    /// The JSON object the feedback request carries (`YandexWaveEvent.toJson` on Android).
    func json() -> [String: Any] {
        var object: [String: Any] = [
            "type": type.rawValue,
            "timestamp": BGYandexWaveEvent.isoTimestamp(timestampMs),
        ]
        if let trackId = trackId {
            object["trackId"] = trackId
        }
        if let playedSeconds = playedSeconds {
            object["totalPlayedSeconds"] = playedSeconds
        }
        return object
    }

    /// ISO 8601 in UTC with milliseconds, such as `2024-01-01T12:00:00.000Z`.
    static func isoTimestamp(_ ms: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}

/// What a radio knows about one of its tracks: the `id:albumId` it names the track by, and the batch it came in.
public struct BGYandexRadioTrack: Equatable {
    public let queueId: String
    public let batchId: String?

    public init(queueId: String, batchId: String?) {
        self.queueId = queueId
        self.batchId = batchId
    }
}

/// One radio: the first batch, then the next ones on request. When the service forgets the session or ends it, a new session
/// with the same seeds continues from the tracks already given, so the queue never breaks (`YandexWaveSession` on Android).
/// Calls run one at a time, in order. Completions run on the main queue.
public final class BGYandexWaveSession {
    public let seeds: [String]
    private let service: BGYandexService
    /// The sign-in the radio started under. Its calls fail with `notSignedIn` once the account has changed.
    private let generation: Int
    private let operations = BGYandexSerialQueue()
    private let lock = NSLock()
    private var sessionId: String?
    /// Tracks given so far, as `id:albumId`, oldest first. Also used to drop repeats.
    private var given: [String] = []
    private var givenSet: Set<String> = []
    /// Radio identity of each queue row (by row key) that this radio gave.
    private var rows: [String: BGYandexRadioTrack] = [:]

    public init(service: BGYandexService, seeds: [String], initialGiven: [String] = []) {
        self.service = service
        self.seeds = seeds
        self.generation = service.currentGeneration()
        for id in initialGiven {
            if givenSet.insert(id).inserted {
                given.append(id)
            }
        }
    }

    /// The `id:albumId` session the feedback goes to. Nil before the radio starts, and after it ended.
    public var currentSessionId: String? {
        lock.lock()
        defer { lock.unlock() }
        return sessionId
    }

    /// The tracks given so far, as `id:albumId`, oldest first. Save them to continue the radio later.
    public func givenIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return given
    }

    /// Marks a track restored from a saved radio as given, so the radio does not repeat it, and gives its feedback a key.
    public func restore(track: BGYandexTrack) {
        lock.lock()
        defer { lock.unlock() }
        let queueId = BGYandexWaveSession.queueId(for: track)
        if givenSet.insert(queueId).inserted {
            given.append(queueId)
        }
        rows[track.rowKey] = BGYandexRadioTrack(queueId: queueId, batchId: nil)
    }

    /// The radio's identity of a queue row, or nil when this radio did not give that row.
    public func radioTrack(rowKey: String) -> BGYandexRadioTrack? {
        lock.lock()
        defer { lock.unlock() }
        return rows[rowKey]
    }

    /// Opens the radio: its first tracks. A radio-started event goes out with them.
    public func first(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        let report = bgYandexMain(completion)
        operations.run { done in
            self.service.startRadio(seeds: self.seeds, queue: [], generation: self.generation) { result in
                switch result {
                case let .failure(error):
                    done()
                    report(.failure(error))
                case let .success(batch):
                    self.setSessionId(batch.sessionId)
                    let fresh = self.accept(batch.tracks, batchId: batch.batchId)
                    self.enqueueFeedback(BGYandexWaveEvent(type: .radioStarted, timestampMs: BGYandexWaveSession.nowMs())) { _ in }
                    done()
                    report(.success(fresh))
                }
            }
        }
    }

    /// The next tracks for the player. An empty list means the service has nothing new right now: ask again later.
    /// A failure is passed on as it is; the caller keeps its queue and tries again after a pause.
    public func more(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        let report = bgYandexMain(completion)
        operations.run { done in
            self.fetchMore(attempt: 0) { result in
                done()
                report(result)
            }
        }
    }

    private func fetchMore(attempt: Int, completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        let state = requestState()
        let handle: (Result<BGYandexWaveBatch, BGYandexError>) -> Void = { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(batch):
                // A session the service forgot or ended is replaced by a new one, with the same seeds, on the next request.
                if batch.unknownSession || batch.terminated {
                    self.setSessionId(nil)
                } else {
                    self.setSessionId(batch.sessionId)
                }
                let fresh = self.accept(batch.tracks, batchId: batch.batchId)
                if !fresh.isEmpty {
                    completion(.success(fresh))
                } else if attempt + 1 < BGYandexConfig.maxEmptyWaveBatches {
                    self.fetchMore(attempt: attempt + 1, completion: completion)
                } else {
                    completion(.success([]))
                }
            }
        }
        if let current = state.sessionId {
            service.nextRadioBatch(sessionId: current, queue: state.given, generation: generation, completion: handle)
        } else {
            service.startRadio(seeds: seeds, queue: state.given, generation: generation, completion: handle)
        }
    }

    /// Sends one listening event of this radio. Events go out in order. An event before the radio has a session is dropped,
    /// as on Android, and reported as success.
    public func sendFeedback(_ event: BGYandexWaveEvent, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        enqueueFeedback(event, completion: bgYandexMain(completion))
    }

    /// The radio event for a listening fact about one of this radio's tracks. Nil when the track is not the radio's.
    public func feedbackEvent(for listen: BGYandexListenEvent) -> BGYandexWaveEvent? {
        guard let track = radioTrack(rowKey: listen.rowKey) else {
            return nil
        }
        let now = BGYandexWaveSession.nowMs()
        switch listen {
        case .started:
            return BGYandexWaveEvent(type: .trackStarted, timestampMs: now, trackId: track.queueId)
        case let .finished(_, playedSeconds):
            return BGYandexWaveEvent(type: .trackFinished, timestampMs: now, trackId: track.queueId, playedSeconds: playedSeconds)
        case let .skipped(_, playedSeconds):
            return BGYandexWaveEvent(type: .skip, timestampMs: now, trackId: track.queueId, playedSeconds: playedSeconds)
        }
    }

    /// The like or unlike event for a track of this radio, by its service id. Nil when this radio did not give the track.
    public func likeFeedback(trackId: String, liked: Bool) -> BGYandexWaveEvent? {
        guard let queueId = queueIdOf(trackId: trackId) else {
            return nil
        }
        return BGYandexWaveEvent(type: liked ? .like : .unlike, timestampMs: BGYandexWaveSession.nowMs(), trackId: queueId)
    }

    /// The `id:albumId` of a track, or the bare id when the track has no album.
    public static func queueId(for track: BGYandexTrack) -> String {
        if let albumId = track.albumId, !albumId.isEmpty {
            return "\(track.trackId):\(albumId)"
        }
        return track.trackId
    }

    // MARK: Internal state

    private func enqueueFeedback(_ event: BGYandexWaveEvent, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        operations.run { done in
            guard let current = self.currentSessionId else {
                done()
                completion(.success(()))
                return
            }
            let batchId = event.trackId.flatMap { self.batchOf(queueId: $0) }
            self.service.sendRadioFeedback(sessionId: current, event: event, batchId: batchId, generation: self.generation) { result in
                done()
                completion(result)
            }
        }
    }

    private func requestState() -> (sessionId: String?, given: [String]) {
        lock.lock()
        defer { lock.unlock() }
        return (sessionId, given)
    }

    private func setSessionId(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        sessionId = value
    }

    /// Keeps the tracks this radio has not given before, and remembers the batch each came in.
    private func accept(_ tracks: [BGYandexTrack], batchId: String?) -> [BGYandexTrack] {
        lock.lock()
        defer { lock.unlock() }
        var fresh: [BGYandexTrack] = []
        for track in tracks {
            let queueId = BGYandexWaveSession.queueId(for: track)
            if givenSet.insert(queueId).inserted {
                given.append(queueId)
                rows[track.rowKey] = BGYandexRadioTrack(queueId: queueId, batchId: batchId)
                fresh.append(track)
            }
        }
        return fresh
    }

    private func batchOf(queueId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return rows.values.first(where: { $0.queueId == queueId })?.batchId
    }

    private func queueIdOf(trackId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return rows.values.first(where: { $0.queueId == trackId || $0.queueId.hasPrefix(trackId + ":") })?.queueId
    }

    static func nowMs() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}
