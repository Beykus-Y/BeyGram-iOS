import Foundation

/// The state of the player's sleep timer, as Android's `SleepTimerState` holds it.
public enum BeyGramSleepTimerState: Equatable {
    case off
    /// Fires at `deadline`.
    case minutes(deadline: Date, accountId: Int64)
    /// Fires when the track with `trackId` ends. `trackId` is nil while the track is not known yet.
    case untilTrackEnd(trackId: String?, accountId: Int64)

    public var accountId: Int64? {
        switch self {
        case .off:
            return nil
        case let .minutes(_, accountId), let .untilTrackEnd(_, accountId):
            return accountId
        }
    }
}

/// Sleep timer of the shared player: stops playback after N minutes or at the end of the current track.
///
/// Pure logic with an injected clock: the owner reports `trackChanged` and `trackEnded`, calls `tick()` on a timer
/// and stops the player when `onFire` runs. Call it from one queue (the main queue).
///
/// As on Android, the timer survives a track change within the same account, and is cancelled when another account
/// becomes the active one.
public final class BeyGramSleepTimer {
    /// Minute presets offered by the player menu.
    public static let presetMinutes: [Int] = [5, 10, 15, 30, 45, 60, 90]
    /// What "extend" adds.
    public static let extensionMinutes = 15

    public private(set) var state: BeyGramSleepTimerState = .off {
        didSet {
            if oldValue != self.state {
                self.onChange?(self.state)
            }
        }
    }

    public var onChange: ((BeyGramSleepTimerState) -> Void)?
    /// The player should stop now.
    public var onFire: (() -> Void)?

    private let now: () -> Date
    private var accountId: Int64
    private var currentTrackId: String?

    public init(accountId: Int64, now: @escaping () -> Date = { Date() }) {
        self.accountId = accountId
        self.now = now
    }

    public var isActive: Bool {
        return self.state != .off
    }

    /// Seconds left of a minutes timer, nil for the other states.
    public var remainingSeconds: TimeInterval? {
        guard case let .minutes(deadline, _) = self.state else {
            return nil
        }
        return max(0, deadline.timeIntervalSince(self.now()))
    }

    public func setMinutes(_ minutes: Int) {
        guard minutes > 0 else {
            self.cancel()
            return
        }
        self.state = .minutes(deadline: self.now().addingTimeInterval(TimeInterval(minutes) * 60), accountId: self.accountId)
    }

    public func setUntilTrackEnd() {
        self.state = .untilTrackEnd(trackId: self.currentTrackId, accountId: self.accountId)
    }

    /// Adds minutes to a minutes timer. For a "until track end" timer, or none, it starts a minutes timer instead.
    public func extend(minutes: Int = BeyGramSleepTimer.extensionMinutes) {
        guard minutes > 0 else {
            return
        }
        if case let .minutes(deadline, accountId) = self.state {
            let base = max(deadline, self.now())
            self.state = .minutes(deadline: base.addingTimeInterval(TimeInterval(minutes) * 60), accountId: accountId)
        } else {
            self.setMinutes(minutes)
        }
    }

    public func cancel() {
        self.state = .off
    }

    /// The active account changed. A timer of another account is dropped.
    public func accountChanged(to accountId: Int64) {
        self.accountId = accountId
        if let timerAccount = self.state.accountId, timerAccount != accountId {
            self.cancel()
        }
    }

    /// The player's current track changed (nil: nothing plays). A track-end timer that has not seen its track yet adopts this one.
    /// A track-end timer stays on the track it was set on; the change itself is not the end, see `trackEnded`.
    public func trackChanged(to trackId: String?) {
        self.currentTrackId = trackId
        if case let .untilTrackEnd(armedTrack, accountId) = self.state, armedTrack == nil, let trackId = trackId {
            self.state = .untilTrackEnd(trackId: trackId, accountId: accountId)
        }
    }

    /// The track with this id played to its end. Fires a track-end timer armed on that track.
    public func trackEnded(trackId: String?) {
        guard case let .untilTrackEnd(armedTrack, _) = self.state else {
            return
        }
        if armedTrack == nil || armedTrack == trackId {
            self.fire()
        }
    }

    /// Call about once a second while the timer is active.
    public func tick() {
        guard case let .minutes(deadline, _) = self.state else {
            return
        }
        if self.now() >= deadline {
            self.fire()
        }
    }

    private func fire() {
        self.state = .off
        self.onFire?()
    }
}
