import Foundation
import UIKit
import UserNotifications
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit
import BeyGramTriggerWords

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

    init(
        toggleFeature: @escaping (Bool) -> Void,
        setScope: @escaping (TriggerWordScope) -> Void,
        clearFeed: @escaping () -> Void,
        setDraftPattern: @escaping (String) -> Void,
        setDraftMode: @escaping (TriggerWordMode) -> Void,
        addRule: @escaping () -> Void,
        toggleRule: @escaping (UUID) -> Void,
        removeRule: @escaping (UUID) -> Void
    ) {
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

private enum TriggerWordsSettingsEntry: ItemListNodeEntry, Equatable {
    case featureSwitch(PresentationTheme, String, Bool)
    case scopeHeader(PresentationTheme, String)
    case scope(PresentationTheme, TriggerWordScope, String, Bool)
    case addHeader(PresentationTheme, String)
    case draftPattern(PresentationTheme, String, String)
    case draftMode(PresentationTheme, TriggerWordMode, String, Bool)
    case addAction(PresentationTheme, String, Bool)
    case status(PresentationTheme, String)
    case rulesHeader(PresentationTheme, String)
    case rule(Int, PresentationTheme, UUID, String, Bool)
    case ruleRemove(Int, PresentationTheme, UUID, String)
    case noRules(PresentationTheme, String)
    case feedHeader(PresentationTheme, String)
    case mention(Int, PresentationTheme, String, String, String)
    case emptyFeed(PresentationTheme, String)
    case clearFeed(PresentationTheme, String)

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
        case .feedHeader, .mention, .emptyFeed, .clearFeed:
            return TriggerWordsSettingsSection.feed.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .featureSwitch: return 0
        case .scopeHeader: return 1
        case .scope(_, .onlyMutedChats, _, _): return 2
        case .scope(_, .allChats, _, _): return 3
        case .addHeader: return 10
        case .draftPattern: return 11
        case .draftMode(_, .wholeWord, _, _): return 12
        case .draftMode(_, .anywhere, _, _): return 13
        case .addAction: return 14
        case .status: return 15
        case .rulesHeader: return 20
        case .noRules: return 21
        case let .rule(index, _, _, _, _): return 1000 + Int64(index) * 2
        case let .ruleRemove(index, _, _, _): return 1000 + Int64(index) * 2 + 1
        case .feedHeader: return 5000
        case .emptyFeed: return 5001
        case let .mention(index, _, _, _, _): return 5010 + Int64(index)
        case .clearFeed: return 9000
        }
    }

    static func == (lhs: TriggerWordsSettingsEntry, rhs: TriggerWordsSettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.featureSwitch(lt, lTitle, lVal), .featureSwitch(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.scopeHeader(lt, lText), .scopeHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.scope(lt, lScope, lTitle, lSel), .scope(rt, rScope, rTitle, rSel)):
            return lt === rt && lScope == rScope && lTitle == rTitle && lSel == rSel
        case let (.addHeader(lt, lText), .addHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.draftPattern(lt, lText, lPlaceholder), .draftPattern(rt, rText, rPlaceholder)):
            return lt === rt && lText == rText && lPlaceholder == rPlaceholder
        case let (.draftMode(lt, lMode, lTitle, lSel), .draftMode(rt, rMode, rTitle, rSel)):
            return lt === rt && lMode == rMode && lTitle == rTitle && lSel == rSel
        case let (.addAction(lt, lTitle, lEnabled), .addAction(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.status(lt, lText), .status(rt, rText)):
            return lt === rt && lText == rText
        case let (.rulesHeader(lt, lText), .rulesHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.rule(lIdx, lt, lId, lText, lEnabled), .rule(rIdx, rt, rId, rText, rEnabled)):
            return lIdx == rIdx && lt === rt && lId == rId && lText == rText && lEnabled == rEnabled
        case let (.ruleRemove(lIdx, lt, lId, lText), .ruleRemove(rIdx, rt, rId, rText)):
            return lIdx == rIdx && lt === rt && lId == rId && lText == rText
        case let (.noRules(lt, lText), .noRules(rt, rText)):
            return lt === rt && lText == rText
        case let (.feedHeader(lt, lText), .feedHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.mention(lIdx, lt, lId, lTitle, lLabel), .mention(rIdx, rt, rId, rTitle, rLabel)):
            return lIdx == rIdx && lt === rt && lId == rId && lTitle == rTitle && lLabel == rLabel
        case let (.emptyFeed(lt, lText), .emptyFeed(rt, rText)):
            return lt === rt && lText == rText
        case let (.clearFeed(lt, lTitle), .clearFeed(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        default:
            return false
        }
    }

    static func < (lhs: TriggerWordsSettingsEntry, rhs: TriggerWordsSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TriggerWordsSettingsArguments
        switch self {
        case let .featureSwitch(_, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                type: .regular,
                enabled: true,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.toggleFeature(newValue)
                }
            )
        case let .scopeHeader(_, text), let .addHeader(_, text), let .rulesHeader(_, text), let .feedHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .scope(_, scope, title, selected):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                style: .left,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    arguments.setScope(scope)
                }
            )
        case let .draftPattern(_, text, placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: "", textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: text,
                placeholder: placeholder,
                type: .regular(capitalization: false, autocorrection: false),
                spacing: 0.0,
                clearType: .always,
                maxLength: TriggerWordRule.maxPatternLength,
                enabled: true,
                sectionId: self.section,
                textUpdated: { updated in
                    arguments.setDraftPattern(updated)
                },
                action: {}
            )
        case let .draftMode(_, mode, title, selected):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                style: .left,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    arguments.setDraftMode(mode)
                }
            )
        case let .addAction(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.addRule() }
                }
            )
        case let .status(_, text), let .noRules(_, text), let .emptyFeed(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .rule(_, _, id, text, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: text,
                kind: enabled ? .neutral : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.toggleRule(id)
                }
            )
        case let .ruleRemove(_, _, id, text):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: text,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.removeRule(id)
                }
            )
        case let .mention(_, _, _, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .clearFeed(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: arguments.clearFeed
            )
        }
    }
}

