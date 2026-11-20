import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit

private final class AudioPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: ([URL]) -> Void

    init(onPick: @escaping ([URL]) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.onPick(urls)
    }
}

private final class BeyGramMixArguments {
    let togglePlayPause: () -> Void
    let nextTrack: () -> Void
    let addTracks: () -> Void
    let clearQueue: () -> Void
    let removeTrack: (UInt64) -> Void
    let openSettings: () -> Void

    init(
        togglePlayPause: @escaping () -> Void,
        nextTrack: @escaping () -> Void,
        addTracks: @escaping () -> Void,
        clearQueue: @escaping () -> Void,
        removeTrack: @escaping (UInt64) -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.togglePlayPause = togglePlayPause
        self.nextTrack = nextTrack
        self.addTracks = addTracks
        self.clearQueue = clearQueue
        self.removeTrack = removeTrack
        self.openSettings = openSettings
    }
}

private enum BeyGramMixSection: Int32 {
    case nowPlaying
    case controls
    case queue
}

private enum BeyGramMixEntryId: Hashable {
    case fixed(Int32)
    case track(UInt64)
}

private enum BeyGramMixEntry: ItemListNodeEntry {
    case nowPlayingHeader(PresentationTheme, String)
    case currentTrack(PresentationTheme, String, String)
    case nextTrack(PresentationTheme, String, String)
    case transitionStatus(PresentationTheme, String)

    case playPause(PresentationTheme, String, Bool)
    case nextAction(PresentationTheme, String, Bool)
    case addAction(PresentationTheme, String)
    case clearAction(PresentationTheme, String, Bool)
    case mixSettings(PresentationTheme, String)

    case queueHeader(PresentationTheme, String)
    case emptyQueue(PresentationTheme, String)
    case trackRow(Int, PresentationTheme, UInt64, String, String, Bool)

    var section: ItemListSectionId {
        switch self {
        case .nowPlayingHeader, .currentTrack, .nextTrack, .transitionStatus:
            return BeyGramMixSection.nowPlaying.rawValue
        case .playPause, .nextAction, .addAction, .clearAction, .mixSettings:
            return BeyGramMixSection.controls.rawValue
        case .queueHeader, .emptyQueue, .trackRow:
            return BeyGramMixSection.queue.rawValue
        }
    }

    var stableId: BeyGramMixEntryId {
        switch self {
        case .nowPlayingHeader: return .fixed(0)
        case .currentTrack: return .fixed(1)
        case .nextTrack: return .fixed(2)
        case .transitionStatus: return .fixed(3)
        case .playPause: return .fixed(10)
        case .nextAction: return .fixed(11)
        case .addAction: return .fixed(12)
        case .clearAction: return .fixed(13)
        case .mixSettings: return .fixed(14)
        case .queueHeader: return .fixed(20)
        case .emptyQueue: return .fixed(21)
        case let .trackRow(_, _, id, _, _, _): return .track(id)
        }
    }

    private var sortOrder: Int {
        switch self {
        case .nowPlayingHeader: return 0
        case .currentTrack: return 1
        case .nextTrack: return 2
        case .transitionStatus: return 3
        case .playPause: return 10
        case .nextAction: return 11
        case .addAction: return 12
        case .clearAction: return 13
        case .mixSettings: return 14
        case .queueHeader: return 20
        case .emptyQueue: return 21
        case let .trackRow(index, _, _, _, _, _): return 100 + index
        }
    }

