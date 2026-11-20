import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit
import BeyGramYandexMusic

private final class BeyGramMusicCenterArguments {
    let togglePlayPause: () -> Void
    let nextTrack: () -> Void
    let openMix: () -> Void
    let openWave: () -> Void
    let openYandex: () -> Void
    let openMixSettings: () -> Void

    init(
        togglePlayPause: @escaping () -> Void,
        nextTrack: @escaping () -> Void,
        openMix: @escaping () -> Void,
        openWave: @escaping () -> Void,
        openYandex: @escaping () -> Void,
        openMixSettings: @escaping () -> Void
    ) {
        self.togglePlayPause = togglePlayPause
        self.nextTrack = nextTrack
        self.openMix = openMix
        self.openWave = openWave
        self.openYandex = openYandex
        self.openMixSettings = openMixSettings
    }
}

private enum BeyGramMusicCenterSection: Int32 {
    case nowPlaying
    case sources
    case recent
    case settings
}

private enum BeyGramMusicCenterEntryId: Hashable {
    case fixed(Int32)
    case recent(UInt64)
}

private enum BeyGramMusicCenterEntry: ItemListNodeEntry {
    case nowPlayingHeader(PresentationTheme, String)
    case nowPlayingTrack(PresentationTheme, String, String)
    case playPauseAction(PresentationTheme, String)
    case nextAction(PresentationTheme, String)

    case sourcesHeader(PresentationTheme, String)
    case sourceBGMix(PresentationTheme, String, String)
    case sourceYandex(PresentationTheme, String, String)
    case sourceBGWave(PresentationTheme, String, String)

    case recentHeader(PresentationTheme, String)
    case recentTrack(Int, PresentationTheme, UInt64, String, String)
    case emptyLibrary(PresentationTheme, String)

