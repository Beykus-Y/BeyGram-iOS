import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import BeyGramKit
import BeyGramProxy

// The screen that drives the Mihomo core: connect or disconnect, the subscription, the node in use,
// and delay checks. It is opened only from the proxy list, and only while the mihomoProxy flag is on.

private struct BeyGramMihomoScreenState: Equatable {
    var subscriptionText: String
    var isRunning: Bool
    var busy: Bool = false
    var serverNames: [String]
    var selectedNode: String?
    var delays: [String: Int] = [:]
    var message: String?
}

private final class BeyGramMihomoScreenArguments {
    let toggleConnection: (Bool) -> Void
    let subscriptionUpdated: (String) -> Void
    let saveSubscription: () -> Void
    let selectNode: (String) -> Void
    let measureDelays: () -> Void

    init(toggleConnection: @escaping (Bool) -> Void, subscriptionUpdated: @escaping (String) -> Void, saveSubscription: @escaping () -> Void, selectNode: @escaping (String) -> Void, measureDelays: @escaping () -> Void) {
        self.toggleConnection = toggleConnection
        self.subscriptionUpdated = subscriptionUpdated
        self.saveSubscription = saveSubscription
        self.selectNode = selectNode
        self.measureDelays = measureDelays
    }
}

private enum BeyGramMihomoSection: Int32 {
    case connection
    case subscription
    case nodes
    case note
}

private enum BeyGramMihomoEntryId: Hashable {
    case index(Int)
    case node(String)
}

private enum BeyGramMihomoEntry: Equatable, ItemListNodeEntry {
    case toggle(String, Bool, Bool)
    case status(String)
    case subscriptionHeader(String)
    case subscriptionField(String, String, String)
    case saveSubscription(String)
    case nodesHeader(String)
    case node(Int, String, String?, Bool)
    case measure(String)
    case note(String)

    var section: ItemListSectionId {
        switch self {
            case .toggle, .status:
                return BeyGramMihomoSection.connection.rawValue
            case .subscriptionHeader, .subscriptionField, .saveSubscription:
                return BeyGramMihomoSection.subscription.rawValue
            case .nodesHeader, .node, .measure:
                return BeyGramMihomoSection.nodes.rawValue
            case .note:
                return BeyGramMihomoSection.note.rawValue
        }
    }

    var stableId: BeyGramMihomoEntryId {
        switch self {
            case .toggle:
                return .index(0)
            case .status:
                return .index(1)
            case .subscriptionHeader:
                return .index(2)
            case .subscriptionField:
                return .index(3)
            case .saveSubscription:
                return .index(4)
            case .nodesHeader:
                return .index(5)
            case let .node(_, name, _, _):
                return .node(name)
            case .measure:
                return .index(6)
            case .note:
                return .index(7)
        }
    }

    /// The display order. Sections follow each other, and nodes keep the order of the subscription.
    private var order: Int {
        switch self {
            case .toggle:
                return 0
            case .status:
                return 1
            case .subscriptionHeader:
                return 2
            case .subscriptionField:
                return 3
            case .saveSubscription:
                return 4
            case .nodesHeader:
                return 5
            case let .node(index, _, _, _):
                return 100 + index
            case .measure:
                return 100000
            case .note:
                return 100001
        }
    }