    static func == (lhs: BeyGramMixEntry, rhs: BeyGramMixEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.nowPlayingHeader(lt, lText), .nowPlayingHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.currentTrack(lt, lTitle, lLabel), .currentTrack(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.nextTrack(lt, lTitle, lLabel), .nextTrack(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.transitionStatus(lt, lText), .transitionStatus(rt, rText)):
            return lt === rt && lText == rText
        case let (.playPause(lt, lTitle, lEnabled), .playPause(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.nextAction(lt, lTitle, lEnabled), .nextAction(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.addAction(lt, lTitle), .addAction(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.clearAction(lt, lTitle, lEnabled), .clearAction(rt, rTitle, rEnabled)):
            return lt === rt && lTitle == rTitle && lEnabled == rEnabled
        case let (.mixSettings(lt, lTitle), .mixSettings(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.queueHeader(lt, lText), .queueHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.emptyQueue(lt, lText), .emptyQueue(rt, rText)):
            return lt === rt && lText == rText
        case let (.trackRow(lIdx, lt, lId, lTitle, lLabel, lPlaying), .trackRow(rIdx, rt, rId, rTitle, rLabel, rPlaying)):
            return lIdx == rIdx && lt === rt && lId == rId && lTitle == rTitle && lLabel == rLabel && lPlaying == rPlaying
        default:
            return false
        }
    }

    static func < (lhs: BeyGramMixEntry, rhs: BeyGramMixEntry) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramMixArguments
        switch self {
        case let .nowPlayingHeader(_, text), let .queueHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .currentTrack(_, title, label), let .nextTrack(_, title, label):
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
        case let .transitionStatus(_, text), let .emptyQueue(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .playPause(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.togglePlayPause() }
                }
            )
        case let .nextAction(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.nextTrack() }
                }
            )
        case let .addAction(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: arguments.addTracks
            )
        case let .clearAction(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .destructive : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.clearQueue() }
                }
            )
        case let .mixSettings(_, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: arguments.openSettings
            )
        case let .trackRow(_, _, id, title, label, isCurrent):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: isCurrent ? "▶︎ \(title)" : title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.removeTrack(id)
                }
            )
        }
    }
}

private func beyGramMixEntries(presentationData: PresentationData, state: BeyGramMusicState) -> [BeyGramMixEntry] {
    let lang = presentationData.strings.primaryComponent.languageCode
    let l10n = BeyGramL10n.shared
    let theme = presentationData.theme
    var entries: [BeyGramMixEntry] = []

    entries.append(.nowPlayingHeader(theme, l10n.string(.bgMixCurrentTrack, languageCode: lang).uppercased()))
    if let current = state.currentTrack {
        var meta: [String] = []
        if state.duration > 0 {
            meta.append("\(l10n.formatDuration(state.position)) / \(l10n.formatDuration(state.duration))")
        } else if let duration = current.duration {
            meta.append(l10n.formatDuration(duration))
        }
        if let bpm = current.bpm {
            meta.append(l10n.format(.bgMixBpmFormat, languageCode: lang, bpm))
        }
        entries.append(.currentTrack(theme, current.title, meta.joined(separator: " • ")))
    } else {
        entries.append(.currentTrack(theme, l10n.string(.musicNothingPlaying, languageCode: lang), ""))
    }

    if let next = state.nextTrack {
        let ready: String
        switch next.status {
        case .pending:
            ready = l10n.string(.musicTrackPreparing, languageCode: lang)
        case let .preparing(progress):
            ready = "\(l10n.string(.musicTrackPreparing, languageCode: lang)) \(Int((progress * 100.0).rounded()))%"
        case .ready, .playing, .played:
            ready = l10n.string(.musicTrackReady, languageCode: lang)
        case let .failed(err):
            ready = err ?? l10n.string(.commonError, languageCode: lang)
        }
        entries.append(.nextTrack(theme, l10n.string(.bgMixNextTrack, languageCode: lang), "\(next.title) (\(ready))"))
    } else if !state.queue.isEmpty {
        entries.append(.nextTrack(theme, l10n.string(.bgMixNextTrack, languageCode: lang), l10n.string(.bgMixNoNextTrack, languageCode: lang)))
    }

    if state.isTransitionActive {
        let pct = Int((state.transitionProgress * 100.0).rounded())
        entries.append(.transitionStatus(theme, "✦ \(l10n.string(.bgMixTransitionActive, languageCode: lang)) (\(pct)%)"))
    } else if let lastError = state.lastError, !lastError.isEmpty {
        entries.append(.transitionStatus(theme, lastError))
    }

    let hasQueue = !state.queue.isEmpty
    let playTitle = state.isPlaying
        ? l10n.string(.musicPause, languageCode: lang)
        : l10n.string(.musicPlay, languageCode: lang)
    entries.append(.playPause(theme, playTitle, hasQueue))
    entries.append(.nextAction(theme, l10n.string(.musicNext, languageCode: lang), state.queue.count > 1))
    entries.append(.addAction(theme, l10n.string(.musicAddTracks, languageCode: lang)))
    entries.append(.clearAction(theme, l10n.string(.musicClearQueue, languageCode: lang), hasQueue))
    entries.append(.mixSettings(theme, l10n.string(.bgMixSettingsTitle, languageCode: lang)))

    entries.append(.queueHeader(theme, l10n.string(.bgMixQueueHeader, languageCode: lang).uppercased()))
    if state.queue.isEmpty {
        entries.append(.emptyQueue(theme, l10n.string(.bgMixEmptySubtitle, languageCode: lang)))
    } else {
        for (index, track) in state.queue.enumerated() {
            var parts: [String] = []
            if let duration = track.duration {
                parts.append(l10n.formatDuration(duration))
            }
            if let bpm = track.bpm {
                parts.append(l10n.format(.bgMixBpmFormat, languageCode: lang, bpm))
            }
            let isCurrent = state.currentTrack?.id == track.id
            if case let .preparing(progress) = track.status {
                parts.append("\(Int((progress * 100.0).rounded()))%")
            } else if case let .failed(err) = track.status {
                parts.append(err ?? l10n.string(.commonError, languageCode: lang))
            }
            entries.append(.trackRow(index, theme, track.id, track.title, parts.joined(separator: " • "), isCurrent))
        }
    }

    return entries
}

