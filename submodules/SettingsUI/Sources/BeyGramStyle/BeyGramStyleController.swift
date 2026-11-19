import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramAppearance

private final class BeyGramStyleArguments {
    let select: (BeyGramStyle) -> Void

    init(select: @escaping (BeyGramStyle) -> Void) {
        self.select = select
    }
}

private enum BeyGramStyleSection: Int32 {
    case styles
}

private enum BeyGramStyleEntry: ItemListNodeEntry {
    case header(PresentationTheme, String)
    case style(PresentationTheme, BeyGramStyle, String, Bool)
    case info(PresentationTheme, String)

    var section: ItemListSectionId {
        return BeyGramStyleSection.styles.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .style(_, style, _, _):
            return 1 + style.rawValue
        case .info:
            return 3
        }
    }

    static func ==(lhs: BeyGramStyleEntry, rhs: BeyGramStyleEntry) -> Bool {
        switch lhs {
        case let .header(lhsTheme, lhsText):
            if case let .header(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .style(lhsTheme, lhsStyle, lhsText, lhsChecked):
            if case let .style(rhsTheme, rhsStyle, rhsText, rhsChecked) = rhs, lhsTheme === rhsTheme, lhsStyle == rhsStyle, lhsText == rhsText, lhsChecked == rhsChecked {
                return true
            } else {
                return false
            }
        case let .info(lhsTheme, lhsText):
            if case let .info(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        }
    }

    static func <(lhs: BeyGramStyleEntry, rhs: BeyGramStyleEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramStyleArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .style(_, style, text, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(style)
            })
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func beyGramStyleEntries(presentationData: PresentationData, selected: BeyGramStyle) -> [BeyGramStyleEntry] {
    var entries: [BeyGramStyleEntry] = []
    entries.append(.header(presentationData.theme, "Style"))
    entries.append(.style(presentationData.theme, .telegram, "Telegram", selected == .telegram))
    entries.append(.style(presentationData.theme, .beygram, "BeyGram", selected == .beygram))
    entries.append(.info(presentationData.theme, "BeyGram keeps the colours of the active Telegram theme and changes the geometry: 20/8 bubble corners, a 24 pt composer and 54 pt avatars in the chat list. Telegram keeps the upstream look."))
    return entries
}

/// The screen that chooses between the Telegram and BeyGram visual styles.
public func beyGramStyleController(context: AccountContext) -> ViewController {
    let arguments = BeyGramStyleArguments(select: { style in
        BeyGramAppearance.shared.setStyle(style)
    })

    let signal = combineLatest(context.sharedContext.presentationData, BeyGramAppearance.shared.styleSignal)
    |> deliverOnMainQueue
    |> map { presentationData, selected -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("BeyGram Style"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: beyGramStyleEntries(presentationData: presentationData, selected: selected), style: .blocks)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
