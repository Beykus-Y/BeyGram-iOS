import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramAppearance
import BeyGramKit

public func beyGramStyleDisplayName(_ style: BeyGramStyle, languageCode: String) -> String {
    let l10n = BeyGramL10n.shared
    switch style {
    case .telegram:
        return l10n.string(.appearanceStyleTelegram, languageCode: languageCode)
    case .beygramDefault:
        return l10n.string(.appearanceStyleDefault, languageCode: languageCode)
    case .material2:
        return l10n.string(.appearanceStyleMaterial2, languageCode: languageCode)
    case .material3:
        return l10n.string(.appearanceStyleMaterial3, languageCode: languageCode)
    case .liquidGlass:
        return l10n.string(.appearanceStyleLiquidGlass, languageCode: languageCode)
    case .signature:
        return l10n.string(.appearanceStyleSignature, languageCode: languageCode)
    }
}

private func glassQualityDisplayName(_ quality: BeyGramGlassQuality, languageCode: String) -> String {
    let l10n = BeyGramL10n.shared
    switch quality {
    case .auto:
        return l10n.string(.appearanceGlassAuto, languageCode: languageCode)
    case .high:
        return l10n.string(.appearanceGlassHigh, languageCode: languageCode)
    case .balanced:
        return l10n.string(.appearanceGlassBalanced, languageCode: languageCode)
    case .lite:
        return l10n.string(.appearanceGlassLite, languageCode: languageCode)
    }
}

private func navPlacementDisplayName(_ placement: BeyGramNavigationPlacement, languageCode: String) -> String {
    let l10n = BeyGramL10n.shared
    switch placement {
    case .auto:
        return l10n.string(.appearanceNavAuto, languageCode: languageCode)
    case .pinned:
        return l10n.string(.appearanceNavPinned, languageCode: languageCode)
    case .floating:
        return l10n.string(.appearanceNavFloating, languageCode: languageCode)
    }
}

private final class BeyGramStyleArguments {
    let selectStyle: (BeyGramStyle) -> Void
    let selectGlass: (BeyGramGlassQuality) -> Void
    let selectNav: (BeyGramNavigationPlacement) -> Void

    init(
        selectStyle: @escaping (BeyGramStyle) -> Void,
        selectGlass: @escaping (BeyGramGlassQuality) -> Void,
        selectNav: @escaping (BeyGramNavigationPlacement) -> Void
    ) {
        self.selectStyle = selectStyle
        self.selectGlass = selectGlass
        self.selectNav = selectNav
    }
}

private enum BeyGramStyleSection: Int32 {
    case styles = 0
    case glass = 1
    case navigation = 2
}

private enum BeyGramStyleEntry: ItemListNodeEntry {
    case styleHeader(PresentationTheme, String)
    case style(PresentationTheme, BeyGramStyle, String, Bool)
    case styleInfo(PresentationTheme, String)
    case glassHeader(PresentationTheme, String)
    case glass(PresentationTheme, BeyGramGlassQuality, String, Bool)
    case navHeader(PresentationTheme, String)
    case nav(PresentationTheme, BeyGramNavigationPlacement, String, Bool)

    var section: ItemListSectionId {
        switch self {
        case .styleHeader, .style, .styleInfo:
            return BeyGramStyleSection.styles.rawValue
        case .glassHeader, .glass:
            return BeyGramStyleSection.glass.rawValue
        case .navHeader, .nav:
            return BeyGramStyleSection.navigation.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .styleHeader:
            return 0
        case let .style(_, style, _, _):
            return 1 + style.rawValue
        case .styleInfo:
            return 20
        case .glassHeader:
            return 30
        case let .glass(_, quality, _, _):
            return 31 + quality.rawValue
        case .navHeader:
            return 50
        case let .nav(_, placement, _, _):
            return 51 + placement.rawValue
        }
    }

