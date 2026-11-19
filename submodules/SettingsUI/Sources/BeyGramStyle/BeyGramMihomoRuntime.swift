import Foundation
import SwiftSignalKit
import TelegramCore
import BeyGramProxy

/// Connects the Mihomo core to Telegram's own SOCKS5 proxy settings.
///
/// Only the BeyGram Mihomo screen calls this, and that screen is reachable only while the
/// `mihomoProxy` flag is on. Telegram's proxy settings are saved before the first connect and
/// restored on disconnect. Until the core archive is linked, the controller uses the unlinked
/// driver, so a connect fails with a clear message. See submodules/BeyGramProxy/README.md.
public final class BeyGramMihomoRuntime {
    public static let shared = BeyGramMihomoRuntime()

    public let controller: MihomoProxyController

    private init() {
        let directory = BeyGramMihomoRuntime.supportDirectory()
        self.controller = MihomoProxyController(
            client: MihomoCoreClient(driver: UnlinkedMihomoCoreDriver()),
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
                        }
                        completion(.failure(error))
                }
            }
        })
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
