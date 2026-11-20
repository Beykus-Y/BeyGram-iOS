import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit
import BeyGramMedia
import BeyGramMusicFormat
import BeyGramYandexMusic

private final class BeyGramMusicArguments {
    let setEnabled: (BeyGramFeature, Bool) -> Void
    let openMix: () -> Void
    let openWave: () -> Void
    let openYandex: () -> Void

    init(setEnabled: @escaping (BeyGramFeature, Bool) -> Void, openMix: @escaping () -> Void, openWave: @escaping () -> Void, openYandex: @escaping () -> Void) {
        self.setEnabled = setEnabled
        self.openMix = openMix
        self.openWave = openWave
        self.openYandex = openYandex
    }
}

private enum BeyGramMusicSection: Int32 {
    case flags
    case screens
    case info
}

private enum BeyGramMusicEntry: ItemListNodeEntry {
    case flagsHeader(String)
    case flag(BeyGramFeature, String, Bool)
    case openMix(String)
    case openWave(String)
    case openYandex(String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .flagsHeader, .flag:
            return BeyGramMusicSection.flags.rawValue
        case .openMix, .openWave, .openYandex:
            return BeyGramMusicSection.screens.rawValue
        case .info:
            return BeyGramMusicSection.info.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .flagsHeader:
            return 0
        case let .flag(feature, _, _):
            switch feature {
            case .musicLibrary: return 1
            case .yandexMusic: return 7
            default: return 2
            }
        case .openMix:
            return 3
        case .openWave:
            return 4
        case .openYandex:
            return 6
        case .info:
            return 5
        }
    }

    static func ==(lhs: BeyGramMusicEntry, rhs: BeyGramMusicEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.flagsHeader(lhsText), .flagsHeader(rhsText)):
            return lhsText == rhsText
        case let (.flag(lhsFeature, lhsText, lhsValue), .flag(rhsFeature, rhsText, rhsValue)):
            return lhsFeature == rhsFeature && lhsText == rhsText && lhsValue == rhsValue
        case let (.openMix(lhsText), .openMix(rhsText)):
            return lhsText == rhsText
        case let (.openWave(lhsText), .openWave(rhsText)):
            return lhsText == rhsText
        case let (.openYandex(lhsText), .openYandex(rhsText)):
            return lhsText == rhsText
        case let (.info(lhsText), .info(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: BeyGramMusicEntry, rhs: BeyGramMusicEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramMusicArguments
        switch self {
        case let .flagsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .flag(feature, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.setEnabled(feature, newValue)
            })
        case let .openMix(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openMix()
            })
        case let .openWave(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openWave()
            })
        case let .openYandex(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openYandex()
            })
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func beyGramMusicEntries(presentationData: PresentationData) -> [BeyGramMusicEntry] {
    let languageCode = presentationData.strings.primaryComponent.languageCode
    let settings = BeyGramSettings.shared
    var entries: [BeyGramMusicEntry] = []
    entries.append(.flagsHeader(languageCode == "ru" ? "Функции" : "Features"))
    entries.append(.flag(.musicLibrary, BeyGramFeature.musicLibrary.title(languageCode: languageCode), settings.isEnabled(.musicLibrary)))
    entries.append(.flag(.bgMedia, BeyGramFeature.bgMedia.title(languageCode: languageCode), settings.isEnabled(.bgMedia)))
    entries.append(.flag(.yandexMusic, BeyGramFeature.yandexMusic.title(languageCode: languageCode), settings.isEnabled(.yandexMusic)))
    if settings.isEnabled(.musicLibrary) {
        entries.append(.openMix("BG Mix"))
    }
    if settings.isEnabled(.bgMedia) {
        entries.append(.openWave("BG Wave"))
    }
    if settings.isEnabled(.yandexMusic) {
        entries.append(.openYandex(languageCode == "ru" ? "Яндекс Музыка" : "Yandex Music"))
    }
    entries.append(.info(languageCode == "ru"
        ? "Все функции выключены по умолчанию. BG Mix сводит локальные аудиофайлы с автоматическими переходами. BG Wave на iOS пока умеет только проверять ссылки-приглашения: совместное прослушивание ещё не реализовано."
        : "All features are off by default. BG Mix blends local audio files with automatic transitions. BG Wave on iOS can only check invite links for now: listening together is not implemented yet."))
    return entries
}

/// The BG Music settings page: switches for the music flags and entries to the screens they enable.
public func beyGramMusicSettingsController(context: AccountContext) -> ViewController {
    var counter = 0
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = BeyGramMusicArguments(setEnabled: { feature, value in
        BeyGramSettings.shared.setEnabled(value, for: feature)
        counter += 1
        refresh.set(counter)
    }, openMix: {
        pushControllerImpl?(BeyGramHostedViewController(title: "BG Mix", hosted: BGMixViewController()))
    }, openWave: {
        pushControllerImpl?(BeyGramHostedViewController(title: "BG Wave", hosted: BGWaveViewController()))
    }, openYandex: {
        pushControllerImpl?(beyGramYandexMusicController(context: context))
    })

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("BG Music"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: beyGramMusicEntries(presentationData: presentationData), style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] screen in
        controller?.push(screen)
    }
    return controller
}
