import Foundation

/// Sleep timer of the player (issue #140, as on Android). Pausing when it ends is done by `BeyGramMusicSession`.
public enum BeyGramSleepTimerMode: Equatable {
    case off
    /// Pause after this many minutes.
    case minutes(Int)
    /// Pause when the current track ends (observed in `BeyGramMusicSession.checkSleepEndOfTrack`).
    case endOfTrack
}

/// Pure state of the sleep timer. It holds no clock: the caller passes `now`, so it is testable.
public struct BeyGramSleepTimerState: Equatable {
    /// Minute choices offered by the player's sheet.
    public static let minuteChoices: [Int] = [5, 10, 15, 30, 45, 60, 90]

    public private(set) var mode: BeyGramSleepTimerMode = .off
    public private(set) var endsAt: Date?

    public init() {
    }

    public mutating func start(minutes: Int, now: Date) {
        let clamped = max(1, minutes)
        self.mode = .minutes(clamped)
        self.endsAt = now.addingTimeInterval(TimeInterval(clamped * 60))
    }

    public mutating func startEndOfTrack() {
        self.mode = .endOfTrack
        self.endsAt = nil
    }

    public mutating func cancel() {
        self.mode = .off
        self.endsAt = nil
    }

    /// Seconds left for a minutes timer, nil when there is no such timer.
    public func remainingSeconds(now: Date) -> TimeInterval? {
        guard let endsAt = self.endsAt else {
            return nil
        }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// True once a minutes timer has reached its end.
    public func isExpired(now: Date) -> Bool {
        guard case .minutes = self.mode, let endsAt = self.endsAt else {
            return false
        }
        return now >= endsAt
    }
}
