import Foundation
import SwiftSignalKit
import TelegramCore
import BeyGramProxy

/// Connects the Mihomo core to Telegram's own SOCKS5 proxy settings.
///
/// Only the BeyGram Mihomo screen calls this, and that screen is reachable only while the
/// `mihomoProxy` flag is on. Telegram's proxy settings are saved before the first connect and
/// restored on disconnect or if the core fails to start. See submodules/BeyGramProxy/README.md.
public final class BeyGramMihomoRuntime {
    public static let shared = BeyGramMihomoRuntime()

    public let controller: MihomoProxyController
    private let runtimeLock = NSLock()
    private var attachedAccountManager: AccountManager<TelegramAccountManagerTypes>?
    private var resumeFailedBeforeAttach = false

    private init() {
        let directory = BeyGramMihomoRuntime.supportDirectory()
        self.controller = MihomoProxyController(
            client: MihomoCoreClient(driver: MihomoCgoDriver()),
            store: MihomoProxyStateStore(directory: directory),
            homeDirectory: directory.appendingPathComponent("core", isDirectory: true)
        )
    }

    /// Starts the core, then points Telegram at the loopback inlet. Completion runs on the main queue.
    public func connect(accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (Result<Void, Error>) -> Void) {
        let _ = (accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> take(1)
        |> deliverOnMainQueue).start(next: { sharedData in
            let current = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
            // Keep the first snapshot. A second connect must not store the loopback entry as the "before" state.
            var savedSnapshot = false
            if self.controller.currentState.telegramSettingsBeforeConnect == nil, let snapshot = try? JSONEncoder().encode(current) {
                self.controller.setTelegramSettingsBeforeConnect(snapshot)
                savedSnapshot = true
            }
            self.controller.start { result in
                switch result {
                    case .success:
                        self.pointTelegramAtInlet(accountManager: accountManager)
                        completion(.success(()))
                    case let .failure(error):
                        if savedSnapshot {
                            self.controller.setTelegramSettingsBeforeConnect(nil)
                        } else if self.controller.currentState.telegramSettingsBeforeConnect != nil {
                            self.restoreTelegramSettings(accountManager: accountManager)
                        }
                        completion(.failure(error))
                }
            }
        })
    }

    /// Called at app launch when the flag is on. Starts the core again if it was running at the last exit.
    public func resumeIfNeeded() {
        self.controller.resumeIfNeeded(completion: { [weak self] result in
            guard let self = self else {
                return
            }
            if case .failure = result {
                self.runtimeLock.lock()
                let accountManager = self.attachedAccountManager
                if accountManager == nil {
                    self.resumeFailedBeforeAttach = true
                }
                self.runtimeLock.unlock()
                if let accountManager = accountManager {
                    self.restoreTelegramSettings(accountManager: accountManager)
                }
            }
        })
    }

    /// Attaches the account manager once initialized so a failed launch resume or disabled flag
    /// never leaves Telegram pointing at a non-working loopback proxy.
    public func attachAccountManager(_ accountManager: AccountManager<TelegramAccountManagerTypes>, mihomoEnabled: Bool) {
        self.runtimeLock.lock()
        self.attachedAccountManager = accountManager
        let failedBeforeAttach = self.resumeFailedBeforeAttach
        self.resumeFailedBeforeAttach = false
        self.runtimeLock.unlock()

        if !mihomoEnabled {
            if self.controller.currentState.telegramSettingsBeforeConnect != nil {
                self.restoreTelegramSettings(accountManager: accountManager)
            }
            return
        }
        if failedBeforeAttach && !self.controller.currentState.isRunning && self.controller.currentState.telegramSettingsBeforeConnect != nil {
            self.restoreTelegramSettings(accountManager: accountManager)
        }
    }

    private let connectionDisposable = MetaDisposable()

    /// Feeds the connection state of an account to the controller (issue #141). A later call replaces the earlier one.
    public func observeTelegramConnection(_ state: Signal<AccountNetworkState, NoError>) {
        self.connectionDisposable.set((state
        |> map { state -> Bool in
            if case .connecting = state {
                return true
            }
            return false
        }
        |> distinctUntilChanged).start(next: { [weak self] isConnecting in
            self?.controller.telegramConnectionChanged(isConnecting: isConnecting)
        }))
    }

    /// Turns the automatic node switch on or off.
    public func setAutoSelect(_ enabled: Bool) {
        self.controller.setAutoSelect(enabled)
    }

    /// Stops the core, then gives Telegram back the proxy settings it had before the connect.
    public func disconnect(accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (Result<Void, Error>) -> Void) {
        self.controller.stop { result in
            self.restoreTelegramSettings(accountManager: accountManager)
            completion(result)
        }
    }

    /// The loopback entry that Telegram's proxy list shows while Mihomo is connected.
    static func inletServer(credentials: LoopbackCredentials) -> ProxyServerSettings {
        return ProxyServerSettings(host: MihomoProxyController.inletHost, port: MihomoProxyController.inletPort, connection: .socks5(username: credentials.username, password: credentials.password))
    }

    private func pointTelegramAtInlet(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        guard let credentials = try? LoopbackCredentialStore.loadOrCreate() else {
            return
        }
        let inlet = BeyGramMihomoRuntime.inletServer(credentials: credentials)
        let _ = updateProxySettingsInteractively(accountManager: accountManager, { current in
            var current = current
            if !current.servers.contains(inlet) {
                current.servers.append(inlet)
            }
            current.activeServer = inlet
            current.enabled = true
            return current
        }).start()
    }

    private func restoreTelegramSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        guard let data = self.controller.currentState.telegramSettingsBeforeConnect else {
            return
        }
        self.controller.setTelegramSettingsBeforeConnect(nil)
        guard let snapshot = try? JSONDecoder().decode(ProxySettings.self, from: data) else {
            return
        }
        let inlet = (try? LoopbackCredentialStore.loadOrCreate()).map { BeyGramMihomoRuntime.inletServer(credentials: $0) }
        let _ = updateProxySettingsInteractively(accountManager: accountManager, { current in
            var current = current
            if let inlet = inlet {
                current.servers.removeAll { $0 == inlet }
            }
            current.activeServer = snapshot.activeServer
            current.enabled = snapshot.enabled
            return current
        }).start()
    }

    private static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BeyGram/Mihomo", isDirectory: true)
    }
}
