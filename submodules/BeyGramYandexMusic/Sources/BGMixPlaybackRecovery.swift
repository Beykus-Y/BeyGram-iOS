import Foundation

/// Small, deterministic policies shared by the music playlist adapter and its regression tests.
public struct BGMixFailureStreak {
    public static let limit = 5

    public private(set) var consecutiveFailures = 0

    public init() {}

    /// Records one unplayable item and returns the new streak length.
    @discardableResult
    public mutating func recordFailure() -> Int {
        self.consecutiveFailures += 1
        return self.consecutiveFailures
    }

    /// A track that starts successfully ends the previous run of failures.
    public mutating func reset() {
        self.consecutiveFailures = 0
    }
}

public enum BGMixPlaybackRecovery {
    /// A playlist may report the same row after Next on repeat-all with one item, or after a failed row is retried.
    /// Restart only when the playlist is settled, the item is still the one we left, and it did not just finish.
    public static func shouldRestartItem(advanceFrom: AnyHashable?,
                                         currentItem: AnyHashable?,
                                         isLoading: Bool,
                                         playedToEnd: Bool) -> Bool {
        guard !isLoading, !playedToEnd, let advanceFrom, let currentItem else {
            return false
        }
        return currentItem == advanceFrom
    }
}
