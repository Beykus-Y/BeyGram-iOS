// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

import Foundation

/// The connection state of Telegram's network layer, as the automatic node switch needs it.
public enum MihomoTelegramConnection: Equatable {
    case connected
    case connecting
    case waitingForNetwork
}

/// Decides when the automatic node switch may probe nodes, as Android's `TelegramAutoSelector` does: only after Telegram has
/// stayed in `Connecting` (or `WaitingForNetwork`, where an unreachable node also lands) for `handover` seconds, and a change
/// of the network cancels that wait. While Telegram is `Connected` nothing is probed.
///
/// Until Telegram's state has been reported at all, the gate allows probing, which is the old behaviour of the 20-second
/// watchdog. Pure logic with the time passed in; the owner calls it from one queue.
public struct MihomoAutoSelectGate {
    /// Android's default handover delay.
    public static let defaultHandoverSeconds: TimeInterval = 8

    public private(set) var connection: MihomoTelegramConnection?
    private var since: Date?

    public init() {}

    /// Telegram's state. Entering `Connecting` or `WaitingForNetwork` starts the wait; a change between the two keeps it.
    public mutating func report(_ connection: MihomoTelegramConnection, now: Date) {
        if self.connection == connection {
            return
        }
        let wasWaiting = self.isWaiting
        self.connection = connection
        if connection == .connected || !wasWaiting {
            self.since = now
        }
    }

    /// The network changed: a wait in progress starts over.
    public mutating func networkChanged(now: Date) {
        if self.isWaiting {
            self.since = now
        }
    }

    /// Back to "no report", for a new run of the core.
    public mutating func reset() {
        self.connection = nil
        self.since = nil
    }

    public func shouldProbe(now: Date, handover: TimeInterval = MihomoAutoSelectGate.defaultHandoverSeconds) -> Bool {
        guard let connection = self.connection else {
            return true
        }
        switch connection {
        case .connected:
            return false
        case .connecting, .waitingForNetwork:
            guard let since = self.since else {
                return true
            }
            return now.timeIntervalSince(since) >= handover
        }
    }

    private var isWaiting: Bool {
        return self.connection == .connecting || self.connection == .waitingForNetwork
    }
}