    static func ==(lhs: BeyGramStyleEntry, rhs: BeyGramStyleEntry) -> Bool {
        switch lhs {
        case let .styleHeader(lhsTheme, lhsText):
            if case let .styleHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText { return true }
            return false
        case let .style(lhsTheme, lhsStyle, lhsText, lhsChecked):
            if case let .style(rhsTheme, rhsStyle, rhsText, rhsChecked) = rhs, lhsTheme === rhsTheme, lhsStyle == rhsStyle, lhsText == rhsText, lhsChecked == rhsChecked { return true }
            return false
        case let .styleInfo(lhsTheme, lhsText):
            if case let .styleInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText { return true }
            return false
        case let .glassHeader(lhsTheme, lhsText):
            if case let .glassHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText { return true }
            return false
        case let .glass(lhsTheme, lhsQuality, lhsText, lhsChecked):
            if case let .glass(rhsTheme, rhsQuality, rhsText, rhsChecked) = rhs, lhsTheme === rhsTheme, lhsQuality == rhsQuality, lhsText == rhsText, lhsChecked == rhsChecked { return true }
            return false
        case let .navHeader(lhsTheme, lhsText):
            if case let .navHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText { return true }
            return false
        case let .nav(lhsTheme, lhsNav, lhsText, lhsChecked):
            if case let .nav(rhsTheme, rhsNav, rhsText, rhsChecked) = rhs, lhsTheme === rhsTheme, lhsNav == rhsNav, lhsText == rhsText, lhsChecked == rhsChecked { return true }
            return false
        }
    }

    static func <(lhs: BeyGramStyleEntry, rhs: BeyGramStyleEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramStyleArguments
        switch self {
        case let .styleHeader(_, text), let .glassHeader(_, text), let .navHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .style(_, style, text, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectStyle(style)
            })
        case let .styleInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .glass(_, quality, text, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectGlass(quality)
            })
        case let .nav(_, placement, text, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectNav(placement)
            })
        }
    }
}

private func beyGramStyleEntries(
    presentationData: PresentationData,
    selectedStyle: BeyGramStyle,
    selectedGlass: BeyGramGlassQuality,
    selectedNav: BeyGramNavigationPlacement
) -> [BeyGramStyleEntry] {
    let lang = presentationData.strings.primaryComponent.languageCode
    let l10n = BeyGramL10n.shared
    var entries: [BeyGramStyleEntry] = []

    entries.append(.styleHeader(presentationData.theme, l10n.string(.appearanceSectionStyle, languageCode: lang)))
    for style in BeyGramStyle.allCases {
        entries.append(.style(presentationData.theme, style, beyGramStyleDisplayName(style, languageCode: lang), selectedStyle == style))
    }
    entries.append(.styleInfo(presentationData.theme, l10n.string(.appearanceDescription, languageCode: lang)))

    if selectedStyle == .liquidGlass {
        entries.append(.glassHeader(presentationData.theme, l10n.string(.appearanceSectionGlass, languageCode: lang)))
        for quality in BeyGramGlassQuality.allCases {
            entries.append(.glass(presentationData.theme, quality, glassQualityDisplayName(quality, languageCode: lang), selectedGlass == quality))
        }
    }

    if selectedStyle != .telegram {
        entries.append(.navHeader(presentationData.theme, l10n.string(.appearanceSectionNavigation, languageCode: lang)))
        for placement in BeyGramNavigationPlacement.allCases {
            entries.append(.nav(presentationData.theme, placement, navPlacementDisplayName(placement, languageCode: lang), selectedNav == placement))
        }
    }

    return entries
}

/// The screen that chooses between Telegram Original and the 5 BeyGram Android design styles.
public func beyGramStyleController(context: AccountContext) -> ViewController {
    let arguments = BeyGramStyleArguments(
        selectStyle: { style in
            BeyGramAppearance.shared.setStyle(style)
        },
        selectGlass: { quality in
            BeyGramAppearance.shared.setGlassQuality(quality)
        },
        selectNav: { placement in
            BeyGramAppearance.shared.setNavigationPlacement(placement)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        BeyGramAppearance.shared.styleSignal,
        BeyGramAppearance.shared.glassQualitySignal,
        BeyGramAppearance.shared.navigationPlacementSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, selectedStyle, selectedGlass, selectedNav -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(BeyGramL10n.shared.string(.appearanceTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: beyGramStyleEntries(
                presentationData: presentationData,
                selectedStyle: selectedStyle,
                selectedGlass: selectedGlass,
                selectedNav: selectedNav
            ),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