/// Native BG Mix & BG Beat player and queue screen.
public func beyGramMixController(context: AccountContext) -> ViewController {
    var presentImpl: ((ViewController, Any?) -> Void)?
    var pushImpl: ((ViewController) -> Void)?
    var pickerDelegate: AudioPickerDelegate?

    let arguments = BeyGramMixArguments(
        togglePlayPause: {
            BeyGramMusicSession.shared.togglePlayPause()
        },
        nextTrack: {
            BeyGramMusicSession.shared.next()
        },
        addTracks: {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio], asCopy: true)
            picker.allowsMultipleSelection = true
            let delegate = AudioPickerDelegate { urls in
                BeyGramMusicSession.shared.addTracks(urls: urls)
                pickerDelegate = nil
            }
            pickerDelegate = delegate
            picker.delegate = delegate
            let _ = pickerDelegate
            if let top = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController {
                var presenter = top
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                presenter.present(picker, animated: true)
            }
        },
        clearQueue: {
            BeyGramMusicSession.shared.clearQueue()
        },
        removeTrack: { id in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.primaryComponent.languageCode
            let l10n = BeyGramL10n.shared
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: l10n.string(.musicRemoveFromQueue, languageCode: lang), color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        BeyGramMusicSession.shared.removeTrack(id: id)
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentImpl?(sheet, nil)
        },
        openSettings: {
            pushImpl?(beyGramMixSettingsController(context: context))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, BeyGramMusicSession.shared.stateSignal)
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(BeyGramL10n.shared.string(.bgMixTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: beyGramMixEntries(presentationData: presentationData, state: state),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] next, arg in
        controller?.present(next, in: .window(.root), with: arg)
    }
    pushImpl = { [weak controller] next in
        controller?.push(next)
    }
    return controller
}

private final class BeyGramMixSettingsArguments {
    let pickDuration: () -> Void
    let setAdaptive: (Bool) -> Void
    let setBassSwap: (Bool) -> Void

