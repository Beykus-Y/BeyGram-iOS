import Foundation

/// A listening fact about one track of a radio, before it becomes a request. `rowKey` is the track's row key (`ym:...`).
public enum BGYandexListenEvent: Equatable {
    case started(rowKey: String)
    case finished(rowKey: String, playedSeconds: Double)
    case skipped(rowKey: String, playedSeconds: Double)

    public var rowKey: String {
        switch self {
        case let .started(rowKey):
            return rowKey
        case let .finished(rowKey, _):
            return rowKey
        case let .skipped(rowKey, _):
            return rowKey
        }
    }
}

/// What the listening tracker needs from one player state. Times are in milliseconds.
public struct BGYandexListenSnapshot: Equatable {
    /// The player still plays the queue of this radio.
    public let radioActive: Bool
    /// Row key of the current item, nil when there is none.
    public let rowKey: String?
    public let playing: Bool
    public let positionMs: Int64
    public let durationMs: Int64
    public let ended: Bool

    public init(radioActive: Bool, rowKey: String?, playing: Bool, positionMs: Int64, durationMs: Int64, ended: Bool) {
        self.radioActive = radioActive
        self.rowKey = rowKey
        self.playing = playing
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.ended = ended
    }
}

/// Turns player states into listening facts for one radio (port of `WaveListenTracker` on Android). A track counts as
/// started once it plays. When another track replaces it, it counts as finished if it reached its end, or its last seconds
/// (which a crossfade cuts off); otherwise it counts as skipped, with the seconds heard. Feed every player state, in order,
/// and stop once `closed` is true.
public struct BGYandexListenTracker {
    private let isRadioTrack: (String) -> Bool
    private var rowKey: String?
    private var started = false
    private var positionMs: Int64 = 0
    private var durationMs: Int64 = 0
    private var ended = false
    /// The radio has been the player's queue at least once; before that, an inactive state is just a late start.
    private var seenActive = false

    /// True once the radio stopped being the player's queue. No further state matters.
    public private(set) var closed = false

    /// `isRadioTrack` tells whether a row key belongs to the radio (`BGYandexWaveSession.radioTrack(rowKey:) != nil`).
    public init(isRadioTrack: @escaping (String) -> Bool) {
        self.isRadioTrack = isRadioTrack
    }

    public mutating func onState(_ state: BGYandexListenSnapshot) -> [BGYandexListenEvent] {
        if closed {
            return []
        }
        if state.radioActive {
            seenActive = true
        }
        if !seenActive {
            return []
        }
        var events: [BGYandexListenEvent] = []
        if let current = rowKey, !state.radioActive || state.rowKey != current {
            if let event = closeCurrent(current) {
                events.append(event)
            }
            rowKey = nil
        }
        if !state.radioActive {
            closed = true
            return events
        }
        if rowKey == nil, let now = state.rowKey, isRadioTrack(now) {
            rowKey = now
            started = false
            positionMs = 0
            durationMs = 0
            ended = false
        }
        if let now = state.rowKey, rowKey == now {
            positionMs = state.positionMs
            if state.durationMs > 0 {
                durationMs = state.durationMs
            }
            if state.ended {
                ended = true
            }
            if state.playing && !started {
                started = true
                events.append(.started(rowKey: now))
            }
        }
        return events
    }

    private func closeCurrent(_ key: String) -> BGYandexListenEvent? {
        guard started else {
            return nil
        }
        let nearEnd = durationMs > 0 && (durationMs - positionMs <= 15_000 || Double(positionMs) >= Double(durationMs) * 0.95)
        if ended || nearEnd {
            let heard = durationMs > 0 ? durationMs : positionMs
            return .finished(rowKey: key, playedSeconds: Double(heard) / 1000)
        }
        return .skipped(rowKey: key, playedSeconds: Double(positionMs) / 1000)
    }
}
