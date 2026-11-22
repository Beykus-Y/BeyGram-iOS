import Foundation
internal import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit
import BeyGramStealth


func _internal_markAllChatsAsRead(postbox: Postbox, network: Network, stateManager: AccountStateManager) -> Signal<Void, NoError> {
    return network.request(Api.functions.messages.getDialogUnreadMarks(flags: 0, parentPeer: nil))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<[Api.DialogPeer]?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<Void, NoError> in
        guard let result = result else {
            return .complete()
        }
        
        return postbox.transaction { transaction -> Signal<Void, NoError> in
            var signals: [Signal<Void, NoError>] = []
            for peer in result {
                switch peer {
                    case let .dialogPeer(dialogPeerData):
                        let peer = dialogPeerData.peer
                        let peerId = peer.peerId
                        // BeyGram stealth: with read receipts hidden for this chat, it is not marked read on the server.
                        if !BeyGramStealthHooks.allows(.readHistory, accountPeerId: stateManager.accountPeerId.toInt64(), chatPeerId: peerId.toInt64()) {
                            continue
                        }
                        if peerId.namespace == Namespaces.Peer.CloudChannel {
                            if let inputChannel = transaction.getPeer(peerId).flatMap(apiInputChannel) {
                                signals.append(network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: Int32.max - 1))
                                |> `catch` { _ -> Signal<Api.Bool, NoError> in
                                    return .single(.boolFalse)
                                }
                                |> mapToSignal { _ -> Signal<Void, NoError> in
                                    return .complete()
                                })
                            }
                        } else if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup {
                            if let inputPeer = transaction.getPeer(peerId).flatMap(apiInputPeer) {
                                signals.append(network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: Int32.max - 1))
                                |> map(Optional.init)
                                |> `catch` { _ -> Signal<Api.messages.AffectedMessages?, NoError> in
                                    return .single(nil)
                                }
                                |> mapToSignal { result -> Signal<Void, NoError> in
                                    if let result = result {
                                        switch result {
                                            case let .affectedMessages(affectedMessagesData):
                                                let (pts, ptsCount) = (affectedMessagesData.pts, affectedMessagesData.ptsCount)
                                                stateManager.addUpdateGroups([.updatePts(pts: pts, ptsCount: ptsCount)])
                                        }
                                    }
                                    return .complete()
                                })
                            }
                        } else {
                            assertionFailure()
                        }
                    case .dialogPeerCommunity:
                        break
                    case .dialogPeerFolder:
                        assertionFailure()
                }
            }
            
            let applyLocally = postbox.transaction { transaction -> Void in
                
            }
            
            return combineLatest(signals)
            |> mapToSignal { _ -> Signal<Void, NoError> in
                return .complete()
            }
            |> then(applyLocally)
        } |> switchToLatest
    }
}