private func validationMessage(for error: TriggerWordValidationError, languageCode: String?) -> String {
    let lang = BeyGramL10n.normalizeLanguageCode(languageCode)
    let isRu = lang == "ru"
    switch error {
    case .emptyPattern:
        return BeyGramL10n.shared.string(.triggerEmptyPatternStatus, languageCode: lang)
    case .patternTooLong:
        return isRu
            ? "Слово длиннее \(TriggerWordRule.maxPatternLength) символов."
            : "The word is longer than \(TriggerWordRule.maxPatternLength) characters."
    case .tooManyRules:
        return isRu
            ? "Не более \(TriggerWordRule.maxRules) правил."
            : "No more than \(TriggerWordRule.maxRules) rules."
    }
}

private func triggerWordsSettingsEntries(
    presentationData: PresentationData,
    store: TriggerWordsStore,
    settings: BeyGramSettings,
    draft: TriggerWordsDraft
) -> [TriggerWordsSettingsEntry] {
    let lang = presentationData.strings.primaryComponent.languageCode
    let l10n = BeyGramL10n.shared
    let theme = presentationData.theme
    var entries: [TriggerWordsSettingsEntry] = []

    entries.append(.featureSwitch(theme, l10n.string(.triggerEnable, languageCode: lang), settings.isEnabled(.triggerWords)))

    entries.append(.scopeHeader(theme, l10n.string(.triggerSectionScope, languageCode: lang).uppercased()))
    entries.append(.scope(theme, .onlyMutedChats, l10n.string(.triggerScopeMuted, languageCode: lang), store.state.scope == .onlyMutedChats))
    entries.append(.scope(theme, .allChats, l10n.string(.triggerScopeAll, languageCode: lang), store.state.scope == .allChats))

    entries.append(.addHeader(theme, l10n.string(.triggerSectionAdd, languageCode: lang).uppercased()))
    entries.append(.draftPattern(theme, draft.pattern, l10n.string(.triggerInputPlaceholder, languageCode: lang)))
    entries.append(.draftMode(theme, .wholeWord, l10n.string(.triggerModeWholeWord, languageCode: lang), draft.mode == .wholeWord))
    entries.append(.draftMode(theme, .anywhere, l10n.string(.triggerModeAnywhere, languageCode: lang), draft.mode == .anywhere))
    let trimmed = draft.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    entries.append(.addAction(theme, l10n.string(.triggerAddAction, languageCode: lang), !trimmed.isEmpty))
    if let status = draft.status {
        entries.append(.status(theme, status))
    }

    let rulesHeaderText = store.state.rules.isEmpty
        ? l10n.string(.triggerSectionRules, languageCode: lang).uppercased()
        : "\(l10n.string(.triggerSectionRules, languageCode: lang).uppercased()) (\(l10n.plural(.rulesCount, count: store.state.rules.count, languageCode: lang)))"
    entries.append(.rulesHeader(theme, rulesHeaderText))
    if store.state.rules.isEmpty {
        entries.append(.noRules(theme, l10n.string(.triggerNoRules, languageCode: lang)))
    } else {
        for (index, rule) in store.state.rules.enumerated() {
            let mode = rule.mode == .wholeWord
                ? l10n.string(.triggerModeWholeWord, languageCode: lang)
                : l10n.string(.triggerModeAnywhere, languageCode: lang)
            let stateText = rule.isEnabled ? mode : "\(mode) · \(l10n.string(.commonOff, languageCode: lang))"
            entries.append(.rule(index, theme, rule.id, "\(rule.pattern) · \(stateText)", rule.isEnabled))
            entries.append(.ruleRemove(index, theme, rule.id, "\(l10n.string(.commonDelete, languageCode: lang)) «\(rule.pattern)»"))
        }
    }

    entries.append(.feedHeader(theme, l10n.string(.triggerSectionFeed, languageCode: lang).uppercased()))
    if store.state.mentions.isEmpty {
        entries.append(.emptyFeed(theme, l10n.string(.triggerFeedEmpty, languageCode: lang)))
    } else {
        for (index, mention) in store.state.mentions.prefix(20).enumerated() {
            let title = mention.senderName ?? mention.matchedPattern
            let label = mention.text ?? mention.matchedPattern
            entries.append(.mention(index, theme, mention.id, title, label))
        }
        let clearTitle = "\(l10n.string(.triggerClearFeed, languageCode: lang)) (\(l10n.plural(.matchesCount, count: store.state.mentions.count, languageCode: lang)))"
        entries.append(.clearFeed(theme, clearTitle))
    }

    return entries
}

