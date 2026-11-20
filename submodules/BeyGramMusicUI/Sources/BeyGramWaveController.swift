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

private final class BeyGramWaveArguments {
    let updateInvite: (String) -> Void
    let checkInvite: () -> Void
    let createWave: () -> Void

    init(updateInvite: @escaping (String) -> Void, checkInvite: @escaping () -> Void, createWave: @escaping () -> Void) {
        self.updateInvite = updateInvite
        self.checkInvite = checkInvite
        self.createWave = createWave
    }
}

private enum BeyGramWaveSection: Int32 {
    case availability
    case session
    case invite
}

private enum BeyGramWaveEntry: ItemListNodeEntry {
    case availabilityHeader(PresentationTheme, String)
    case availabilityBody(PresentationTheme, String)
    case sessionHeader(PresentationTheme, String)
    case sessionStatus(PresentationTheme, String, String)
    case createWave(PresentationTheme, String)
    case inviteHeader(PresentationTheme, String)
    case inviteField(PresentationTheme, String, String)
    case checkInvite(PresentationTheme, String, Bool)
    case inviteResult(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .availabilityHeader, .availabilityBody:
            return BeyGramWaveSection.availability.rawValue
        case .sessionHeader, .sessionStatus, .createWave:
            return BeyGramWaveSection.session.rawValue
        case .inviteHeader, .inviteField, .checkInvite, .inviteResult:
            return BeyGramWaveSection.invite.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .availabilityHeader: return 0
        case .availabilityBody: return 1
        case .sessionHeader: return 2
        case .sessionStatus: return 3
        case .createWave: return 4
        case .inviteHeader: return 5
        case .inviteField: return 6
        case .checkInvite: return 7
        case .inviteResult: return 8
        }
    }

    static func == (lhs: BeyGramWaveEntry, rhs: BeyGramWaveEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.availabilityHeader(lt, lText), .availabilityHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.availabilityBody(lt, lText), .availabilityBody(rt, rText)):
            return lt === rt && lText == rText
        case let (.sessionHeader(lt, lText), .sessionHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.sessionStatus(lt, lTitle, lVal), .sessionStatus(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.createWave(lt, lTitle), .createWave(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.inviteHeader(lt, lText), .inviteHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.inviteField(lt, lText, lPlaceholder), .inviteField(rt, rText, rPlaceholder)):
            return lt === rt && lText == rText && lPlaceholder == rPlaceholder
        case let (.checkInvite(lt, lTitle, lEnabled), .checkInvite(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.inviteResult(lt, lText), .inviteResult(rt, rText)):
            return lt === rt && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: BeyGramWaveEntry, rhs: BeyGramWaveEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramWaveArguments
        switch self {
        case let .availabilityHeader(_, text), let .sessionHeader(_, text), let .inviteHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .availabilityBody(_, text), let .inviteResult(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .sessionStatus(_, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .createWave(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: arguments.createWave
            )
        case let .inviteField(_, text, placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: "", textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: text,
                placeholder: placeholder,
                type: .regular(capitalization: false, autocorrection: false),
                spacing: 0.0,
                clearType: .always,
                sectionId: self.section,
                textUpdated: arguments.updateInvite,
                action: arguments.checkInvite
            )
        case let .checkInvite(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.checkInvite() }
                }
            )
        }
    }
}

/// Native BG Wave screen prepared for shared-listening transport without simulating fake connections.
public func beyGramWaveController(context: AccountContext) -> ViewController {
    let inviteText = Atomic<String>(value: "")
    let validationResult = Atomic<Bool?>(value: nil)
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let bump: () -> Void = {
        counter += 1
        revision.set(counter)
    }

    let arguments = BeyGramWaveArguments(
        updateInvite: { text in
            _ = inviteText.swap(text)
            _ = validationResult.swap(nil)
            bump()
        },
        checkInvite: {
            let current = inviteText.with { $0 }
            _ = validationResult.swap(BGWaveLinkLooksValid(current))
            bump()
        },
        createWave: {}
    )

    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let theme = presentationData.theme
        let currentInvite = inviteText.with { $0 }
        let isValid = validationResult.with { $0 }

        var entries: [BeyGramWaveEntry] = [
            .availabilityHeader(theme, l10n.string(.bgWaveUnavailableTitle, languageCode: lang).uppercased()),
            .availabilityBody(theme, l10n.string(.bgWaveUnavailableBody, languageCode: lang)),
            .sessionHeader(theme, l10n.string(.bgWaveCurrentSession, languageCode: lang).uppercased()),
            .sessionStatus(theme, l10n.string(.bgWaveCurrentSession, languageCode: lang), l10n.string(.bgWaveStatusDisconnected, languageCode: lang)),
            .createWave(theme, "\(l10n.string(.bgWaveCreateWave, languageCode: lang)) (\(l10n.string(.commonExperimental, languageCode: lang)))"),
            .inviteHeader(theme, l10n.string(.bgWaveJoinByInvite, languageCode: lang).uppercased()),
            .inviteField(theme, currentInvite, l10n.string(.bgWaveInvitePlaceholder, languageCode: lang)),
            .checkInvite(theme, l10n.string(.bgWaveCheckInvite, languageCode: lang), !currentInvite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        ]

        if let isValid {
            entries.append(.inviteResult(
                theme,
                isValid
                    ? l10n.string(.bgWaveInviteValid, languageCode: lang)
                    : l10n.string(.bgWaveInviteInvalid, languageCode: lang)
            ))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(l10n.string(.bgWaveTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
