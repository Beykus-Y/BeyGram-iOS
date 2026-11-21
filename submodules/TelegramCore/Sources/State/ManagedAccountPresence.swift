import BeyGramStealth
import Foundation
internal import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    private let accountPeerId: PeerId
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    private var wasOnline: Bool = false
    private var stealthSettingsObserver: NSObjectProtocol?
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, accountPeerId: PeerId) {
        self.queue = queue
        self.network = network
        self.accountPeerId = accountPeerId
        
        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            if self.wasOnline != value {
                self.wasOnline = value
                self.updatePresence(value)
            }
        })
        self.observeStealthSettings()
    }
    
    /// "Hide online" applies at once: while the account is requested online, the presence is evaluated again when the setting
    /// changes. Without this, a change waited for the next presence change or the 30-second refresh.
    private func observeStealthSettings() {
        let accountPeerId = self.accountPeerId.toInt64()
        let queue = self.queue
        self.stealthSettingsObserver = NotificationCenter.default.addObserver(forName: BeyGramStealthStore.didChangeNotification, object: nil, queue: nil, using: { notification in
            // The notification can come from any thread, so the presence work is handed to the presence queue.
            guard let changedAccountPeerId = notification.userInfo?[BeyGramStealthStore.accountPeerIdUserInfoKey] as? Int64, changedAccountPeerId == accountPeerId else {
                return
            }
            queue.justDispatch { [weak self] in
                guard let strongSelf = self, strongSelf.wasOnline else {
                    return
                }
                strongSelf.updatePresence(true)
            }
        })
    }

    deinit {
        assert(self.queue.isCurrent())
        if let stealthSettingsObserver = self.stealthSettingsObserver {
            NotificationCenter.default.removeObserver(stealthSettingsObserver)
        }
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
    }
    
    private func updatePresence(_ requestedOnline: Bool) {
        // BeyGram stealth: "hide online" keeps the account offline (submodules/BeyGramStealth).
        let isOnline = requestedOnline && BeyGramStealthHooks.allows(.onlinePresence, accountPeerId: self.accountPeerId.toInt64(), chatPeerId: nil)
        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else if requestedOnline {
            // Re-assert offline periodically while foregrounded with hide-online active so server-side activity does not leave the account online.
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, accountPeerId: PeerId) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network, accountPeerId: accountPeerId)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
