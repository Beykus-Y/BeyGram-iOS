import Foundation

/// Immutable snapshot of the active "My Wave" radio playback session.
public struct BGYandexWaveState: Equatable {
    public let currentTrack: BGYandexTrack?
    public let isActive: Bool
    public let isLoading: Bool
    public let isLiked: Bool
    public let upcomingCount: Int
    public let error: String?

    public init(
        currentTrack: BGYandexTrack? = nil,
        isActive: Bool = false,
        isLoading: Bool = false,
        isLiked: Bool = false,
        upcomingCount: Int = 0,
        error: String? = nil
    ) {
        self.currentTrack = currentTrack
        self.isActive = isActive
        self.isLoading = isLoading
        self.isLiked = isLiked
        self.upcomingCount = upcomingCount
        self.error = error
    }
}

/// Player interface required by `BGYandexWavePlaybackCoordinator`.
/// `BeyGramMusicSession` conforms in production; unit tests provide a deterministic fake.
public protocol BGYandexWavePlayerAdapter: AnyObject {
    /// Resolves and adds `track` to the audio player queue.
    /// Completes on the main queue with the player's unique queue item identifier (`UInt64`).
    func playWaveTrack(
        _ track: BGYandexTrack,
        replaceQueue: Bool,
        completion: @escaping (Result<UInt64, BGYandexPlaybackError>) -> Void
    )
    /// Triggers a smooth crossfade/advance to the already-prepared next track.
    /// Returns `true` if the player accepted the transition.
    func skipToPreparedNextWaveTrack() -> Bool
    /// Toggles play/pause on the current track.
    func toggleWavePlayPause()
}

/// Coordinates continuous "My Wave" playback independently of any UI view controller.
///
/// Guarantees:
/// - The first track is consumed from `BGYandexWaveQueue` via `takeNext()` exactly once before pre-enqueuing the next track.
/// - Track transitions are matched by player queue item ID (`UInt64`), so consecutive tracks with identical `yandexTrackId` still advance.
/// - Handles skip, end-of-track with empty next deck (`current == nil` / `.played`), download/decode failures with bounded retry,
///   and survives dismissal of the Yandex Music screen.
public final class BGYandexWavePlaybackCoordinator {
    public static let maxConsecutiveFailures = 3

    private let makeQueue: () -> BGYandexWaveQueue
    private weak var player: BGYandexWavePlayerAdapter?
    private let onLikeTrack: ((String, Bool) -> Void)?

    public var onStateChanged: ((BGYandexWaveState) -> Void)?

    private var waveQueue: BGYandexWaveQueue?
    private var currentTrack: BGYandexTrack?
    private var currentItemId: UInt64?
    private var preEnqueuedTrack: BGYandexTrack?
    private var preEnqueuedItemId: UInt64?

    private var isActive: Bool = false
    private var isLoading: Bool = false
    private var isStartingCurrent: Bool = false
    private var isPreEnqueuing: Bool = false
    private var isLiked: Bool = false
    private var error: String?

    private var generation: Int = 0
    private var consecutiveFailures: Int = 0
    private var reportedEndedItemId: UInt64?
    private var skippedItemId: UInt64?
    private var lastPosition: TimeInterval = 0.0
    private var lastDuration: TimeInterval = 0.0
    private var lastNextItemReady: Bool = false

    public init(
        makeQueue: @escaping () -> BGYandexWaveQueue,
        player: BGYandexWavePlayerAdapter,
        onLikeTrack: ((String, Bool) -> Void)? = nil
    ) {
        self.makeQueue = makeQueue
        self.player = player
        self.onLikeTrack = onLikeTrack
    }

    public var state: BGYandexWaveState {
        return BGYandexWaveState(
            currentTrack: self.currentTrack,
            isActive: self.isActive,
            isLoading: self.isLoading,
            isLiked: self.isLiked,
            upcomingCount: self.waveQueue?.upcomingTracks.count ?? 0,
            error: self.error
        )
    }

    private func publishState() {
        self.onStateChanged?(self.state)
    }

    private func ensureQueue() -> BGYandexWaveQueue {
        if let existing = self.waveQueue {
            return existing
        }
        let created = self.makeQueue()
        self.waveQueue = created
        return created
    }