/// Settings screen for trigger words: feature toggle, scope, rules management, and matches feed.
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

    let arguments = TriggerWordsSettingsArguments(
        toggleFeature: { value in
            settings.setEnabled(value, for: .triggerWords)
            if value {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge], completionHandler: { _, _ in })
            }
            bump()
        },
        setScope: { scope in
            store.setScope(scope)
            bump()
        },
        clearFeed: {
            store.clearFeed()
            bump()
        },
        setDraftPattern: { text in
            draft.pattern = text
            draft.status = nil
        },
        setDraftMode: { mode in
            draft.mode = mode
            bump()
        },
        addRule: {
            let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.primaryComponent.languageCode
            let trimmed = draft.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            let rule = TriggerWordRule(pattern: trimmed, mode: draft.mode)
            if let error = store.upsertRule(rule) {
                draft.status = validationMessage(for: error, languageCode: lang)
            } else {
                draft.pattern = ""
                draft.status = BeyGramL10n.shared.string(.triggerAddedStatus, languageCode: lang)
            }
            bump()
        },
        toggleRule: { id in
            guard var rule = store.state.rules.first(where: { $0.id == id }) else {
                return
            }
            rule.isEnabled.toggle()
            _ = store.upsertRule(rule)
            bump()
        },
        removeRule: { id in
            store.removeRule(id: id)
            bump()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(BeyGramL10n.shared.string(.triggerTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: triggerWordsSettingsEntries(presentationData: presentationData, store: store, settings: settings, draft: draft),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
