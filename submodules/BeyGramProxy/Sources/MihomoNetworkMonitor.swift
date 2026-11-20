// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

import Foundation
import Network

/// Reports the changes of the network the phone uses while the core runs: an interface comes or goes, or the path
/// drops and comes back. The first path is only the baseline, so starting the monitor reports nothing.
/// A monitor runs once. A stopped `NWPathMonitor` cannot start again, so the owner makes a new monitor for each run.
public final class MihomoNetworkMonitor {
    /// What the monitor compares. Two paths with the same signature count as the same network.
    private struct Signature: Equatable {
        let usable: Bool
        let interfaces: [String]

        init(path: NWPath) {
            usable = path.status == .satisfied
            interfaces = path.availableInterfaces
                .filter { $0.type != .loopback }
                .map { "\($0.type)/\($0.name)" }
                .sorted()
        }
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "org.beygram.mihomo.network")
    private let onChange: () -> Void
    /// The last path seen. Only used on `queue`.
    private var last: Signature?

    /// `onChange` runs on the monitor's own queue, once for each change to a usable network.
    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        monitor.pathUpdateHandler = { [weak self] path in
            self?.receive(path)
        }
    }

    public func start() {
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    /// Runs on `queue`. A change is reported when the path is usable and differs from the one before it. A path that is
    /// not usable is not reported: nothing can be restarted onto it, and the network coming back is reported instead.
    /// Two limits: a new address on the same interface is not a change, and a switch between two Wi-Fi networks with
    /// no gap in between is not seen.
    private func receive(_ path: NWPath) {
        let next = Signature(path: path)
        let previous = last
        last = next
        guard let previous, next.usable, previous != next else {
            return
        }
        onChange()
    }
}
