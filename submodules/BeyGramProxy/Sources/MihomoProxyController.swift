// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

import Foundation

public enum MihomoProxyError: Error, Equatable {
    case emptySubscription
    case noSubscription
    case homeDirectory
}

extension MihomoProxyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptySubscription:
            return "Подписка пустая."
        case .noSubscription:
            return "Сначала сохраните подписку."
        case .homeDirectory:
            return "Не удалось создать папку ядра."
        }
    }
}

/// Owns the Mihomo core of the app: the subscription, start and stop, the node in use, and delay checks.
/// Core calls block, so they run on a private serial queue. Completions are delivered on the main queue.
public final class MihomoProxyController {
    /// The loopback SOCKS5 inlet that every profile opens. Must match normalize.Host and normalize.Port.
    public static let inletHost = "127.0.0.1"
    public static let inletPort: Int32 = 17891
    /// The selectable group that routes everything. Must match normalize.ConnectionGroup.
    public static let groupName = "BeyGram Telegram"

    private let client: MihomoCoreClient
    private let store: MihomoProxyStateStore
    private let homeDirectory: URL
    private let queue = DispatchQueue(label: "org.beygram.mihomo.controller")
    private let lock = NSLock()
    private var state: MihomoProxyState
    /// The profile of the running core, kept in memory only: it holds the loopback password.
    /// A restart of the core reuses it without fetching the subscription again.
    private var profileYAML: String?
    /// Bumped on every watchdog start and stop, so a tick scheduled earlier does nothing.
    private var watchdogGeneration = 0
    private static let watchdogIntervalSeconds = 20
    private static let probeTimeoutMilliseconds = 5000
    /// After a change of the network, the core is checked once the network has stayed as it is for this long.
    private static let networkSettleSeconds = 2
    /// Bumped by every change of the network and every stop of the watch, so a recovery scheduled earlier does nothing.
    /// Used on `queue` only.
    private var networkGeneration = 0
    /// Watches the network while the core runs. A new monitor for each run. Used on `queue` only.
    private var networkMonitor: MihomoNetworkMonitor?
    /// At most this many probes are in flight at once. The limit protects the phone's network, not the core.
    private static let maxConcurrentProbes = 8
    /// Probes wait on the network, so they run here, off `queue`: a check never holds up start, stop or a node change.
    private let probeQueue = DispatchQueue(label: "org.beygram.mihomo.probes", attributes: .concurrent)
    /// Runs the delay checks and the watchdog passes that wait for probes. Also off `queue`.
    private let checkQueue = DispatchQueue(label: "org.beygram.mihomo.checks", qos: .utility)
    /// The latest delay check. Guarded by `lock`.
    private var latencyCheck = MihomoLatencyCheck.idle
    /// Observers of `latencyCheck`, by token. Guarded by `lock`.
    private var latencyObservers: [Int: (MihomoLatencyCheck) -> Void] = [:]
    private var nextLatencyObserverId = 0

    public init(client: MihomoCoreClient, store: MihomoProxyStateStore, homeDirectory: URL) {
        self.client = client
        self.store = store
        self.homeDirectory = homeDirectory
        self.state = store.load()
    }

    /// The persisted state. Safe to read from any thread.
    public var currentState: MihomoProxyState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Keeps Telegram's proxy settings from before the first connect, or clears them with nil.
    public func setTelegramSettingsBeforeConnect(_ data: Data?) {
        update { $0.telegramSettingsBeforeConnect = data }
    }

