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

/// Screen state that is not stored: the word being typed and the mode for the new rule.
private final class TriggerWordsDraft {
    var pattern = ""
    var mode: TriggerWordMode = .wholeWord
    var status: String?
}

private final class TriggerWordsSettingsArguments {
    let toggleFeature: (Bool) -> Void
    let setScope: (TriggerWordScope) -> Void
    let clearFeed: () -> Void
    let setDraftPattern: (String) -> Void
    let setDraftMode: (TriggerWordMode) -> Void
    let addRule: () -> Void
    let toggleRule: (UUID) -> Void
    let removeRule: (UUID) -> Void

    init(toggleFeature: @escaping (Bool) -> Void, setScope: @escaping (TriggerWordScope) -> Void, clearFeed: @escaping () -> Void,
         setDraftPattern: @escaping (String) -> Void, setDraftMode: @escaping (TriggerWordMode) -> Void, addRule: @escaping () -> Void,
         toggleRule: @escaping (UUID) -> Void, removeRule: @escaping (UUID) -> Void) {
        self.toggleFeature = toggleFeature
        self.setScope = setScope
        self.clearFeed = clearFeed
        self.setDraftPattern = setDraftPattern
        self.setDraftMode = setDraftMode
        self.addRule = addRule
        self.toggleRule = toggleRule
        self.removeRule = removeRule
    }
}

private enum TriggerWordsSettingsSection: Int32 {
    case feature
    case scope
    case add
    case rules
    case feed
}

/// Entries carry only plain values, so they can be compared. Rules are identified by their UUID.
private enum TriggerWordsSettingsEntry: ItemListNodeEntry, Equatable {
    case featureSwitch(Bool)
    case scopeHeader
    case scope(TriggerWordScope, Bool)
    case addHeader
    case draftPattern(String)
    case draftMode(TriggerWordMode, Bool)
    case addAction(Bool)
    case status(String)
    case rulesHeader
    case rule(Int, UUID, String, Bool)
    case ruleRemove(Int, UUID, String)
    case noRules
    case clearFeed(Int)

    var section: ItemListSectionId {
        switch self {
        case .featureSwitch:
            return TriggerWordsSettingsSection.feature.rawValue
        case .scopeHeader, .scope:
            return TriggerWordsSettingsSection.scope.rawValue
        case .addHeader, .draftPattern, .draftMode, .addAction, .status:
            return TriggerWordsSettingsSection.add.rawValue
        case .rulesHeader, .rule, .ruleRemove, .noRules:
            return TriggerWordsSettingsSection.rules.rawValue
        case .clearFeed:
            return TriggerWordsSettingsSection.feed.rawValue
        }
    }

    /// Stable ids: fixed rows use small numbers; a rule's rows use its position in the list, so the ids
    /// do not depend on per-process hashing.
    var stableId: Int64 {
        switch self {
        case .featureSwitch: return 0
        case .scopeHeader: return 1
        case .scope(.onlyMutedChats, _): return 2
        case .scope(.allChats, _): return 3
        case .addHeader: return 10
        case .draftPattern: return 11
        case .draftMode(.wholeWord, _): return 12
        case .draftMode(.anywhere, _): return 13
        case .addAction: return 14
        case .status: return 15
        case .rulesHeader: return 20
        case .noRules: return 21
        case let .rule(index, _, _, _): return 1000 + Int64(index) * 2
        case let .ruleRemove(index, _, _): return 1000 + Int64(index) * 2 + 1
        case .clearFeed: return 30
        }
    }

