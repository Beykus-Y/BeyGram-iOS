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
                    self.update { state in
                        state.isRunning = true
                        state.serverNames = profile.serverNames
                    }
                    self.deliver(.success(()), to: completion)
                } catch {
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

    /// Measures every node of the group. Needs a running core. Returns node name to delay in ms (-1 when it failed).
    public func measureDelays(completion: @escaping (Result<[String: Int], Error>) -> Void) {
        queue.async {
            do {
                let group = try self.client.proxies(group: MihomoProxyController.groupName)
                var delays: [String: Int] = [:]
                for node in group.nodes {
                    delays[node.name] = try self.client.testDelay(proxy: node.name, timeoutMilliseconds: 5000)
                }
                self.deliver(.success(delays), to: completion)
            } catch {
                self.deliver(.failure(error), to: completion)
            }
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