    /// Checks a subscription (an https link, or the text itself), keeps it, and returns the server names.
    public func saveSubscription(_ source: String, completion: @escaping (Result<[String], Error>) -> Void) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deliver(.failure(MihomoProxyError.emptySubscription), to: completion)
            return
        }
        loadText(trimmed) { result in
            self.queue.async {
                do {
                    let text = try result.get()
                    let credentials = try LoopbackCredentialStore.loadOrCreate()
                    let profile = try self.client.normalize(source: text, credentials: credentials)
                    self.update { state in
                        state.subscriptionSource = trimmed
                        state.serverNames = profile.serverNames
                        if let selected = state.selectedNode, !profile.serverNames.contains(selected) {
                            state.selectedNode = nil
                        }
                    }
                    self.deliver(.success(profile.serverNames), to: completion)
                } catch {
                    self.deliver(.failure(error), to: completion)
                }
            }
        }
    }

    /// Loads the saved subscription again and keeps its server list. Neither the automatic switch nor Telegram's proxy
    /// settings change. A running core takes the new profile at once, and only when the profile differs from the one it
    /// runs; the node in use stays when it is still in the list. A failed load changes nothing.
    public func refreshSubscription(completion: @escaping (Result<[String], Error>) -> Void) {
        guard let source = currentState.subscriptionSource else {
            deliver(.failure(MihomoProxyError.noSubscription), to: completion)
            return
        }
        loadText(source) { result in
            self.queue.async {
                do {
                    let text = try result.get()
                    let credentials = try LoopbackCredentialStore.loadOrCreate()
                    let profile = try self.client.normalize(source: text, credentials: credentials)
                    self.update { state in
                        state.serverNames = profile.serverNames
                        if let selected = state.selectedNode, !profile.serverNames.contains(selected) {
                            state.selectedNode = nil
                        }
                    }
                    if self.currentState.isRunning, let running = self.profileYAML, running != profile.yaml {
                        self.profileYAML = profile.yaml
                        self.restartCore()
                        if !self.currentState.isRunning {
                            throw MihomoCoreError.refused("Ядро не запустилось с обновлённой подпиской. Подключение остановлено.")
                        }
                    }
                    self.deliver(.success(profile.serverNames), to: completion)
                } catch {
                    self.deliver(.failure(error), to: completion)
                }
            }
        }
    }

    /// Loads the saved subscription, starts the core on the loopback inlet, and selects the node the user chose.
    public func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let source = currentState.subscriptionSource else {
            deliver(.failure(MihomoProxyError.noSubscription), to: completion)
            return
        }
        loadText(source) { result in
            self.queue.async {
                do {
                    let text = try result.get()
                    let credentials = try LoopbackCredentialStore.loadOrCreate()
                    try self.prepareHomeDirectory()
                    try self.client.initialize(homeDirectory: self.homeDirectory.path)
                    let profile = try self.client.normalize(source: text, credentials: credentials)
                    var selected: [String: String] = [:]
                    if let node = self.currentState.selectedNode {
                        selected[MihomoProxyController.groupName] = node
                    }
                    try self.client.setup(config: profile.yaml, selected: selected)
                    self.profileYAML = profile.yaml
                    self.update { state in
                        state.isRunning = true
                        state.serverNames = profile.serverNames
                    }
                    self.startWatchdogIfEnabled()
                    self.startNetworkWatch()
                    self.deliver(.success(()), to: completion)
                } catch {
                    self.stopWatchdog()
                    self.stopNetworkWatch()
                    self.update { $0.isRunning = false }
                    self.deliver(.failure(error), to: completion)
                }
            }
        }
    }

    /// Stops the core. The state says "stopped" even when the core reports an error.
    public func stop(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            var result: Result<Void, Error> = .success(())
            self.stopWatchdog()
            self.stopNetworkWatch()
            self.profileYAML = nil
            do {
                try self.client.stop()
            } catch {
                result = .failure(error)
            }
            self.update { $0.isRunning = false }
            self.deliver(result, to: completion)
        }
    }

    /// Makes a node the one in use. While the core runs, the change applies at once.
    public func selectNode(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            do {
                if self.currentState.isRunning {
                    try self.client.select(group: MihomoProxyController.groupName, proxy: name)
                }
                self.update { $0.selectedNode = name }
                self.deliver(.success(()), to: completion)
            } catch {
                self.deliver(.failure(error), to: completion)
            }
        }
    }

    /// Called at app launch. When the core was running at the last exit, starts it again.
    /// Telegram keeps pointing at the loopback inlet, so only the core needs to come back.
    public func resumeIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard currentState.isRunning, currentState.subscriptionSource != nil else {
            deliver(.success(()), to: completion)
            return
        }
        start(completion: completion)
    }

    /// Turns the automatic node switch on or off. It takes effect at once while the core runs.
    public func setAutoSelect(_ enabled: Bool) {
        queue.async {
            self.update { $0.autoSelectEnabled = enabled }
            if enabled && self.currentState.isRunning {
                self.startWatchdogIfEnabled()
            } else {
                self.stopWatchdog()
            }
        }
    }

    /// Measures every node of the group. Needs a running core. Returns node name to delay in ms (-1 when it failed).
    /// The probes run a few at a time, off `queue`, so start, stop and a node change are not held up while they wait.
    /// Progress is published through `latencyCheckState` and `addLatencyObserver`.
    public func measureDelays(completion: @escaping (Result<[String: Int], Error>) -> Void) {
        queue.async {
            do {
                let group = try self.client.proxies(group: MihomoProxyController.groupName)
                let names = MihomoProxyController.serverNames(in: group)
                self.updateLatencyCheck { $0 = MihomoLatencyCheck(phase: .running, total: names.count, delays: [:]) }
                self.checkQueue.async {
                    // One node that fails must not cancel the others. It is reported as -1.
                    let delays = self.probeDelays(names, timeoutMilliseconds: MihomoProxyController.probeTimeoutMilliseconds) { name, delay in
                        self.updateLatencyCheck { $0.record(name, delay: delay) }
                    }
                    self.updateLatencyCheck { $0.finish() }
                    self.deliver(.success(delays), to: completion)
                }
            } catch {
                self.deliver(.failure(error), to: completion)
            }
        }
    }

    /// The latest delay check. Safe to read from any thread.
    public var latencyCheckState: MihomoLatencyCheck {
        lock.lock()
        defer { lock.unlock() }
        return latencyCheck
    }

    /// Calls `observer` now with the latest delay check, and again after each change, on the main queue.
    /// Returns a token for `removeLatencyObserver`. Keep the observer's token for as long as the observer is needed.
    public func addLatencyObserver(_ observer: @escaping (MihomoLatencyCheck) -> Void) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let token = nextLatencyObserverId
        nextLatencyObserverId += 1
        latencyObservers[token] = observer
        let snapshot = latencyCheck
        DispatchQueue.main.async {
            observer(snapshot)
        }
        return token
    }

    public func removeLatencyObserver(_ token: Int) {
        lock.lock()
        defer { lock.unlock() }
        latencyObservers.removeValue(forKey: token)
    }

    /// Changes the delay check and tells the observers. The notifications are queued while `lock` is held, so they
    /// arrive on the main queue in the order of the changes.
    private func updateLatencyCheck(_ change: (inout MihomoLatencyCheck) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&latencyCheck)
        let snapshot = latencyCheck
        for observer in latencyObservers.values {
            DispatchQueue.main.async {
                observer(snapshot)
            }
        }
    }

    /// Probes each node, with at most `maxConcurrentProbes` in flight, and returns once all have answered. It blocks the
    /// calling thread, so call it from `checkQueue`, never from `queue`. `onEach` runs as each answer arrives.
    private func probeDelays(_ names: [String], timeoutMilliseconds: Int, onEach: @escaping (String, Int) -> Void) -> [String: Int] {
        let answers = ProbeAnswers()
        let slots = DispatchSemaphore(value: MihomoProxyController.maxConcurrentProbes)
        let finished = DispatchGroup()
        for name in names {
            slots.wait()
            finished.enter()
            probeQueue.async {
                let delay = (try? self.client.testDelay(proxy: name, timeoutMilliseconds: timeoutMilliseconds)) ?? -1
                answers.record(name, delay)
                onEach(name, delay)
                slots.signal()
                finished.leave()
            }
        }
        finished.wait()
        return answers.delays
    }

    // MARK: - Watchdog

    /// Runs on `queue`. Starts the periodic check when the core runs and the automatic switch is on.
    private func startWatchdogIfEnabled() {
        stopWatchdog()
        guard currentState.isRunning, currentState.autoSelectEnabled else {
            return
        }
        scheduleWatchdogTick(generation: watchdogGeneration)
    }

    /// Runs on `queue`. Any tick already scheduled becomes a no-op.
    private func stopWatchdog() {
        watchdogGeneration += 1
    }

    private func scheduleWatchdogTick(generation: Int) {
        queue.asyncAfter(deadline: .now() + .seconds(MihomoProxyController.watchdogIntervalSeconds)) {
            self.watchdogTick(generation: generation)
        }
    }

    /// Runs on `queue`. One check: if the core stops answering it is restarted; if the node in use
    /// does not answer, the fastest node that does is selected. Then the next check is scheduled.
    private func watchdogTick(generation: Int) {
        guard generation == watchdogGeneration, currentState.isRunning, currentState.autoSelectEnabled else {
            return
        }
        let group: MihomoGroupState
        do {
            group = try client.proxies(group: MihomoProxyController.groupName)
        } catch {
            restartCore()
            scheduleNextTickIfActive(generation: generation)
            return
        }
        // The probes wait on the network, so they run off `queue`: a check never holds up start, stop or a node change.
        checkQueue.async {
            // The delay stored in the group can be stale, so the node in use is probed directly.
            let inUseDelay = (try? self.client.testDelay(proxy: group.now, timeoutMilliseconds: MihomoProxyController.probeTimeoutMilliseconds)) ?? -1
            let fastest: String? = inUseDelay <= 0 ? self.fastestNode(among: MihomoProxyController.serverNames(in: group)) : nil
            self.queue.async {
                if let fastest = fastest {
                    self.selectIfStillWatching(fastest, generation: generation)
                }
                self.scheduleNextTickIfActive(generation: generation)
            }
        }
    }

    private func scheduleNextTickIfActive(generation: Int) {
        if generation == watchdogGeneration {
            scheduleWatchdogTick(generation: generation)
        }
    }

    /// The names of the group's entries that are servers, in the group's order. See `MihomoServerRule`.
    private static func serverNames(in group: MihomoGroupState) -> [String] {
        return group.nodes.filter { MihomoServerRule.isServer(type: $0.type) }.map { $0.name }
    }

    /// Runs off `queue`. Probes the nodes and returns the fastest one that answers; of equal delays, the first in order.
    private func fastestNode(among names: [String]) -> String? {
        let delays = probeDelays(names, timeoutMilliseconds: MihomoProxyController.probeTimeoutMilliseconds) { _, _ in }
        var bestName: String?
        var bestDelay = Int.max
        for name in names {
            let delay = delays[name] ?? -1
            if delay > 0 && delay < bestDelay {
                bestDelay = delay
                bestName = name
            }
        }
        return bestName
    }

    /// Runs on `queue`. Selects the node the probes chose, unless the watchdog has stopped or the core is no longer running.
    private func selectIfStillWatching(_ name: String, generation: Int) {
        guard generation == watchdogGeneration, currentState.isRunning else {
            return
        }
        do {
            try client.select(group: MihomoProxyController.groupName, proxy: name)
            update { $0.selectedNode = name }
        } catch {
            // The node in use stays. The next tick tries again.
        }
    }

    /// Runs on `queue`. Restarts the core with the profile kept in memory, and the node the user chose.
    private func restartCore() {
        guard let yaml = profileYAML else {
            stopWatchdog()
            stopNetworkWatch()
            update { $0.isRunning = false }
            return
        }
        _ = try? client.stop()
        do {
            try client.initialize(homeDirectory: homeDirectory.path)
            var selected: [String: String] = [:]
            if let node = currentState.selectedNode {
                selected[MihomoProxyController.groupName] = node
            }
            try client.setup(config: yaml, selected: selected)
        } catch {
            stopWatchdog()
            stopNetworkWatch()
            profileYAML = nil
            update { $0.isRunning = false }
        }
    }

    // MARK: - Network changes

    /// Runs on `queue`. Watches the network while the core runs. Each run uses a new monitor, because a stopped one cannot start again.
    private func startNetworkWatch() {
        stopNetworkWatch()
        let monitor = MihomoNetworkMonitor { [weak self] in
            guard let self = self else {
                return
            }
            self.queue.async {
                self.networkChanged()
            }
        }
        networkMonitor = monitor
        monitor.start()
    }

    /// Runs on `queue`. Stops the watch. A recovery that is still waiting then does nothing.
    private func stopNetworkWatch() {
        networkGeneration += 1
        networkMonitor?.stop()
        networkMonitor = nil
    }

    /// Runs on `queue`. A change starts the recovery once the network has stayed as it is for `networkSettleSeconds`.
    /// A change that comes meanwhile restarts that wait, so one handover gives one recovery.
    private func networkChanged() {
        guard currentState.isRunning, profileYAML != nil else {
            return
        }
        networkGeneration += 1
        let generation = networkGeneration
        queue.asyncAfter(deadline: .now() + .seconds(MihomoProxyController.networkSettleSeconds)) {
            self.recoverAfterNetworkChange(generation: generation)
        }
    }

    /// Runs on `queue`. The node in use is probed first. When it answers, nothing changes, so a change the core
    /// rides out costs nothing. When it does not answer, the core is restarted and the node is probed again.
    private func recoverAfterNetworkChange(generation: Int) {
        guard generation == networkGeneration, currentState.isRunning, profileYAML != nil else {
            return
        }
        guard let group = try? client.proxies(group: MihomoProxyController.groupName) else {
            restartAfterNetworkChange(generation: generation)
            return
        }
        probeOffQueue(group.now) { answered in
            if !answered {
                self.restartAfterNetworkChange(generation: generation)
            }
        }
    }

    /// Runs on `queue`. Restarts the core with the profile and the node the user chose, then probes that node again.
    /// If it still does not answer and the automatic switch is on, the fastest node that answers is selected.
    private func restartAfterNetworkChange(generation: Int) {
        guard generation == networkGeneration, currentState.isRunning, profileYAML != nil else {
            return
        }
        restartCore()
        guard generation == networkGeneration, currentState.isRunning,
              let group = try? client.proxies(group: MihomoProxyController.groupName) else {
            return
        }
        probeOffQueue(group.now) { answered in
            guard generation == self.networkGeneration, self.currentState.isRunning, !answered,
                  self.currentState.autoSelectEnabled else {
                return
            }
            self.selectFastestAfterNetworkChange(names: MihomoProxyController.serverNames(in: group), generation: generation)
        }
    }

    /// Runs on `queue`. Probes the nodes off `queue` and selects the fastest one that answers. Nothing is selected when the
    /// core has stopped or the network has changed again in the meantime.
    private func selectFastestAfterNetworkChange(names: [String], generation: Int) {
        checkQueue.async {
            let fastest = self.fastestNode(among: names)
            self.queue.async {
                guard let fastest, generation == self.networkGeneration, self.currentState.isRunning else {
                    return
                }
                do {
                    try self.client.select(group: MihomoProxyController.groupName, proxy: fastest)
                    self.update { $0.selectedNode = fastest }
                } catch {
                    // The node in use stays. The next change of the network tries again.
                }
            }
        }
    }

    /// Runs on `queue`. Probes one node on `probeQueue`, so a running delay check does not hold it up, and calls `then`
    /// back on `queue` with whether the node answered. Only `testDelay` runs off `queue`, which the core allows beside other actions.
    private func probeOffQueue(_ name: String, then: @escaping (Bool) -> Void) {
        probeQueue.async {
            let delay = (try? self.client.testDelay(proxy: name, timeoutMilliseconds: MihomoProxyController.probeTimeoutMilliseconds)) ?? -1
            self.queue.async {
                then(delay > 0)
            }
        }
    }

    private func loadText(_ source: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard SubscriptionFetcher.isWebAddress(source) else {
            completion(.success(source))
            return
        }
        do {
            let installationId = try InstallationIdentifierStore.loadOrCreate()
            SubscriptionFetcher.fetch(source, installationId: installationId) { result in
                completion(result.mapError { $0 as Error })
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func prepareHomeDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        } catch {
            throw MihomoProxyError.homeDirectory
        }
    }

    private func update(_ change: (inout MihomoProxyState) -> Void) {
        lock.lock()
        change(&state)
        let snapshot = state
        lock.unlock()
        _ = try? store.save(snapshot)
    }

    private func deliver<Value>(_ result: Result<Value, Error>, to completion: @escaping (Result<Value, Error>) -> Void) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

/// A delay check of the selectable group. `delays` holds the answers so far, in ms, or -1 for a node that did not answer.
public struct MihomoLatencyCheck: Equatable {
    public enum Phase: Equatable {
        case idle
        case running
        case finished
    }

    public private(set) var phase: Phase
    /// The nodes of the group when the check began.
    public private(set) var total: Int
    public private(set) var delays: [String: Int]

    public static let idle = MihomoLatencyCheck(phase: .idle, total: 0, delays: [:])

    /// The nodes that have answered so far.
    public var completed: Int {
        return delays.count
    }

    public init(phase: Phase, total: Int, delays: [String: Int]) {
        self.phase = phase
        self.total = total
        self.delays = delays
    }

    mutating func record(_ name: String, delay: Int) {
        delays[name] = delay
    }

    mutating func finish() {
        phase = .finished
    }
}

/// Collects the answers of probes that finish on different threads.
private final class ProbeAnswers: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]

    func record(_ name: String, _ delay: Int) {
        lock.lock()
        defer { lock.unlock() }
        values[name] = delay
    }

    var delays: [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
