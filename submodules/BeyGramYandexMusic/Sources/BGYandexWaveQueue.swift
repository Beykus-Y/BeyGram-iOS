import Foundation

/// What the wave queue needs from a radio. `BGYandexWaveSession` is the real one; tests give their own.
public protocol BGYandexWaveSource: AnyObject {
    func first(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void)
    func more(completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void)
    func feedbackEvent(for listen: BGYandexListenEvent) -> BGYandexWaveEvent?
    func likeFeedback(trackId: String, liked: Bool) -> BGYandexWaveEvent?
    func sendFeedback(_ event: BGYandexWaveEvent, completion: @escaping (Result<Void, BGYandexError>) -> Void)
}

extension BGYandexWaveSession: BGYandexWaveSource {}

/// The personal radio as a player sees it: a queue that stays a few tracks ahead of the player, the next file downloaded before
/// its turn, and the listening events the radio learns from. It does not know the player. The player takes `takeNext()` and
/// reports what it heard. Call it from the main queue, where the radio's completions arrive.
public final class BGYandexWaveQueue {
    /// The queue asks the radio for more once it holds this many tracks or fewer.
    public static let refillBelow = 3
    /// After a failed or empty refill, the radio is not asked again for this long.
    public static let retryDelay: TimeInterval = 30

    private let source: BGYandexWaveSource
    private let prepare: (BGYandexTrack) -> Void
    private let now: () -> Date
    private var upcoming: [BGYandexTrack] = []
    private var started = false
    private var refilling = false
    private var retryAt: Date?
    private var preparedRowKey: String?
    /// Bumped by `stop()`, so a radio answer that arrives after it is dropped.
    private var generation = 0

    /// `prepare` starts the download of a track's file ahead of time. Its result is not needed here.
    public init(source: BGYandexWaveSource,
                prepare: @escaping (BGYandexTrack) -> Void,
                now: @escaping () -> Date = { Date() }) {
        self.source = source
        self.prepare = prepare
        self.now = now
    }

    /// The tracks waiting behind the player, next first.
    public var upcomingTracks: [BGYandexTrack] {
        return upcoming
    }

    /// Opens the radio. Completes with its first track, or with nil when the radio has nothing yet.
    public func start(completion: @escaping (Result<BGYandexTrack?, BGYandexError>) -> Void) {
        let current = generation
        source.first { [weak self] result in
            guard let self = self else {
                return
            }
            guard current == self.generation else {
                completion(.success(nil))
                return
            }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(tracks):
                self.started = true
                self.upcoming = tracks
                self.prepareNext()
                self.refillIfShort()
                completion(.success(self.upcoming.first))
            }
        }
    }

    /// The track the player plays now: the head of the queue, which leaves it. Nil while the radio has nothing ready.
    /// The queue refills when it runs short, and starts the file of the track after this one.
    public func takeNext() -> BGYandexTrack? {
        guard !upcoming.isEmpty else {
            refillIfShort()
            return nil
        }
        let track = upcoming.removeFirst()
        prepareNext()
        refillIfShort()
        return track
    }

    /// The player started a track of this radio.
    public func trackStarted(rowKey: String) {
        report(.started(rowKey: rowKey))
    }

    /// The player played a track of this radio to its end.
    public func trackFinished(rowKey: String, playedSeconds: Double) {
        report(.finished(rowKey: rowKey, playedSeconds: playedSeconds))
    }

    /// The listener skipped a track of this radio before its end.
    public func trackSkipped(rowKey: String, playedSeconds: Double) {
        report(.skipped(rowKey: rowKey, playedSeconds: playedSeconds))
    }

    /// Likes or unlikes a track of this radio as a radio event. Nil-safe: a track that is not the radio's gives no event.
    /// The account's own like is set by the screens through the service.
    public func setLiked(trackId: String, liked: Bool) {
        guard let event = source.likeFeedback(trackId: trackId, liked: liked) else {
            return
        }
        source.sendFeedback(event) { _ in }
    }

    /// Stops the radio here: the queue is cleared, nothing more is asked for, and a radio answer still on its way is dropped.
    /// The radio keeps the ids it gave, so a saved radio can continue later.
    public func stop() {
        generation += 1
        started = false
        refilling = false
        retryAt = nil
        preparedRowKey = nil
        upcoming = []
    }

    private func refillIfShort() {
        guard started, !refilling, upcoming.count <= BGYandexWaveQueue.refillBelow else {
            return
        }
        if let retryAt = retryAt, now() < retryAt {
            return
        }
        refilling = true
        let current = generation
        source.more { [weak self] result in
            guard let self = self, current == self.generation else {
                return
            }
            self.refilling = false
            switch result {
            case let .success(tracks) where !tracks.isEmpty:
                self.retryAt = nil
                self.upcoming.append(contentsOf: tracks)
                self.prepareNext()
            case .success:
                // The radio has nothing new right now. The session has already retried its own empty batches.
                self.retryAt = self.now().addingTimeInterval(BGYandexWaveQueue.retryDelay)
            case .failure:
                self.retryAt = self.now().addingTimeInterval(BGYandexWaveQueue.retryDelay)
            }
        }
    }

    /// Starts the file of the next track, once per track.
    private func prepareNext() {
        guard let next = upcoming.first, next.rowKey != preparedRowKey else {
            return
        }
        preparedRowKey = next.rowKey
        prepare(next)
    }

    private func report(_ listen: BGYandexListenEvent) {
        guard let event = source.feedbackEvent(for: listen) else {
            return
        }
        // Feedback is best effort: a send that fails does not change the queue.
        source.sendFeedback(event) { _ in }
    }
}