    case settingsHeader(PresentationTheme, String)
    case playbackSettings(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .nowPlayingHeader, .nowPlayingTrack, .playPauseAction, .nextAction:
            return BeyGramMusicCenterSection.nowPlaying.rawValue
        case .sourcesHeader, .sourceBGMix, .sourceYandex, .sourceBGWave:
            return BeyGramMusicCenterSection.sources.rawValue
        case .recentHeader, .recentTrack, .emptyLibrary:
            return BeyGramMusicCenterSection.recent.rawValue
        case .settingsHeader, .playbackSettings:
            return BeyGramMusicCenterSection.settings.rawValue
        }
    }

    var stableId: BeyGramMusicCenterEntryId {
        switch self {
        case .nowPlayingHeader: return .fixed(0)
        case .nowPlayingTrack: return .fixed(1)
        case .playPauseAction: return .fixed(2)
        case .nextAction: return .fixed(3)
        case .sourcesHeader: return .fixed(10)
        case .sourceBGMix: return .fixed(11)
        case .sourceYandex: return .fixed(12)
        case .sourceBGWave: return .fixed(13)
        case .recentHeader: return .fixed(20)
        case .emptyLibrary: return .fixed(21)
        case let .recentTrack(_, _, id, _, _): return .recent(id)
        case .settingsHeader: return .fixed(1000)
        case .playbackSettings: return .fixed(1001)
        }
    }

    private var sortOrder: Int {
        switch self {
        case .nowPlayingHeader: return 0
        case .nowPlayingTrack: return 1
        case .playPauseAction: return 2
        case .nextAction: return 3
        case .sourcesHeader: return 10
        case .sourceBGMix: return 11
        case .sourceYandex: return 12
        case .sourceBGWave: return 13
        case .recentHeader: return 20
        case .emptyLibrary: return 21
        case let .recentTrack(index, _, _, _, _): return 100 + index
        case .settingsHeader: return 10000
        case .playbackSettings: return 10001
        }
    }

    static func == (lhs: BeyGramMusicCenterEntry, rhs: BeyGramMusicCenterEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.nowPlayingHeader(lt, lText), .nowPlayingHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.nowPlayingTrack(lt, lTitle, lLabel), .nowPlayingTrack(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.playPauseAction(lt, lTitle), .playPauseAction(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.nextAction(lt, lTitle), .nextAction(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        case let (.sourcesHeader(lt, lText), .sourcesHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.sourceBGMix(lt, lTitle, lLabel), .sourceBGMix(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.sourceYandex(lt, lTitle, lLabel), .sourceYandex(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.sourceBGWave(lt, lTitle, lLabel), .sourceBGWave(rt, rTitle, rLabel)):
            return lt === rt && lTitle == rTitle && lLabel == rLabel
        case let (.recentHeader(lt, lText), .recentHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.recentTrack(lIdx, lt, lId, lTitle, lLabel), .recentTrack(rIdx, rt, rId, rTitle, rLabel)):
            return lIdx == rIdx && lt === rt && lId == rId && lTitle == rTitle && lLabel == rLabel
        case let (.emptyLibrary(lt, lText), .emptyLibrary(rt, rText)):
            return lt === rt && lText == rText
        case let (.settingsHeader(lt, lText), .settingsHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.playbackSettings(lt, lTitle), .playbackSettings(rt, rTitle)):
            return lt === rt && lTitle == rTitle
        default:
            return false
        }
    }

    static func < (lhs: BeyGramMusicCenterEntry, rhs: BeyGramMusicCenterEntry) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramMusicCenterArguments
        switch self {
        case let .nowPlayingHeader(_, text),
             let .sourcesHeader(_, text),
             let .recentHeader(_, text),
             let .settingsHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .nowPlayingTrack(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.music,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openMix
            )
        case let .playPauseAction(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: arguments.togglePlayPause
            )
        case let .nextAction(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: arguments.nextTrack
            )
        case let .sourceBGMix(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openMix
            )
        case let .sourceYandex(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openYandex
            )
        case let .sourceBGWave(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openWave
            )
        case let .recentTrack(_, _, _, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: arguments.openMix
            )
        case let .emptyLibrary(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .playbackSettings(_, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: arguments.openMixSettings
            )
        }
    }
}

private func musicCenterEntries(presentationData: PresentationData, state: BeyGramMusicState) -> [BeyGramMusicCenterEntry] {
    let lang = presentationData.strings.primaryComponent.languageCode
    let l10n = BeyGramL10n.shared
    let theme = presentationData.theme
    var entries: [BeyGramMusicCenterEntry] = []

    // 1. Now Playing / Mini-player
    entries.append(.nowPlayingHeader(theme, l10n.string(.musicNowPlaying, languageCode: lang).uppercased()))
    if let current = state.currentTrack {
        let status = state.isPlaying ? "▶︎" : "⏸"
        let durationText = current.duration.map { l10n.formatDuration($0) } ?? ""
        entries.append(.nowPlayingTrack(theme, "\(status) \(current.title)", durationText))
        entries.append(.playPauseAction(theme, state.isPlaying ? l10n.string(.musicPause, languageCode: lang) : l10n.string(.musicPlay, languageCode: lang)))
        if state.queue.count > 1 {
            entries.append(.nextAction(theme, l10n.string(.musicNext, languageCode: lang)))
        }
    } else {
        entries.append(.nowPlayingTrack(theme, l10n.string(.musicNothingPlaying, languageCode: lang), ""))
    }

    // 2. Music Sources
    entries.append(.sourcesHeader(theme, l10n.string(.musicSourcesTitle, languageCode: lang).uppercased()))
    let queueLabel = state.queue.isEmpty
        ? ""
        : l10n.plural(.tracksCount, count: state.queue.count, languageCode: lang)
    entries.append(.sourceBGMix(theme, l10n.string(.musicSourceBGMix, languageCode: lang), queueLabel))

    let yandexConfigured = BGYandexCredentials.fromBundle().isConfigured
    let yandexLabel = yandexConfigured ? "" : l10n.string(.commonOff, languageCode: lang)
    entries.append(.sourceYandex(theme, l10n.string(.musicSourceYandex, languageCode: lang), yandexLabel))
    entries.append(.sourceBGWave(theme, l10n.string(.musicSourceBGWave, languageCode: lang), l10n.string(.commonExperimental, languageCode: lang)))

    // 3. Recent Tracks / Library
    entries.append(.recentHeader(theme, l10n.string(.musicRecentTracks, languageCode: lang).uppercased()))
    if state.recentTracks.isEmpty {
        entries.append(.emptyLibrary(theme, l10n.string(.musicEmptyLibrary, languageCode: lang)))
    } else {
        for (index, track) in state.recentTracks.prefix(10).enumerated() {
            let durationText = track.duration.map { l10n.formatDuration($0) } ?? ""
            entries.append(.recentTrack(index, theme, track.id, track.title, durationText))
        }
    }

    // 4. Playback Settings
    entries.append(.settingsHeader(theme, l10n.string(.musicPlaybackSettings, languageCode: lang).uppercased()))
    entries.append(.playbackSettings(theme, l10n.string(.bgMixSettingsTitle, languageCode: lang)))

    return entries
}

private extension BeyGramStringKey {
    static func commonConnectedOrEnabledFallback(isActive: Bool) -> BeyGramStringKey {
        return isActive ? .commonOn : .commonOff
    }
}

/// BeyGram Music Center: home, sources, recent tracks, mini-player controls, and playback settings.
public func beyGramMusicSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = BeyGramMusicCenterArguments(
        togglePlayPause: {
            BeyGramMusicSession.shared.togglePlayPause()
        },
        nextTrack: {
            BeyGramMusicSession.shared.next()
        },
        openMix: {
            pushControllerImpl?(beyGramMixController(context: context))
        },
        openWave: {
            pushControllerImpl?(beyGramWaveController(context: context))
        },
        openYandex: {
            pushControllerImpl?(beyGramYandexMusicController(context: context))
        },
        openMixSettings: {
            pushControllerImpl?(beyGramMixSettingsController(context: context))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, BeyGramMusicSession.shared.stateSignal)
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(BeyGramL10n.shared.string(.musicTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: musicCenterEntries(presentationData: presentationData, state: state),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] next in
        controller?.push(next)
    }
    return controller
}
