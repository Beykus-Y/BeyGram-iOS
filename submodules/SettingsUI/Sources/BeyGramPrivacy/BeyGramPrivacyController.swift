import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit
import BeyGramStealth

/// The four switches of the privacy screen. The stored keys are set in `BeyGramStealthSettings` (Android names).
private enum BeyGramPrivacySwitch {
    case hideTyping
    case noReadReceipts
    case hideOnline
    case serverScheduledSend
}

private final class BeyGramPrivacyArguments {
    let setMasterEnabled: (Bool) -> Void
    let setSwitch: (BeyGramPrivacySwitch, Bool) -> Void
    let setScheduleDelay: (Int32) -> Void

    init(setMasterEnabled: @escaping (Bool) -> Void, setSwitch: @escaping (BeyGramPrivacySwitch, Bool) -> Void, setScheduleDelay: @escaping (Int32) -> Void) {
        self.setMasterEnabled = setMasterEnabled
        self.setSwitch = setSwitch
        self.setScheduleDelay = setScheduleDelay
    }
}

private enum BeyGramPrivacySection: Int32 {
    case master
    case switches
    case schedule
}

private enum BeyGramPrivacyEntry: ItemListNodeEntry {
    case masterSwitch(PresentationTheme, Bool)
    case masterInfo(PresentationTheme, String)
    case switchesHeader(PresentationTheme, String)
    case hideTyping(PresentationTheme, Bool, Bool)
    case noReadReceipts(PresentationTheme, Bool, Bool)
    case hideOnline(PresentationTheme, Bool, Bool)
    case scheduleHeader(PresentationTheme, String)
    case scheduleSwitch(PresentationTheme, Bool, Bool)
    case scheduleDelay(PresentationTheme, Int32, Bool, Bool)
    case scheduleInfo(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .masterSwitch, .masterInfo:
            return BeyGramPrivacySection.master.rawValue
        case .switchesHeader, .hideTyping, .noReadReceipts, .hideOnline:
            return BeyGramPrivacySection.switches.rawValue
        case .scheduleHeader, .scheduleSwitch, .scheduleDelay, .scheduleInfo:
            return BeyGramPrivacySection.schedule.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .masterSwitch:
            return 0
        case .masterInfo:
            return 1
        case .switchesHeader:
            return 2
        case .hideTyping:
            return 3
        case .noReadReceipts:
            return 4
        case .hideOnline:
            return 5
        case .scheduleHeader:
            return 6
        case .scheduleSwitch:
            return 7
        case let .scheduleDelay(_, seconds, _, _):
            return 8 + Int32(BeyGramStealthSettings.scheduleDelayChoices.firstIndex(of: seconds) ?? 0)
        case .scheduleInfo:
            return 20
        }
    }

    static func ==(lhs: BeyGramPrivacyEntry, rhs: BeyGramPrivacyEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.masterSwitch(lhsTheme, lhsValue), .masterSwitch(rhsTheme, rhsValue)):
            return lhsTheme === rhsTheme && lhsValue == rhsValue
        case let (.masterInfo(lhsTheme, lhsText), .masterInfo(rhsTheme, rhsText)):
            return lhsTheme === rhsTheme && lhsText == rhsText
        case let (.switchesHeader(lhsTheme, lhsText), .switchesHeader(rhsTheme, rhsText)):
            return lhsTheme === rhsTheme && lhsText == rhsText
        case let (.hideTyping(lhsTheme, lhsValue, lhsEnabled), .hideTyping(rhsTheme, rhsValue, rhsEnabled)):
            return lhsTheme === rhsTheme && lhsValue == rhsValue && lhsEnabled == rhsEnabled
        case let (.noReadReceipts(lhsTheme, lhsValue, lhsEnabled), .noReadReceipts(rhsTheme, rhsValue, rhsEnabled)):
            return lhsTheme === rhsTheme && lhsValue == rhsValue && lhsEnabled == rhsEnabled
        case let (.hideOnline(lhsTheme, lhsValue, lhsEnabled), .hideOnline(rhsTheme, rhsValue, rhsEnabled)):
            return lhsTheme === rhsTheme && lhsValue == rhsValue && lhsEnabled == rhsEnabled
        case let (.scheduleHeader(lhsTheme, lhsText), .scheduleHeader(rhsTheme, rhsText)):
            return lhsTheme === rhsTheme && lhsText == rhsText
        case let (.scheduleSwitch(lhsTheme, lhsValue, lhsEnabled), .scheduleSwitch(rhsTheme, rhsValue, rhsEnabled)):
            return lhsTheme === rhsTheme && lhsValue == rhsValue && lhsEnabled == rhsEnabled
        case let (.scheduleDelay(lhsTheme, lhsSeconds, lhsSelected, lhsEnabled), .scheduleDelay(rhsTheme, rhsSeconds, rhsSelected, rhsEnabled)):
            return lhsTheme === rhsTheme && lhsSeconds == rhsSeconds && lhsSelected == rhsSelected && lhsEnabled == rhsEnabled
        case let (.scheduleInfo(lhsTheme, lhsText), .scheduleInfo(rhsTheme, rhsText)):
            return lhsTheme === rhsTheme && lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: BeyGramPrivacyEntry, rhs: BeyGramPrivacyEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramPrivacyArguments
        switch self {
        case let .masterSwitch(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Режим невидимки", value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.setMasterEnabled(newValue)
            })
        case let .masterInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .switchesHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .hideTyping(_, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Не показывать, что я печатаю", value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.setSwitch(.hideTyping, newValue)
            })
        case let .noReadReceipts(_, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Не отмечать сообщения прочитанными", value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.setSwitch(.noReadReceipts, newValue)
            })
        case let .hideOnline(_, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Скрывать статус «в сети»", value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.setSwitch(.hideOnline, newValue)
            })
        case let .scheduleHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .scheduleSwitch(_, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Отправлять через отложенные сообщения Telegram", value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.setSwitch(.serverScheduledSend, newValue)
            })
        case let .scheduleDelay(_, seconds, selected, enabled):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: "\(seconds) с", style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                if enabled {
                    arguments.setScheduleDelay(seconds)
                }
            })
        case let .scheduleInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func beyGramPrivacyEntries(presentationData: PresentationData, masterEnabled: Bool, settings: BeyGramStealthSettings) -> [BeyGramPrivacyEntry] {
    let theme = presentationData.theme
    var entries: [BeyGramPrivacyEntry] = []
    entries.append(.masterSwitch(theme, masterEnabled))
    entries.append(.masterInfo(theme, "Пока режим выключен, ни один из переключателей ниже не действует. Все они выключены по умолчанию. Настройки относятся только к этому аккаунту."))

    entries.append(.switchesHeader(theme, "Что скрывать"))
    entries.append(.hideTyping(theme, settings.hideTyping, masterEnabled))
    entries.append(.noReadReceipts(theme, settings.hideReadReceipts, masterEnabled))
    entries.append(.hideOnline(theme, settings.hideOnline, masterEnabled))

    entries.append(.scheduleHeader(theme, "Отправка в невидимке"))
    entries.append(.scheduleSwitch(theme, settings.serverScheduledSend, masterEnabled))
    for seconds in BeyGramStealthSettings.scheduleDelayChoices {
        entries.append(.scheduleDelay(theme, seconds, settings.scheduledSendDelaySeconds == seconds, masterEnabled && settings.serverScheduledSend))
    }
    entries.append(.scheduleInfo(theme, "Сообщение сразу уходит на сервер Telegram как запланированное, и сервер публикует его через выбранное время. Пока сообщение ждёт, его можно отменить или перенести в списке отложенных сообщений чата. В секретных чатах, в чатах с платными сообщениями и в трансляции геопозиции запланировать нельзя: такие отправки не уходят сразу и не отправляются. Это снижает риск показать вас в сети, но не гарантирует невидимость."))
    return entries
}

