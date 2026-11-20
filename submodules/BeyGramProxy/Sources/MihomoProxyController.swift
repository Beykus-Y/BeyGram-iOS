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
                    self.deliver(.success(()), to: completion)
                } catch {
                    self.stopWatchdog()
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
    public func measureDelays(completion: @escaping (Result<[String: Int], Error>) -> Void) {
        queue.async {
            do {
                let group = try self.client.proxies(group: MihomoProxyController.groupName)
                var delays: [String: Int] = [:]
                for node in group.nodes {
                    // One node that fails must not cancel the others. It is reported as -1.
                    do {
                        delays[node.name] = try self.client.testDelay(proxy: node.name, timeoutMilliseconds: 5000)
                    } catch {
                        delays[node.name] = -1
                    }
                }
                self.deliver(.success(delays), to: completion)
            } catch {
                self.deliver(.failure(error), to: completion)
            }
        }
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
        // The delay stored in the group can be stale, so the node in use is probed directly.
        let inUseDelay = (try? client.testDelay(proxy: group.now, timeoutMilliseconds: MihomoProxyController.probeTimeoutMilliseconds)) ?? -1
        if inUseDelay <= 0 {
            selectFastestNode(nodes: group.nodes.map { $0.name })
        }
        scheduleNextTickIfActive(generation: generation)
    }

    private func scheduleNextTickIfActive(generation: Int) {
        if generation == watchdogGeneration {
            scheduleWatchdogTick(generation: generation)
        }
    }

    /// Runs on `queue`. Measures the nodes one by one and selects the fastest one that answers.
    private func selectFastestNode(nodes: [String]) {
        var bestName: String?
        var bestDelay = Int.max
        for name in nodes {
            let delay = (try? client.testDelay(proxy: name, timeoutMilliseconds: MihomoProxyController.probeTimeoutMilliseconds)) ?? -1
            if delay > 0 && delay < bestDelay {
                bestDelay = delay
                bestName = name
            }
        }
        guard let fastest = bestName else {
            return
        }
        do {
            try client.select(group: MihomoProxyController.groupName, proxy: fastest)
            update { $0.selectedNode = fastest }
        } catch {
            // The node in use stays. The next tick tries again.
        }
    }

    /// Runs on `queue`. Restarts the core with the profile kept in memory, and the node the user chose.
    private func restartCore() {
        guard let yaml = profileYAML else {
            stopWatchdog()
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
            profileYAML = nil
            update { $0.isRunning = false }
        }
    }

    private func loadText(_ source: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard SubscriptionFetcher.isWebAddress(source) else {
            completion(.success(source))
            return
        }
        SubscriptionFetcher.fetch(source) { result in
            completion(result.mapError { $0 as Error })
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