    init(pickDuration: @escaping () -> Void, setAdaptive: @escaping (Bool) -> Void, setBassSwap: @escaping (Bool) -> Void) {
        self.pickDuration = pickDuration
        self.setAdaptive = setAdaptive
        self.setBassSwap = setBassSwap
    }
}

private enum BeyGramMixSettingsEntry: ItemListNodeEntry {
    case duration(PresentationTheme, String, String)
    case adaptive(PresentationTheme, String, Bool)
    case adaptiveInfo(PresentationTheme, String)
    case bassSwap(PresentationTheme, String, Bool)
    case bassSwapInfo(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .duration: return 0
        case .adaptive, .adaptiveInfo: return 1
        case .bassSwap, .bassSwapInfo: return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .duration: return 0
        case .adaptive: return 1
        case .adaptiveInfo: return 2
        case .bassSwap: return 3
        case .bassSwapInfo: return 4
        }
    }

    static func == (lhs: BeyGramMixSettingsEntry, rhs: BeyGramMixSettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.duration(lt, lTitle, lVal), .duration(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.adaptive(lt, lTitle, lVal), .adaptive(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.adaptiveInfo(lt, lText), .adaptiveInfo(rt, rText)):
            return lt === rt && lText == rText
        case let (.bassSwap(lt, lTitle, lVal), .bassSwap(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.bassSwapInfo(lt, lText), .bassSwapInfo(rt, rText)):
            return lt === rt && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: BeyGramMixSettingsEntry, rhs: BeyGramMixSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramMixSettingsArguments
        switch self {
        case let .duration(_, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                action: arguments.pickDuration
            )
        case let .adaptive(_, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: arguments.setAdaptive
            )
        case let .adaptiveInfo(_, text), let .bassSwapInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .bassSwap(_, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: arguments.setBassSwap
            )
        }
    }
}

/// Compact BG Mix & BG Beat transition parameters screen.
public func beyGramMixSettingsController(context: AccountContext) -> ViewController {
    var presentImpl: ((ViewController, Any?) -> Void)?
    let arguments = BeyGramMixSettingsArguments(
        pickDuration: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.primaryComponent.languageCode
            let l10n = BeyGramL10n.shared
            let choices: [Double] = [0.0, 4.0, 8.0, 12.0]
            let sheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            for seconds in choices {
                let title = seconds <= 0.0
                    ? l10n.string(.bgMixTransitionAuto, languageCode: lang)
                    : l10n.plural(.secondsFull, count: Int(seconds), languageCode: lang)
                items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    BeyGramMusicSession.shared.setTransitionDuration(seconds)
                }))
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentImpl?(sheet, nil)
        },
        setAdaptive: { enabled in
            BeyGramMusicSession.shared.setAdaptiveTransitions(enabled)
        },
        setBassSwap: { enabled in
            BeyGramMusicSession.shared.setBassSwap(enabled)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, BeyGramMusicSession.shared.stateSignal)
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let theme = presentationData.theme
        let durationValue = state.transitionDuration <= 0.0
            ? l10n.string(.bgMixTransitionAuto, languageCode: lang)
            : l10n.plural(.secondsShort, count: Int(state.transitionDuration), languageCode: lang)

        let entries: [BeyGramMixSettingsEntry] = [
            .duration(theme, l10n.string(.bgMixTransitionDuration, languageCode: lang), durationValue),
            .adaptive(theme, l10n.string(.bgMixAdaptiveTransitions, languageCode: lang), state.adaptiveTransitions),
            .adaptiveInfo(theme, l10n.string(.bgMixAdaptiveDescription, languageCode: lang)),
            .bassSwap(theme, l10n.string(.bgMixBassSwap, languageCode: lang), state.bassSwap),
            .bassSwapInfo(theme, l10n.string(.bgMixBassSwapDescription, languageCode: lang))
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(l10n.string(.bgMixSettingsTitle, languageCode: lang)),
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

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] next, arg in
        controller?.present(next, in: .window(.root), with: arg)
    }
    return controller
}
