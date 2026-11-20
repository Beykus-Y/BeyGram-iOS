import Foundation

/// One queue for every request to Yandex: a fixed gap between requests, and a whole-queue pause after 429.
/// Same rules as `YandexHttp.kt`. Time is passed in, so the gate can be tested without sleeping.
public struct BGYandexRequestGate {
    private var nextAllowedAt: TimeInterval = 0
    private var blockedUntil: TimeInterval = 0

    public init() {}

    /// Reserves the next slot and returns how long to wait before sending. Zero means send now.
    public mutating func reserve(now: TimeInterval) -> TimeInterval {
        let start = max(nextAllowedAt, blockedUntil, now)
        nextAllowedAt = start + BGYandexConfig.minRequestGap
        return start - now
    }

    /// Wait needed by a request that skips the gap (helper files on storage hosts). Only a 429 pause applies to it.
    public func pauseRemaining(now: TimeInterval) -> TimeInterval {
        return max(0, blockedUntil - now)
    }

    /// Call on a 429. `retryAfterHeader` is the raw header value, or nil when it is missing or not a number.
    public mutating func reportRateLimited(retryAfterHeader: String?, now: TimeInterval) {
        let seconds = retryAfterHeader.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? BGYandexConfig.defaultRetryAfter
        blockedUntil = now + seconds
    }
}
