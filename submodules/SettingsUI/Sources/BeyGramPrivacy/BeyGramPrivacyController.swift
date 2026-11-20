import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit
import BeyGramStealth

private enum BeyGramPrivacySwitch {
    case hideTyping
    case noReadReceipts
    case hideOnline
    case serverScheduledSend
}

private final class BeyGramPrivacyArguments {
    let setMasterEnabled: (Bool) -> Void
    let setSwitch: (BeyGramPrivacySwitch, Bool) -> Void
    let openDelayPicker: () -> Void
    let openHowItWorks: () -> Void

    init(
        setMasterEnabled: @escaping (Bool) -> Void,
        setSwitch: @escaping (BeyGramPrivacySwitch, Bool) -> Void,
        openDelayPicker: @escaping () -> Void,
        openHowItWorks: @escaping () -> Void
    ) {
        self.setMasterEnabled = setMasterEnabled
        self.setSwitch = setSwitch
        self.openDelayPicker = openDelayPicker
        self.openHowItWorks = openHowItWorks
    }
}

private enum BeyGramPrivacySection: Int32 {
    case master
    case switches
    case schedule
    case details
}

private enum BeyGramPrivacyEntry: ItemListNodeEntry {
    case masterSwitch(PresentationTheme, String, Bool)
    case masterInfo(PresentationTheme, String)
    case switchesHeader(PresentationTheme, String)
    case hideTyping(PresentationTheme, String, Bool, Bool)
    case noReadReceipts(PresentationTheme, String, Bool, Bool)
    case hideOnline(PresentationTheme, String, Bool, Bool)
    case scheduleHeader(PresentationTheme, String)
    case scheduleSwitch(PresentationTheme, String, Bool, Bool)
    case scheduleDelayPicker(PresentationTheme, String, String, Bool)
    case scheduleRestrictions(PresentationTheme, String)
    case howItWorks(PresentationTheme, String)
    case disclaimer(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .masterSwitch, .masterInfo:
            return BeyGramPrivacySection.master.rawValue
        case .switchesHeader, .hideTyping, .noReadReceipts, .hideOnline:
            return BeyGramPrivacySection.switches.rawValue
        case .scheduleHeader, .scheduleSwitch, .scheduleDelayPicker, .scheduleRestrictions:
            return BeyGramPrivacySection.schedule.rawValue
        case .howItWorks, .disclaimer:
            return BeyGramPrivacySection.details.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .masterSwitch: return 0
        case .masterInfo: return 1
        case .switchesHeader: return 2
        case .hideTyping: return 3
        case .noReadReceipts: return 4
        case .hideOnline: return 5
        case .scheduleHeader: return 6
        case .scheduleSwitch: return 7
        case .scheduleDelayPicker: return 8
        case .scheduleRestrictions: return 9
        case .howItWorks: return 10
        case .disclaimer: return 11
        }
    }

    static func == (lhs: BeyGramPrivacyEntry, rhs: BeyGramPrivacyEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.masterSwitch(lt, lTitle, lVal), .masterSwitch(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.masterInfo(lt, lText), .masterInfo(rt, rText)):
            return lt === rt && lText == rText
        case let (.switchesHeader(lt, lText), .switchesHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.hideTyping(lt, lTitle, lVal, lEnabled), .hideTyping(rt, rTitle, rVal, rEnabled)):
            return lt === rt && lTitle == rTitle && lVal == rVal && lEnabled == rEnabled
        case let (.noReadReceipts(lt, lTitle, lVal, lEnabled), .noReadReceipts(rt, rTitle, rVal, rEnabled)):
            return lt === rt && lTitle == rTitle && lVal == rVal && lEnabled == rEnabled
        case let (.hideOnline(lt, lTitle, lVal, lEnabled), .hideOnline(rt, rTitle, rVal, rEnabled)):
            return lt === rt && lTitle == rTitle && lVal == rVal && lEnabled == rEnabled
        case let (.scheduleHeader(lt, lText), .scheduleHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.scheduleSwitch(lt, lTitle, lVal, lEnabled), .scheduleSwitch(rt, rTitle, rVal, rEnabled)):
            return lt === rt && lTitle == rTitle && lVal == rVal && lEnabled == rEnabled
        case let (.scheduleDelayPicker(lt, lTitle, lVal, lEnabled), .scheduleDelayPicker(rt, rTitle, rVal, rEnabled)):
            return lt === rt && lTitle == rTitle && lVal == rVal && lEnabled == rEnabled
        case let (.scheduleRestrictions(lt, lText), .scheduleRestrictions(rt, rText)):
            return lt === rt && lText == rText
        case let (.howItWorks(lt, lTitle), .howItWorks(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.disclaimer(lt, lText), .disclaimer(rt, rText)):
            return lt === rt && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: BeyGramPrivacyEntry, rhs: BeyGramPrivacyEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramPrivacyArguments
        switch self {
        case let .masterSwitch(_, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setMasterEnabled(newValue)
                }
            )
        case let .masterInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .switchesHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .hideTyping(_, title, value, enabled):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                enabled: enabled,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setSwitch(.hideTyping, newValue)
                }
            )
        case let .noReadReceipts(_, title, value, enabled):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                enabled: enabled,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setSwitch(.noReadReceipts, newValue)
                }
            )
        case let .hideOnline(_, title, value, enabled):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                enabled: enabled,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setSwitch(.hideOnline, newValue)
                }
            )
        case let .scheduleHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .scheduleSwitch(_, title, value, enabled):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                enabled: enabled,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setSwitch(.serverScheduledSend, newValue)
                }
            )
        case let .scheduleDelayPicker(_, title, value, enabled):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                enabled: enabled,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled {
                        arguments.openDelayPicker()
                    }
                }
            )
        case let .scheduleRestrictions(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .howItWorks(_, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: arguments.openHowItWorks
            )
        case let .disclaimer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func beyGramPrivacyEntries(
    presentationData: PresentationData,
    masterEnabled: Bool,
    settings: BeyGramStealthSettings
) -> [BeyGramPrivacyEntry] {
    let lang = presentationData.strings.primaryComponent.languageCode
    let l10n = BeyGramL10n.shared
    let theme = presentationData.theme

    var entries: [BeyGramPrivacyEntry] = []
    entries.append(.masterSwitch(theme, l10n.string(.privacyMasterTitle, languageCode: lang), masterEnabled))
    entries.append(.masterInfo(
        theme,
        masterEnabled
            ? l10n.string(.privacyMasterActiveSummary, languageCode: lang)
            : l10n.string(.privacyMasterInactiveSummary, languageCode: lang)
    ))

    entries.append(.switchesHeader(theme, l10n.string(.privacySectionHide, languageCode: lang).uppercased()))
    entries.append(.hideTyping(theme, l10n.string(.privacyHideTyping, languageCode: lang), settings.hideTyping, masterEnabled))
    entries.append(.noReadReceipts(theme, l10n.string(.privacyNoReadReceipts, languageCode: lang), settings.hideReadReceipts, masterEnabled))
    entries.append(.hideOnline(theme, l10n.string(.privacyHideOnline, languageCode: lang), settings.hideOnline, masterEnabled))

    entries.append(.scheduleHeader(theme, l10n.string(.privacySectionSend, languageCode: lang).uppercased()))
    entries.append(.scheduleSwitch(theme, l10n.string(.privacyDelayedSend, languageCode: lang), settings.serverScheduledSend, masterEnabled))
    let delayText = l10n.plural(.secondsShort, count: Int(settings.scheduledSendDelaySeconds), languageCode: lang)
    entries.append(.scheduleDelayPicker(
        theme,
        l10n.string(.privacyDelayPickerTitle, languageCode: lang),
        delayText,
        masterEnabled && settings.serverScheduledSend
    ))
    if masterEnabled && settings.serverScheduledSend {
        entries.append(.scheduleRestrictions(theme, l10n.string(.privacyRestrictionsSummary, languageCode: lang)))
    }

    entries.append(.howItWorks(theme, l10n.string(.privacyHowItWorksTitle, languageCode: lang)))
    entries.append(.disclaimer(theme, l10n.string(.privacyDisclaimer, languageCode: lang)))
    return entries
}

/// The privacy screen: the master switch of `BeyGramFeature.privacyPolicy` and the per-account stealth switches.
public func beyGramPrivacyController(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    let masterPromise = ValuePromise<Bool>(BeyGramSettings.shared.isEnabled(.privacyPolicy), ignoreRepeated: true)
    let settingsPromise = ValuePromise<BeyGramStealthSettings>(BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId), ignoreRepeated: true)

    var presentControllerImpl: ((ViewController, Any?) -> Void)?

    let arguments = BeyGramPrivacyArguments(
        setMasterEnabled: { value in
            BeyGramSettings.shared.setEnabled(value, for: .privacyPolicy)
            masterPromise.set(BeyGramSettings.shared.isEnabled(.privacyPolicy))
        },
        setSwitch: { option, value in
            BeyGramStealthStore.shared.update(accountPeerId: accountPeerId) { settings in
                switch option {
                case .hideTyping:
                    settings.hideTyping = value
                case .noReadReceipts:
                    settings.hideReadReceipts = value
                case .hideOnline:
                    settings.hideOnline = value
                case .serverScheduledSend:
                    settings.serverScheduledSend = value
                }
            }
            settingsPromise.set(BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId))
        },
        openDelayPicker: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.primaryComponent.languageCode
            let l10n = BeyGramL10n.shared
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            for seconds in BeyGramStealthSettings.scheduleDelayChoices {
                let title = l10n.plural(.secondsFull, count: Int(seconds), languageCode: lang)
                items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    BeyGramStealthStore.shared.update(accountPeerId: accountPeerId) { settings in
                        settings.scheduledSendDelaySeconds = seconds
                    }
                    settingsPromise.set(BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId))
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(actionSheet, nil)
        },
        openHowItWorks: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.primaryComponent.languageCode
            let l10n = BeyGramL10n.shared
            let alert = textAlertController(
                context: context,
                title: l10n.string(.privacyHowItWorksTitle, languageCode: lang),
                text: l10n.string(.privacyHowItWorksBody, languageCode: lang),
                actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                ]
            )
            presentControllerImpl?(alert, nil)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, masterPromise.get(), settingsPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, masterEnabled, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(BeyGramL10n.shared.string(.privacyTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: beyGramPrivacyEntries(presentationData: presentationData, masterEnabled: masterEnabled, settings: settings),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] next, context in
        controller?.present(next, in: .window(.root), with: context)
    }
    return controller
}
