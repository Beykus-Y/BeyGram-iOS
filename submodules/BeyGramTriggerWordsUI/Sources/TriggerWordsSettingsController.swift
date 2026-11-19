import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit
import BeyGramTriggerWords

private final class TriggerWordsSettingsArguments {
    let toggleFeature: (Bool) -> Void
    let setScope: (TriggerWordScope) -> Void
    let clearFeed: () -> Void

    init(toggleFeature: @escaping (Bool) -> Void, setScope: @escaping (TriggerWordScope) -> Void, clearFeed: @escaping () -> Void) {
        self.toggleFeature = toggleFeature
        self.setScope = setScope
        self.clearFeed = clearFeed
    }
}

private enum TriggerWordsSettingsSection: Int32 {
    case feature
    case scope
    case rules
    case feed
}

private enum TriggerWordsSettingsEntry: ItemListNodeEntry, Equatable {
    case featureSwitch(Bool)
    case scopeHeader
    case scope(TriggerWordScope, Bool)
    case rulesHeader
    case rule(Int, String)
    case noRules
    case clearFeed(Int)

    var section: ItemListSectionId {
        switch self {
        case .featureSwitch:
            return TriggerWordsSettingsSection.feature.rawValue
        case .scopeHeader, .scope:
            return TriggerWordsSettingsSection.scope.rawValue
        case .rulesHeader, .rule, .noRules:
            return TriggerWordsSettingsSection.rules.rawValue
        case .clearFeed:
            return TriggerWordsSettingsSection.feed.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .featureSwitch: return 0
        case .scopeHeader: return 1
        case .scope(.onlyMutedChats, _): return 2
        case .scope(.allChats, _): return 3
        case .rulesHeader: return 4
        case let .rule(index, _): return 100 + Int64(index)
        case .noRules: return 99
        case .clearFeed: return 5
        }
    }

    static func < (lhs: TriggerWordsSettingsEntry, rhs: TriggerWordsSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TriggerWordsSettingsArguments
        switch self {
        case let .featureSwitch(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Trigger words", value: value, type: .regular, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFeature(value)
            })
        case .scopeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Check messages in", sectionId: self.section)
        case let .scope(scope, selected):
            let title = scope == .onlyMutedChats ? "Only muted chats" : "All chats"
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setScope(scope)
            })
        case .rulesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Words", sectionId: self.section)
        case let .rule(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .noRules:
            return ItemListTextItem(presentationData: presentationData, text: .plain("No trigger words yet."), sectionId: self.section)
        case let .clearFeed(count):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Clear feed (\(count))", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearFeed()
            })
        }
    }
}

private func triggerWordsSettingsEntries(store: TriggerWordsStore, settings: BeyGramSettings) -> [TriggerWordsSettingsEntry] {
    var entries: [TriggerWordsSettingsEntry] = []
    entries.append(.featureSwitch(settings.isEnabled(.triggerWords)))
    entries.append(.scopeHeader)
    entries.append(.scope(.onlyMutedChats, store.state.scope == .onlyMutedChats))
    entries.append(.scope(.allChats, store.state.scope == .allChats))
    entries.append(.rulesHeader)
    if store.state.rules.isEmpty {
        entries.append(.noRules)
    } else {
        for (index, rule) in store.state.rules.enumerated() {
            let mode = rule.mode == .wholeWord ? "whole word" : "anywhere in text"
            entries.append(.rule(index, "\(rule.pattern) · \(mode)\(rule.isEnabled ? "" : " · off")"))
        }
    }
    if !store.state.mentions.isEmpty {
        entries.append(.clearFeed(store.state.mentions.count))
    }
    return entries
}

/// Settings screen for trigger words. The feature flag and the store are shared across the app.
/// Rules can be listed here; adding and editing them is not implemented yet.
public func triggerWordsSettingsController(context: AccountContext) -> ViewController {
    let store = TriggerWordsStore.shared
    let settings = BeyGramSettings.shared
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let bump: () -> Void = {
        counter += 1
        revision.set(counter)
    }

    let arguments = TriggerWordsSettingsArguments(toggleFeature: { value in
        settings.setEnabled(value, for: .triggerWords)
        bump()
    }, setScope: { scope in
        store.setScope(scope)
        bump()
    }, clearFeed: {
        store.clearFeed()
        bump()
    })

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
        |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Trigger words"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: triggerWordsSettingsEntries(store: store, settings: settings), style: .blocks)
            return (controllerState, (listState, arguments))
        }

    return ItemListController(context: context, state: signal)
}