    static func <(lhs: BeyGramMihomoEntry, rhs: BeyGramMihomoEntry) -> Bool {
        return lhs.order < rhs.order
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramMihomoScreenArguments
        switch self {
            case let .toggle(title, value, enabled):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enableInteractiveChanges: enabled, enabled: enabled, sectionId: self.section, style: .blocks, updated: { newValue in
                    arguments.toggleConnection(newValue)
                })
            case let .status(text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .subscriptionHeader(text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .subscriptionField(title, text, placeholder):
                return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: text, placeholder: placeholder, sectionId: self.section, textUpdated: { newText in
                    arguments.subscriptionUpdated(newText)
                }, action: {
                    arguments.saveSubscription()
                })
            case let .saveSubscription(title):
                return ProxySettingsActionItem(presentationData: presentationData, systemStyle: .glass, title: title, sectionId: self.section, editing: false, action: {
                    arguments.saveSubscription()
                })
            case let .nodesHeader(text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .node(_, name, subtitle, checked):
                return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: name, subtitle: subtitle, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.selectNode(name)
                })
            case let .measure(title):
                return ProxySettingsActionItem(presentationData: presentationData, systemStyle: .glass, title: title, sectionId: self.section, editing: false, action: {
                    arguments.measureDelays()
                })
            case let .note(text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func beyGramMihomoStatusText(_ state: BeyGramMihomoScreenState, isRussian: Bool) -> String {
    var lines: [String] = []
    if state.busy {
        lines.append(isRussian ? "Подождите…" : "Please wait…")
    } else if state.isRunning {
        lines.append(isRussian ? "Работает" : "Running")
    } else {
        lines.append(isRussian ? "Остановлен" : "Stopped")
    }
    if let selectedNode = state.selectedNode {
        lines.append((isRussian ? "Узел: " : "Node: ") + selectedNode)
    }
    if let message = state.message {
        lines.append(message)
    }
    return lines.joined(separator: "\n")
}

private func beyGramMihomoDelayText(_ delay: Int?, isRussian: Bool) -> String? {
    guard let delay = delay else {
        return nil
    }
    if delay < 0 {
        return isRussian ? "недоступен" : "unavailable"
    }
    return "\(delay) " + (isRussian ? "мс" : "ms")
}

private func beyGramMihomoEntries(state: BeyGramMihomoScreenState, isRussian: Bool) -> [BeyGramMihomoEntry] {
    var entries: [BeyGramMihomoEntry] = []
    entries.append(.toggle(isRussian ? "Подключить прокси" : "Connect proxy", state.isRunning, !state.busy))
    entries.append(.status(beyGramMihomoStatusText(state, isRussian: isRussian)))
    entries.append(.subscriptionHeader(isRussian ? "Подписка" : "Subscription"))
    entries.append(.subscriptionField(isRussian ? "Ссылка" : "Link", state.subscriptionText, isRussian ? "https:// или текст подписки" : "https:// or subscription text"))
    entries.append(.saveSubscription(isRussian ? "Сохранить и обновить" : "Save and refresh"))
    if !state.serverNames.isEmpty {
        entries.append(.nodesHeader(isRussian ? "Узлы" : "Nodes"))
        for (index, name) in state.serverNames.enumerated() {
            entries.append(.node(index, name, beyGramMihomoDelayText(state.delays[name], isRussian: isRussian), state.selectedNode == name))
        }
        if state.isRunning {
            entries.append(.measure(isRussian ? "Проверить задержку" : "Check delays"))
        }
    }
    entries.append(.note(isRussian ? "Экспериментальная функция. Выключена по умолчанию." : "Experimental feature. Off by default."))
    return entries
}

public func beyGramMihomoController(accountManager: AccountManager<TelegramAccountManagerTypes>, presentationData: PresentationData, updatedPresentationData: Signal<PresentationData, NoError>) -> ViewController {
    let runtime = BeyGramMihomoRuntime.shared
    let isRussian = presentationData.strings.primaryComponent.languageCode == "ru"
    let initial = runtime.controller.currentState
    let stateValue = Atomic(value: BeyGramMihomoScreenState(subscriptionText: initial.subscriptionSource ?? "", isRunning: initial.isRunning, serverNames: initial.serverNames, selectedNode: initial.selectedNode))
    let statePromise = ValuePromise<BeyGramMihomoScreenState>(stateValue.with { $0 })
    let mutate: ((inout BeyGramMihomoScreenState) -> Void) -> Void = { change in
        let value = stateValue.modify { current in
            var next = current
            change(&next)
            return next
        }
        statePromise.set(value)
    }

    let arguments = BeyGramMihomoScreenArguments(toggleConnection: { enable in
        if stateValue.with({ $0 }).busy {
            return
        }
        mutate { state in
            state.busy = true
            state.message = nil
        }
        if enable {
            runtime.connect(accountManager: accountManager, completion: { result in
                switch result {
                    case .success:
                        mutate { state in
                            state.busy = false
                            state.isRunning = true
                        }
                    case let .failure(error):
                        mutate { state in
                            state.busy = false
                            state.isRunning = false
                            state.message = error.localizedDescription
                        }
                }
            })
        } else {
            runtime.disconnect(accountManager: accountManager, completion: { result in
                mutate { state in
                    state.busy = false
                    state.isRunning = false
                    if case let .failure(error) = result {
                        state.message = error.localizedDescription
                    }
                }
            })
        }
    }, subscriptionUpdated: { text in
        mutate { state in
            state.subscriptionText = text
        }
    }, saveSubscription: {
        let current = stateValue.with { $0 }
        if current.busy {
            return
        }
        mutate { state in
            state.busy = true
            state.message = nil
        }
        runtime.controller.saveSubscription(current.subscriptionText, completion: { result in
            switch result {
                case let .success(names):
                    mutate { state in
                        state.busy = false
                        state.serverNames = names
                        state.selectedNode = runtime.controller.currentState.selectedNode
                        state.delays = [:]
                        state.message = (isRussian ? "Узлов: " : "Nodes: ") + "\(names.count)"
                    }
                case let .failure(error):
                    mutate { state in
                        state.busy = false
                        state.message = error.localizedDescription
                    }
            }
        })
    }, selectNode: { name in
        if stateValue.with({ $0 }).busy {
            return
        }
        runtime.controller.selectNode(name, completion: { result in
            switch result {
                case .success:
                    mutate { state in
                        state.selectedNode = name
                        state.message = nil
                    }
                case let .failure(error):
                    mutate { state in
                        state.message = error.localizedDescription
                    }
            }
        })
    }, measureDelays: {
        if stateValue.with({ $0 }).busy {
            return
        }
        mutate { state in
            state.busy = true
            state.message = nil
        }
        runtime.controller.measureDelays(completion: { result in
            switch result {
                case let .success(delays):
                    mutate { state in
                        state.busy = false
                        state.delays = delays
                    }
                case let .failure(error):
                    mutate { state in
                        state.busy = false
                        state.message = error.localizedDescription
                    }
            }
        })
    })

    let signal = combineLatest(updatedPresentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let languageIsRussian = presentationData.strings.primaryComponent.languageCode == "ru"
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(BeyGramFeature.mihomoProxy.title(languageCode: presentationData.strings.primaryComponent.languageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: beyGramMihomoEntries(state: state, isRussian: languageIsRussian), style: .blocks, ensureVisibleItemTag: nil)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: updatedPresentationData |> map(ItemListPresentationData.init(_:)), state: signal, tabBarItem: nil)
}
