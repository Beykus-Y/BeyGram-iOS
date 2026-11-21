import Foundation

/// Immutable snapshot of the active "My Wave" radio playback session.
public struct BGYandexWaveState: Equatable {
    /// The track confirmed on the master audio deck (or the initial track while cold-starting).
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
    /// Resolves and submits `track` to the audio player queue.
    /// When `replaceQueue == true`, the player must atomically drain/clear decks before adding and playing.
    /// Completes on the main queue with the player's unique queue item identifier (`UInt64`).
    func playWaveTrack(
        _ track: BGYandexTrack,
        replaceQueue: Bool,
        completion: @escaping (Result<UInt64, BGYandexPlaybackError>) -> Void
    )
    /// Attempts a smooth crossfade/advance to the already-prepared next track.
    /// Must return `true` ONLY if the engine actually entered an active transition.
    func skipToPreparedNextWaveTrack() -> Bool
    /// Toggles play/pause on the current track.
    func toggleWavePlayPause()
}

/// Coordinates continuous "My Wave" playback independently of any UI view controller.
///
/// Guarantees:
/// - Single authority for advancing and enqueuing wave tracks.
/// - `state.currentTrack` reflects the actual audible master-deck track; adding/replacing a track
///   does not overwrite a sounding track in the UI until the master deck confirms the new item ID.
/// - `takeNext()` is not consumed until queue admission succeeds (or a track permanently fails),
///   preventing lost tracks on cancelled or busy-deck attempts.
/// - Transient `currentItemId == nil` before the master deck has confirmed the current track never
///   triggers runaway auto-advancing.
/// - Transitions are matched by player queue item ID (`UInt64`), supporting consecutive identical `yandexTrackId`s.
public final class BGYandexWavePlaybackCoordinator {
    public static let maxConsecutiveFailures = 3

    private let makeQueue: () -> BGYandexWaveQueue
    private weak var player: BGYandexWavePlayerAdapter?
    private let onLikeTrack: ((String, Bool) -> Void)?

    public var onStateChanged: ((BGYandexWaveState) -> Void)?

    private var waveQueue: BGYandexWaveQueue?

    // Audible master-deck state (source of truth for UI once confirmed).
    private var audibleTrack: BGYandexTrack?
    private var audibleItemId: UInt64?

    // Pending replacement track (submitted via replaceQueue=true, awaiting master-deck confirmation).
    private var pendingCurrentTrack: BGYandexTrack?
    private var pendingCurrentItemId: UInt64?

    // Pre-enqueued next track (submitted via replaceQueue=false, waiting on deck B).
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
    private var lastTransitionActive: Bool = false

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
        // Show the confirmed audible track whenever one is playing; fall back to pending only on cold start.
        let visibleTrack = self.audibleTrack ?? self.pendingCurrentTrack
        return BGYandexWaveState(
            currentTrack: visibleTrack,
            isActive: self.isActive,
            isLoading: self.isLoading || (self.isStartingCurrent && self.audibleTrack == nil),
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

    /// Starts "My Wave" if inactive, or toggles play/pause if the current wave track is already sounding.
    public func startOrTogglePlay() {
        if self.isLoading {
            return
        }
        if self.isActive, self.audibleTrack != nil, self.audibleItemId != nil {
            self.player?.toggleWavePlayPause()
            return
        }
        if self.isActive, self.isStartingCurrent {
            return
        }
        if self.isActive, let pending = self.pendingCurrentTrack, self.pendingCurrentItemId == nil {
            self.playAsCurrent(pending, alreadyConsumed: true)
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
                guard let firstTrack = queue.upcomingTracks.first else {
                    self.isActive = false
                    self.error = "My Wave returned no tracks."
                    self.publishState()
                    return
                }
                self.playAsCurrent(firstTrack, alreadyConsumed: false)
            }
        }
    }