/// The privacy screen: the master switch of `BeyGramFeature.privacyPolicy` and the per-account stealth switches.
public func beyGramPrivacyController(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    let masterPromise = ValuePromise<Bool>(BeyGramSettings.shared.isEnabled(.privacyPolicy), ignoreRepeated: true)
    let settingsPromise = ValuePromise<BeyGramStealthSettings>(BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId), ignoreRepeated: true)

    let arguments = BeyGramPrivacyArguments(setMasterEnabled: { value in
        BeyGramSettings.shared.setEnabled(value, for: .privacyPolicy)
        masterPromise.set(BeyGramSettings.shared.isEnabled(.privacyPolicy))
    }, setSwitch: { option, value in
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
    }, setScheduleDelay: { seconds in
        BeyGramStealthStore.shared.update(accountPeerId: accountPeerId) { settings in
            settings.scheduledSendDelaySeconds = seconds
        }
        settingsPromise.set(BeyGramStealthStore.shared.settings(accountPeerId: accountPeerId))
    })

    let signal = combineLatest(context.sharedContext.presentationData, masterPromise.get(), settingsPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, masterEnabled, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Приватность"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: beyGramPrivacyEntries(presentationData: presentationData, masterEnabled: masterEnabled, settings: settings), style: .blocks)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