    static func < (lhs: TriggerWordsSettingsEntry, rhs: TriggerWordsSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TriggerWordsSettingsArguments
        switch self {
        case let .featureSwitch(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Trigger words", value: value, type: .regular, enabled: true, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.toggleFeature(newValue)
            })
        case .scopeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Check messages in", sectionId: self.section)
        case let .scope(scope, selected):
            let title = scope == .onlyMutedChats ? "Only muted chats" : "All chats"
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setScope(scope)
            })
        case .addHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Add a word", sectionId: self.section)
        case let .draftPattern(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "", textColor: .black), text: text, placeholder: "Word or phrase", type: .regular(capitalization: false, autocorrection: false), spacing: 0.0, clearType: .always, maxLength: TriggerWordRule.maxPatternLength, enabled: true, sectionId: self.section, textUpdated: { updated in
                arguments.setDraftPattern(updated)
            }, action: {})
        case let .draftMode(mode, selected):
            let title = mode == .wholeWord ? "Whole word" : "Anywhere in text"
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setDraftMode(mode)
            })
        case let .addAction(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Add word", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addRule()
            })
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .rulesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Words", sectionId: self.section)
        case let .rule(_, id, text, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: enabled ? .neutral : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.toggleRule(id)
            })
        case let .ruleRemove(_, id, text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Remove \(text)", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.removeRule(id)
            })
        case .noRules:
            return ItemListTextItem(presentationData: presentationData, text: .plain("No trigger words yet."), sectionId: self.section)
        case let .clearFeed(count):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Clear feed (\(count))", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearFeed()
            })
        }
    }
}

private func statusText(for error: TriggerWordValidationError) -> String {
    switch error {
    case .emptyPattern: return "The word is empty."
    case .patternTooLong: return "The word is longer than \(TriggerWordRule.maxPatternLength) characters."
    case .tooManyRules: return "No more than \(TriggerWordRule.maxRules) words."
    }
}

private func triggerWordsSettingsEntries(store: TriggerWordsStore, settings: BeyGramSettings, draft: TriggerWordsDraft) -> [TriggerWordsSettingsEntry] {
    var entries: [TriggerWordsSettingsEntry] = []
    entries.append(.featureSwitch(settings.isEnabled(.triggerWords)))
    entries.append(.scopeHeader)
    entries.append(.scope(.onlyMutedChats, store.state.scope == .onlyMutedChats))
    entries.append(.scope(.allChats, store.state.scope == .allChats))
    entries.append(.addHeader)
    entries.append(.draftPattern(draft.pattern))
    entries.append(.draftMode(.wholeWord, draft.mode == .wholeWord))
    entries.append(.draftMode(.anywhere, draft.mode == .anywhere))
    let trimmed = draft.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    entries.append(.addAction(!trimmed.isEmpty))
    if let status = draft.status {
        entries.append(.status(status))
    }
    entries.append(.rulesHeader)
    if store.state.rules.isEmpty {
        entries.append(.noRules)
    } else {
        for (index, rule) in store.state.rules.enumerated() {
            let mode = rule.mode == .wholeWord ? "whole word" : "anywhere in text"
            let caption = "\(rule.pattern) · \(mode)"
            entries.append(.rule(index, rule.id, rule.isEnabled ? caption : caption + " · off", rule.isEnabled))
            entries.append(.ruleRemove(index, rule.id, rule.pattern))
        }
    }
    if !store.state.mentions.isEmpty {
        entries.append(.clearFeed(store.state.mentions.count))
    }
    return entries
}

/// Settings screen for trigger words: the feature switch, the scope, adding words, enabling and removing them, and clearing the feed.
/// Editing a word's text means removing it and adding it again.
public func triggerWordsSettingsController(context: AccountContext) -> ViewController {
    let store = TriggerWordsStore.shared
    let settings = BeyGramSettings.shared
    let draft = TriggerWordsDraft()
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
    }, setDraftPattern: { text in
        // Typing does not re-render: the field keeps its own text.
        draft.pattern = text
        draft.status = nil
    }, setDraftMode: { mode in
        draft.mode = mode
        bump()
    }, addRule: {
        let trimmed = draft.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = TriggerWordRule(pattern: trimmed, mode: draft.mode)
        if let error = store.upsertRule(rule) {
            draft.status = statusText(for: error)
        } else {
            draft.pattern = ""
            draft.status = nil
        }
        bump()
    }, toggleRule: { id in
        guard var rule = store.state.rules.first(where: { $0.id == id }) else {
            return
        }
        rule.isEnabled.toggle()
        _ = store.upsertRule(rule)
        bump()
    }, removeRule: { id in
        store.removeRule(id: id)
        bump()
    })

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
        |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Trigger words"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: triggerWordsSettingsEntries(store: store, settings: settings, draft: draft), style: .blocks)
            return (controllerState, (listState, arguments))
        }

    return ItemListController(context: context, state: signal)
}