    /// Skips the current wave track, reporting `.skipped` feedback and preserving BG Mix crossfade
    /// only when the engine confirms the transition actually started; otherwise falls back to atomic replace.
    public func skip() {
        guard let current = self.audibleTrack ?? self.pendingCurrentTrack else {
            return
        }
        let activeId = self.audibleItemId ?? self.pendingCurrentItemId
        self.waveQueue?.trackSkipped(rowKey: current.rowKey, playedSeconds: self.lastPosition)
        self.skippedItemId = activeId
        self.reportedEndedItemId = activeId

        if self.preEnqueuedItemId != nil,
           self.lastNextItemReady,
           !self.lastTransitionActive,
           self.player?.skipToPreparedNextWaveTrack() == true {
            return
        }

        if let pre = self.preEnqueuedTrack {
            self.preEnqueuedTrack = nil
            self.preEnqueuedItemId = nil
            self.playAsCurrent(pre, alreadyConsumed: true)
            return
        }
        if let next = self.waveQueue?.upcomingTracks.first {
            self.playAsCurrent(next, alreadyConsumed: false)
            return
        }
        // Queue exhausted: restart wave cleanly.
        self.audibleTrack = nil
        self.audibleItemId = nil
        self.pendingCurrentTrack = nil
        self.pendingCurrentItemId = nil
        self.isActive = false
        self.startOrTogglePlay()
    }