    /// Starts "My Wave" if inactive, or toggles play/pause if the current wave track is already loaded.
    public func startOrTogglePlay() {
        if self.isLoading {
            return
        }
        if self.isActive, self.currentTrack != nil, self.currentItemId != nil {
            self.player?.toggleWavePlayPause()
            return
        }
        if self.isActive, let current = self.currentTrack, self.currentItemId == nil {
            self.playAsCurrent(current)
            return
        }

        let queue = self.ensureQueue()
        self.generation += 1
        let gen = self.generation
        self.isActive = true
        self.isLoading = true
        self.error = nil
        self.consecutiveFailures = 0
        self.publishState()

        queue.start { [weak self] result in
            guard let self, gen == self.generation else {
                return
            }
            self.isLoading = false
            switch result {
            case let .failure(err):
                self.isActive = false
                self.error = String(describing: err)
                self.publishState()
            case .success:
                // Consume the first track via takeNext() so it leaves upcomingTracks before we pre-enqueue the next one.
                guard let firstTrack = queue.takeNext() else {
                    self.isActive = false
                    self.error = "My Wave returned no tracks."
                    self.publishState()
                    return
                }
                self.playAsCurrent(firstTrack)
            }
        }
    }

    /// Skips the current wave track, reporting `.skipped` feedback and preserving BG Mix crossfade when the next track is ready.
    public func skip() {
        guard let current = self.currentTrack else {
            return
        }
        self.waveQueue?.trackSkipped(rowKey: current.rowKey, playedSeconds: self.lastPosition)
        self.skippedItemId = self.currentItemId
        self.reportedEndedItemId = self.currentItemId

        if self.preEnqueuedItemId != nil, self.lastNextItemReady, self.player?.skipToPreparedNextWaveTrack() == true {
            return
        }
        if let pre = self.preEnqueuedTrack {
            self.preEnqueuedTrack = nil
            self.preEnqueuedItemId = nil
            self.playAsCurrent(pre)
            return
        }
        if let next = self.waveQueue?.takeNext() {
            self.playAsCurrent(next)
            return
        }
        // Queue exhausted: restart wave cleanly.
        self.currentTrack = nil
        self.currentItemId = nil
        self.isActive = false
        self.startOrTogglePlay()
    }

    /// Toggles like for the active wave track and reports radio feedback.
    public func toggleLike() {
        guard let current = self.currentTrack else {
            return
        }
        self.isLiked.toggle()
        let liked = self.isLiked
        self.waveQueue?.setLiked(trackId: current.trackId, liked: liked)
        self.onLikeTrack?(current.trackId, liked)
        self.publishState()
    }

    /// Stops the wave session and ignores any in-flight async callbacks.
    public func stop() {
        self.generation += 1
        self.waveQueue?.stop()
        self.waveQueue = nil
        self.currentTrack = nil
        self.currentItemId = nil
        self.preEnqueuedTrack = nil
        self.preEnqueuedItemId = nil
        self.isActive = false
        self.isLoading = false
        self.isStartingCurrent = false
        self.isPreEnqueuing = false
        self.isLiked = false
        self.error = nil
        self.consecutiveFailures = 0
        self.reportedEndedItemId = nil
        self.skippedItemId = nil
        self.lastPosition = 0.0
        self.lastDuration = 0.0
        self.lastNextItemReady = false
        self.publishState()
    }

    /// Called on every player snapshot update (main queue) to drive continuous auto-advance.
    public func handlePlaybackUpdate(
        currentItemId: UInt64?,
        currentItemFailed: Bool,
        currentItemPlayed: Bool,
        nextItemReady: Bool,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        self.lastNextItemReady = nextItemReady
        guard self.isActive else {
            return
        }

        if let trackedId = self.currentItemId, currentItemId == trackedId {
            self.lastPosition = position
            if duration > 0 {
                self.lastDuration = duration
            }
            if currentItemFailed {
                self.handleCurrentPlaybackFailure(message: "Failed to prepare track.")
                return
            }
            if currentItemPlayed {
                self.handleCurrentTrackEnded()
                return
            }
            return
        }

        // Case 1: BG Mix transitioned cleanly from currentItemId to preEnqueuedItemId.
        if let newItemId = currentItemId,
           let preId = self.preEnqueuedItemId,
           let preTrack = self.preEnqueuedTrack,
           newItemId == preId {
            self.reportFinishedIfNeeded()
            self.currentTrack = preTrack
            self.currentItemId = preId
            self.preEnqueuedTrack = nil
            self.preEnqueuedItemId = nil
            self.isLiked = false
            self.error = nil
            self.consecutiveFailures = 0
            self.lastPosition = position
            self.lastDuration = duration
            self.skippedItemId = nil
            self.reportedEndedItemId = nil
            self.waveQueue?.trackStarted(rowKey: preTrack.rowKey)
            self.publishState()
            self.enqueueNextIfNeeded()
            return
        }

        // Case 2: Current track finished and player has no next track loaded (currentItemId == nil).
        if currentItemId == nil, self.currentItemId != nil, !self.isStartingCurrent {
            self.handleCurrentTrackEnded()
        }
    }