    /// Toggles like for the active audible wave track and reports radio feedback.
    public func toggleLike() {
        guard let current = self.audibleTrack ?? self.pendingCurrentTrack else {
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
        self.audibleTrack = nil
        self.audibleItemId = nil
        self.pendingCurrentTrack = nil
        self.pendingCurrentItemId = nil
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
        self.lastTransitionActive = false
        self.publishState()
    }

    /// Called on every player snapshot update (main queue) to synchronize UI with the real master deck
    /// and drive continuous auto-advance.
    public func handlePlaybackUpdate(
        currentItemId: UInt64?,
        currentItemFailed: Bool,
        currentItemPlayed: Bool,
        nextItemReady: Bool,
        transitionActive: Bool = false,
        isStopped: Bool = false,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        self.lastNextItemReady = nextItemReady
        self.lastTransitionActive = transitionActive
        guard self.isActive else {
            return
        }

        // Case 0: Pending replacement track has now been confirmed on the master deck.
        if let newItemId = currentItemId,
           let pendingId = self.pendingCurrentItemId,
           let pendingTrack = self.pendingCurrentTrack,
           newItemId == pendingId {
            self.audibleTrack = pendingTrack
            self.audibleItemId = pendingId
            self.pendingCurrentTrack = nil
            self.pendingCurrentItemId = nil
            self.isLiked = false
            self.error = nil
            self.consecutiveFailures = 0
            self.lastPosition = position
            self.lastDuration = duration
            self.skippedItemId = nil
            self.reportedEndedItemId = nil
            self.waveQueue?.trackStarted(rowKey: pendingTrack.rowKey)
            self.publishState()
            if !transitionActive {
                self.enqueueNextIfNeeded()
            }
            return
        }

        // Case 0b: Pending replacement track failed preparation before reaching master deck.
        if currentItemFailed,
           let newItemId = currentItemId,
           let pendingId = self.pendingCurrentItemId,
           newItemId == pendingId {
            self.pendingCurrentTrack = nil
            self.pendingCurrentItemId = nil
            self.handleCurrentPlaybackFailure(message: "Failed to prepare track.")
            return
        }

        // Case 1: Confirmed audible track is still on the master deck.
        if let trackedId = self.audibleItemId, currentItemId == trackedId {
            self.lastPosition = position
            if duration > 0 {
                self.lastDuration = duration
            }
            if currentItemFailed {
                self.handleCurrentPlaybackFailure(message: "Failed to prepare track.")
                return
            }
            if currentItemPlayed {
                self.handleAudibleTrackEnded()
                return
            }
            if !transitionActive && self.preEnqueuedTrack == nil && !self.isPreEnqueuing && !self.isStartingCurrent {
                self.enqueueNextIfNeeded()
            }
            return
        }

        // Case 2: BG Mix transitioned cleanly from audibleItemId to preEnqueuedItemId on the master deck.
        if let newItemId = currentItemId,
           let preId = self.preEnqueuedItemId,
           let preTrack = self.preEnqueuedTrack,
           newItemId == preId {
            self.reportFinishedIfNeeded()
            self.audibleTrack = preTrack
            self.audibleItemId = preId
            self.pendingCurrentTrack = nil
            self.pendingCurrentItemId = nil
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
            if !transitionActive {
                self.enqueueNextIfNeeded()
            }
            return
        }

        // Case 3: Confirmed audible track ended and player stopped with no next track loaded.
        // Guarded strictly by `audibleItemId != nil` and `pendingCurrentItemId == nil` and `!isStartingCurrent`
        // so transient nil snapshots during deck replacement NEVER trigger runaway auto-advance.
        if currentItemId == nil,
           isStopped,
           self.audibleItemId != nil,
           self.pendingCurrentItemId == nil,
           !self.isStartingCurrent,
           !transitionActive {
            self.handleAudibleTrackEnded()
        }
    }

    private func reportFinishedIfNeeded() {
        guard let finishedTrack = self.audibleTrack,
              let finishedId = self.audibleItemId,
              self.reportedEndedItemId != finishedId,
              self.skippedItemId != finishedId else {
            return
        }
        self.reportedEndedItemId = finishedId
        let played = self.lastDuration > 0 ? self.lastDuration : self.lastPosition
        self.waveQueue?.trackFinished(rowKey: finishedTrack.rowKey, playedSeconds: played)
    }

    private func handleAudibleTrackEnded() {
        self.reportFinishedIfNeeded()
        self.audibleItemId = nil
        if let pre = self.preEnqueuedTrack {
            self.preEnqueuedTrack = nil
            self.preEnqueuedItemId = nil
            self.playAsCurrent(pre, alreadyConsumed: true)
        } else if let next = self.waveQueue?.upcomingTracks.first {
            self.playAsCurrent(next, alreadyConsumed: false)
        } else {
            self.publishState()
        }
    }

    private func handleCurrentPlaybackFailure(message: String) {
        self.consecutiveFailures += 1
        if self.consecutiveFailures >= BGYandexWavePlaybackCoordinator.maxConsecutiveFailures {
            self.error = message
            self.publishState()
            return
        }
        if let pre = self.preEnqueuedTrack {
            self.preEnqueuedTrack = nil
            self.preEnqueuedItemId = nil
            self.playAsCurrent(pre, alreadyConsumed: true)
        } else if let next = self.waveQueue?.upcomingTracks.first {
            self.playAsCurrent(next, alreadyConsumed: false)
        } else {
            self.error = message
            self.publishState()
        }
    }

    private func playAsCurrent(_ track: BGYandexTrack, alreadyConsumed: Bool) {
        self.generation += 1
        let gen = self.generation
        self.pendingCurrentTrack = track
        self.pendingCurrentItemId = nil
        self.preEnqueuedTrack = nil
        self.preEnqueuedItemId = nil
        self.isStartingCurrent = true
        self.isPreEnqueuing = false
        self.error = nil
        self.publishState()

        self.player?.playWaveTrack(track, replaceQueue: true) { [weak self] result in
            guard let self, gen == self.generation else {
                return
            }
            self.isStartingCurrent = false
            switch result {
            case let .success(itemId):
                if !alreadyConsumed, self.waveQueue?.upcomingTracks.first?.trackId == track.trackId {
                    _ = self.waveQueue?.takeNext()
                }
                self.pendingCurrentItemId = itemId
                self.consecutiveFailures = 0
                self.publishState()
            case let .failure(err):
                if !alreadyConsumed, self.waveQueue?.upcomingTracks.first?.trackId == track.trackId,
                   !BGYandexWavePlaybackCoordinator.stopsWaveAtOnce(err) {
                    _ = self.waveQueue?.takeNext()
                }
                self.pendingCurrentTrack = nil
                self.pendingCurrentItemId = nil
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
              !self.lastTransitionActive,
              self.audibleItemId != nil,
              self.preEnqueuedTrack == nil,
              let candidate = self.waveQueue?.upcomingTracks.first else {
            return
        }
        let gen = self.generation
        self.isPreEnqueuing = true
        self.publishState()

        self.player?.playWaveTrack(candidate, replaceQueue: false) { [weak self] result in
            guard let self, gen == self.generation else {
                return
            }
            self.isPreEnqueuing = false
            switch result {
            case let .success(itemId):
                if self.waveQueue?.upcomingTracks.first?.trackId == candidate.trackId {
                    _ = self.waveQueue?.takeNext()
                }
                self.preEnqueuedTrack = candidate
                self.preEnqueuedItemId = itemId
                self.consecutiveFailures = 0
                self.publishState()
            case let .failure(err):
                if BGYandexWavePlaybackCoordinator.stopsWaveAtOnce(err) {
                    self.error = String(describing: err)
                    self.publishState()
                    return
                }
                if self.waveQueue?.upcomingTracks.first?.trackId == candidate.trackId {
                    _ = self.waveQueue?.takeNext()
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