    private func reportFinishedIfNeeded() {
        guard let finishedTrack = self.currentTrack,
              let finishedId = self.currentItemId,
              self.reportedEndedItemId != finishedId,
              self.skippedItemId != finishedId else {
            return
        }
        self.reportedEndedItemId = finishedId
        let played = self.lastDuration > 0 ? self.lastDuration : self.lastPosition
        self.waveQueue?.trackFinished(rowKey: finishedTrack.rowKey, playedSeconds: played)
    }

    private func handleCurrentTrackEnded() {
        self.reportFinishedIfNeeded()
        self.currentItemId = nil
        if let pre = self.preEnqueuedTrack {
            self.preEnqueuedTrack = nil
            self.preEnqueuedItemId = nil
            self.playAsCurrent(pre)
        } else if let next = self.waveQueue?.takeNext() {
            self.playAsCurrent(next)
        } else {
            self.publishState()
        }
    }

    private func handleCurrentPlaybackFailure(message: String) {
        self.consecutiveFailures += 1
        self.currentItemId = nil
        if self.consecutiveFailures >= BGYandexWavePlaybackCoordinator.maxConsecutiveFailures {
            self.error = message
            self.publishState()
            return
        }
        if let pre = self.preEnqueuedTrack {
            self.preEnqueuedTrack = nil
            self.preEnqueuedItemId = nil
            self.playAsCurrent(pre)
        } else if let next = self.waveQueue?.takeNext() {
            self.playAsCurrent(next)
        } else {
            self.error = message
            self.publishState()
        }
    }

    private func playAsCurrent(_ track: BGYandexTrack) {
        self.generation += 1
        let gen = self.generation
        self.currentTrack = track
        self.currentItemId = nil
        self.preEnqueuedTrack = nil
        self.preEnqueuedItemId = nil
        self.isStartingCurrent = true
        self.isPreEnqueuing = false
        self.isLiked = false
        self.error = nil
        self.lastPosition = 0.0
        self.lastDuration = 0.0
        self.skippedItemId = nil
        self.reportedEndedItemId = nil
        self.publishState()

        self.player?.playWaveTrack(track, replaceQueue: true) { [weak self] result in
            guard let self, gen == self.generation else {
                return
            }
            self.isStartingCurrent = false
            switch result {
            case let .success(itemId):
                self.currentItemId = itemId
                self.consecutiveFailures = 0
                self.waveQueue?.trackStarted(rowKey: track.rowKey)
                self.publishState()
                self.enqueueNextIfNeeded()
            case let .failure(err):
                if BGYandexWavePlaybackCoordinator.stopsWaveAtOnce(err) {
                    self.error = String(describing: err)
                    self.publishState()
                    return
                }
                self.handleCurrentPlaybackFailure(message: String(describing: err))
            }
        }
    }

    private func enqueueNextIfNeeded() {
        guard self.isActive,
              !self.isStartingCurrent,
              !self.isPreEnqueuing,
              self.preEnqueuedTrack == nil,
              let next = self.waveQueue?.takeNext() else {
            return
        }
        let gen = self.generation
        self.isPreEnqueuing = true
        self.publishState()

        self.player?.playWaveTrack(next, replaceQueue: false) { [weak self] result in
            guard let self, gen == self.generation else {
                return
            }
            self.isPreEnqueuing = false
            switch result {
            case let .success(itemId):
                self.preEnqueuedTrack = next
                self.preEnqueuedItemId = itemId
                self.consecutiveFailures = 0
                self.publishState()
            case let .failure(err):
                if BGYandexWavePlaybackCoordinator.stopsWaveAtOnce(err) {
                    self.error = String(describing: err)
                    self.publishState()
                    return
                }
                self.consecutiveFailures += 1
                if self.consecutiveFailures < BGYandexWavePlaybackCoordinator.maxConsecutiveFailures {
                    self.enqueueNextIfNeeded()
                } else {
                    self.error = String(describing: err)
                    self.publishState()
                }
            }
        }
    }

    private static func stopsWaveAtOnce(_ error: BGYandexPlaybackError) -> Bool {
        switch error {
        case .notSignedIn, .subscriptionRequired:
            return true
        case .unavailable, .rateLimited, .network, .invalidFile:
            return false
        }
    }
}
