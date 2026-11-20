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

private final class BeyGramYandexServiceStore {
    static let shared = BeyGramYandexServiceStore()

    let service: BGYandexService

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.service = BGYandexService(
            credentials: BGYandexCredentials.fromBundle(),
            cacheDirectory: base.appendingPathComponent("beygram/yandex", isDirectory: true)
        )
    }
}

private enum BeyGramYandexSectionKind {
    case search
    case likes
    case playlists
    case myWave
}

private final class BeyGramYandexArguments {
    let accept: () -> Void
    let revoke: () -> Void
    let signIn: () -> Void
    let cancelSignIn: () -> Void
    let copyCode: (String) -> Void
    let openVerification: () -> Void
    let signOut: () -> Void
    let openSection: (BeyGramYandexSectionKind) -> Void

    init(
        accept: @escaping () -> Void,
        revoke: @escaping () -> Void,
        signIn: @escaping () -> Void,
        cancelSignIn: @escaping () -> Void,
        copyCode: @escaping (String) -> Void,
        openVerification: @escaping () -> Void,
        signOut: @escaping () -> Void,
        openSection: @escaping (BeyGramYandexSectionKind) -> Void
    ) {
        self.accept = accept
        self.revoke = revoke
        self.signIn = signIn
        self.cancelSignIn = cancelSignIn
        self.copyCode = copyCode
        self.openVerification = openVerification
        self.signOut = signOut
        self.openSection = openSection
    }
}

private enum BeyGramYandexSection: Int32 {
    case warning
    case account
    case features
    case footer
}

private struct BeyGramYandexState: Equatable {
    var accepted: Bool
    var configured: Bool
    var signedIn: Bool
    var displayName: String?
    var hasPlus: Bool = false
    var waitingCode: String?
    var verificationUrl: String?
    var codeCopied: Bool = false
    var failure: String?
}

private enum BeyGramYandexEntry: ItemListNodeEntry {
    case warningHeader(PresentationTheme, String)
    case warningBody(PresentationTheme, String)
    case accept(PresentationTheme, String)

    case notConfiguredTitle(PresentationTheme, String)
    case notConfiguredBody(PresentationTheme, String)

    case signIn(PresentationTheme, String)
    case waitingHeader(PresentationTheme, String)
    case codeRow(PresentationTheme, String, String, String)
    case copyCode(PresentationTheme, String, String)
    case openVerification(PresentationTheme, String)
    case cancelSignIn(PresentationTheme, String)

    case profileRow(PresentationTheme, String, String)
    case featuresHeader(PresentationTheme, String)
    case featureRow(Int32, PresentationTheme, BeyGramYandexSectionKind, String)
    case signOut(PresentationTheme, String)

    case failure(PresentationTheme, String)
    case revoke(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .warningHeader, .warningBody, .accept, .notConfiguredTitle, .notConfiguredBody:
            return BeyGramYandexSection.warning.rawValue
        case .signIn, .waitingHeader, .codeRow, .copyCode, .openVerification, .cancelSignIn, .profileRow, .signOut, .failure:
            return BeyGramYandexSection.account.rawValue
        case .featuresHeader, .featureRow:
            return BeyGramYandexSection.features.rawValue
        case .revoke:
            return BeyGramYandexSection.footer.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .warningHeader: return 0
        case .warningBody: return 1
        case .accept: return 2
        case .notConfiguredTitle: return 3
        case .notConfiguredBody: return 4
        case .signIn: return 10
        case .waitingHeader: return 11
        case .codeRow: return 12
        case .copyCode: return 13
        case .openVerification: return 14
        case .cancelSignIn: return 15
        case .profileRow: return 16
        case .signOut: return 17
        case .failure: return 18
        case .featuresHeader: return 20
        case let .featureRow(idx, _, _, _): return 21 + idx
        case .revoke: return 100
        }
    }

    static func == (lhs: BeyGramYandexEntry, rhs: BeyGramYandexEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.warningHeader(lt, lText), .warningHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.warningBody(lt, lText), .warningBody(rt, rText)):
            return lt === rt && lText == rText
        case let (.accept(lt, lText), .accept(rt, rText)):
            return lt === rt && lText == rText
        case let (.notConfiguredTitle(lt, lText), .notConfiguredTitle(rt, rText)):
            return lt === rt && lText == rText
        case let (.notConfiguredBody(lt, lText), .notConfiguredBody(rt, rText)):
            return lt === rt && lText == rText
        case let (.signIn(lt, lText), .signIn(rt, rText)):
            return lt === rt && lText == rText
        case let (.waitingHeader(lt, lText), .waitingHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.codeRow(lt, lTitle, lCode, lRaw), .codeRow(rt, rTitle, rCode, rRaw)):
            return lt === rt && lTitle == rTitle && lCode == rCode && lRaw == rRaw
        case let (.copyCode(lt, lTitle, lRaw), .copyCode(rt, rTitle, rRaw)):
            return lt === rt && lTitle == rTitle && lRaw == rRaw
        case let (.openVerification(lt, lText), .openVerification(rt, rText)):
            return lt === rt && lText == rText
        case let (.cancelSignIn(lt, lText), .cancelSignIn(rt, rText)):
            return lt === rt && lText == rText
        case let (.profileRow(lt, lTitle, lVal), .profileRow(rt, rTitle, rVal)):
            return lt === rt && lTitle == rTitle && lVal == rVal
        case let (.featuresHeader(lt, lText), .featuresHeader(rt, rText)):
            return lt === rt && lText == rText
        case let (.featureRow(lIdx, lt, lKind, lTitle), .featureRow(rIdx, rt, rKind, rTitle)):
            return lIdx == rIdx && lt === rt && lKind == rKind && lTitle == rTitle
        case let (.signOut(lt, lText), .signOut(rt, rText)):
            return lt === rt && lText == rText
        case let (.failure(lt, lText), .failure(rt, rText)):
            return lt === rt && lText == rText
        case let (.revoke(lt, lText), .revoke(rt, rText)):
            return lt === rt && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: BeyGramYandexEntry, rhs: BeyGramYandexEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramYandexArguments
        switch self {
        case let .warningHeader(_, text),
             let .waitingHeader(_, text),
             let .featuresHeader(_, text),
             let .notConfiguredTitle(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .warningBody(_, text),
             let .notConfiguredBody(_, text),
             let .failure(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .accept(_, title), let .signIn(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                switch self {
                case .accept: arguments.accept()
                case .signIn: arguments.signIn()
                default: break
                }
            })
        case let .codeRow(_, title, code, rawCode):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: code,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.copyCode(rawCode)
                }
            )
        case let .copyCode(_, title, rawCode):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.copyCode(rawCode)
            })
        case let .openVerification(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.openVerification)
        case let .cancelSignIn(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.cancelSignIn)
        case let .profileRow(_, title, value):
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
        case let .featureRow(_, _, kind, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openSection(kind)
                }
            )
        case let .signOut(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.signOut)
        case let .revoke(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.revoke)
        }
    }
}

private func beyGramYandexEntries(presentationData: PresentationData, state: BeyGramYandexState) -> [BeyGramYandexEntry] {
    let lang = presentationData.strings.primaryComponent.languageCode
    let l10n = BeyGramL10n.shared
    let theme = presentationData.theme
    var entries: [BeyGramYandexEntry] = []

    if !state.configured {
        entries.append(.notConfiguredTitle(theme, l10n.string(.yandexNotConfiguredTitle, languageCode: lang).uppercased()))
        entries.append(.notConfiguredBody(theme, l10n.string(.yandexNotConfiguredBody, languageCode: lang)))
        return entries
    }

    if !state.accepted {
        entries.append(.warningHeader(theme, l10n.string(.yandexWarningTitle, languageCode: lang).uppercased()))
        entries.append(.warningBody(theme, l10n.string(.yandexWarningBody, languageCode: lang)))
        entries.append(.accept(theme, l10n.string(.yandexAcceptConsent, languageCode: lang)))
        return entries
    }

    if state.signedIn {
        let accountLabel: String
        if let name = state.displayName, !name.isEmpty {
            accountLabel = state.hasPlus ? "\(name) (Plus)" : name
        } else {
            accountLabel = l10n.string(.yandexSignedInStatus, languageCode: lang)
        }
        entries.append(.profileRow(theme, l10n.string(.yandexProfileTitle, languageCode: lang), accountLabel))
        entries.append(.featuresHeader(theme, l10n.string(.yandexSectionFeatures, languageCode: lang).uppercased()))
        let sections: [(BeyGramYandexSectionKind, BeyGramStringKey)] = [
            (.myWave, .yandexMyWave),
            (.likes, .yandexLikes),
            (.playlists, .yandexPlaylists),
            (.search, .yandexSearch)
        ]
        for (idx, item) in sections.enumerated() {
            entries.append(.featureRow(Int32(idx), theme, item.0, l10n.string(item.1, languageCode: lang)))
        }
        entries.append(.signOut(theme, l10n.string(.yandexSignOut, languageCode: lang)))
    } else if let code = state.waitingCode {
        entries.append(.waitingHeader(theme, l10n.string(.yandexWaitingTitle, languageCode: lang).uppercased()))
        entries.append(.codeRow(theme, l10n.string(.yandexCodeLabel, languageCode: lang), code, code))
        let copyTitle = state.codeCopied
            ? l10n.string(.commonCopied, languageCode: lang)
            : l10n.string(.yandexCopyCode, languageCode: lang)
        entries.append(.copyCode(theme, copyTitle, code))
        entries.append(.openVerification(theme, l10n.string(.yandexOpenVerification, languageCode: lang)))
        entries.append(.cancelSignIn(theme, l10n.string(.yandexCancelSignIn, languageCode: lang)))
    } else {
        let signInTitle = state.failure != nil
            ? l10n.string(.yandexRetrySignIn, languageCode: lang)
            : l10n.string(.yandexSignIn, languageCode: lang)
        entries.append(.signIn(theme, signInTitle))
    }

    if let failure = state.failure {
        entries.append(.failure(theme, failure))
    }

    entries.append(.revoke(theme, l10n.string(.yandexRevokeConsent, languageCode: lang)))
    return entries
}

/// Yandex Music source connection, authorization, and live backend sections.
public func beyGramYandexMusicController(context: AccountContext) -> ViewController {
    let service = BeyGramYandexServiceStore.shared.service
    let consent = BGYandexConsent(defaults: .standard)

    var initialName: String?
    var initialPlus = false
    if case let .signedIn(account) = service.accountState {
        initialName = account.displayName
        initialPlus = account.hasPlus
    }

    let initialState = BeyGramYandexState(
        accepted: consent.isAccepted,
        configured: service.credentials.isConfigured,
        signedIn: service.isSignedIn,
        displayName: initialName,
        hasPlus: initialPlus
    )
    let stateValue = Atomic(value: initialState)
    let refresh = ValuePromise<BeyGramYandexState>(initialState)
    let mutate: ((inout BeyGramYandexState) -> Void) -> Void = { change in
        let next = stateValue.modify { current in
            var copy = current
            change(&copy)
            return copy
        }
        refresh.set(next)
    }

    service.onAccountStateChange = { accountState in
        mutate { state in
            switch accountState {
            case .signedOut:
                state.signedIn = false
                state.displayName = nil
                state.hasPlus = false
            case let .signedIn(account):
                state.signedIn = true
                state.displayName = account.displayName
                state.hasPlus = account.hasPlus
            }
        }
    }

    if service.isSignedIn {
        service.refreshAccount { result in
            if case let .success(account) = result {
                mutate { state in
                    state.signedIn = true
                    state.displayName = account.displayName
                    state.hasPlus = account.hasPlus
                }
            }
        }
    }

    var pushImpl: ((ViewController) -> Void)?

    let arguments = BeyGramYandexArguments(
        accept: {
            consent.accept()
            mutate { $0.accepted = true }
        },
        revoke: {
            service.cancelSignIn()
            service.signOut()
            consent.revoke()
            mutate { state in
                state.accepted = false
                state.signedIn = false
                state.displayName = nil
                state.hasPlus = false
                state.waitingCode = nil
                state.verificationUrl = nil
                state.codeCopied = false
                state.failure = nil
            }
        },
        signIn: {
            mutate { state in
                state.failure = nil
                state.waitingCode = nil
                state.codeCopied = false
            }
            service.startSignIn { event in
                mutate { state in
                    switch event {
                    case let .code(code):
                        state.waitingCode = code.userCode
                        state.verificationUrl = code.verificationUrl
                    case .finished:
                        state.waitingCode = nil
                        state.verificationUrl = nil
                        state.signedIn = true
                    case let .failed(reason):
                        state.waitingCode = nil
                        state.verificationUrl = nil
                        state.failure = "\(reason)"
                    }
                }
            }
        },
        cancelSignIn: {
            service.cancelSignIn()
            mutate { state in
                state.waitingCode = nil
                state.verificationUrl = nil
                state.codeCopied = false
            }
        },
        copyCode: { code in
            UIPasteboard.general.string = code
            mutate { $0.codeCopied = true }
        },
        openVerification: {
            if let url = stateValue.with({ $0.verificationUrl }) {
                context.sharedContext.applicationBindings.openUrl(url)
            }
        },
        signOut: {
            service.signOut()
            mutate { state in
                state.signedIn = false
                state.displayName = nil
                state.hasPlus = false
            }
        },
        openSection: { kind in
            switch kind {
            case .search:
                pushImpl?(beyGramYandexTracksController(context: context, service: service, mode: .search))
            case .likes:
                pushImpl?(beyGramYandexTracksController(context: context, service: service, mode: .likes))
            case .myWave:
                pushImpl?(beyGramYandexTracksController(context: context, service: service, mode: .myWave))
            case .playlists:
                pushImpl?(beyGramYandexPlaylistsController(context: context, service: service))
            }
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(BeyGramL10n.shared.string(.yandexTitle, languageCode: lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: beyGramYandexEntries(presentationData: presentationData, state: state),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] next in
        controller?.push(next)
    }
    return controller
}

// MARK: - Yandex Tracks (Search / Likes / My Wave / Playlist)

private enum BeyGramYandexTracksMode {
    case search
    case likes
    case myWave
    case playlist(title: String, kind: String, ownerUid: String?)
}

private struct YandexTracksState: Equatable {
    var query: String = ""
    var isLoading: Bool = false
    var tracks: [BGYandexTrack] = []
    var errorText: String?
    var busyTrackId: String?
}

private final class YandexTracksArguments {
    let updateQuery: (String) -> Void
    let runSearch: () -> Void
    let loadMore: () -> Void
    let openTrack: (BGYandexTrack) -> Void

    init(
        updateQuery: @escaping (String) -> Void,
        runSearch: @escaping () -> Void,
        loadMore: @escaping () -> Void,
        openTrack: @escaping (BGYandexTrack) -> Void
    ) {
        self.updateQuery = updateQuery
        self.runSearch = runSearch
        self.loadMore = loadMore
        self.openTrack = openTrack
    }
}

private enum YandexTracksEntry: ItemListNodeEntry {
    case searchField(PresentationTheme, String, String)
    case searchButton(PresentationTheme, String, Bool)
    case status(PresentationTheme, String)
    case track(Int, PresentationTheme, BGYandexTrack, String, Bool)
    case loadMore(PresentationTheme, String, Bool)

    var section: ItemListSectionId {
        switch self {
        case .searchField, .searchButton: return 0
        case .status, .track, .loadMore: return 1
        }
    }

    var stableId: Int64 {
        switch self {
        case .searchField: return 0
        case .searchButton: return 1
        case .status: return 2
        case let .track(idx, _, _, _, _): return 100 + Int64(idx)
        case .loadMore: return 100000
        }
    }

    static func == (lhs: YandexTracksEntry, rhs: YandexTracksEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.searchField(lt, lText, lPh), .searchField(rt, rText, rPh)):
            return lt === rt && lText == rText && lPh == rPh
        case let (.searchButton(lt, lTitle, lEn), .searchButton(rt, rTitle, rEn)):
            return lt === rt && lTitle == rTitle && lEn == rEn
        case let (.status(lt, lText), .status(rt, rText)):
            return lt === rt && lText == rText
        case let (.track(lIdx, lt, lTrack, lLabel, lBusy), .track(rIdx, rt, rTrack, rLabel, rBusy)):
            return lIdx == rIdx && lt === rt && lTrack == rTrack && lLabel == rLabel && lBusy == rBusy
        case let (.loadMore(lt, lTitle, lEn), .loadMore(rt, rTitle, rEn)):
            return lt === rt && lTitle == rTitle && lEn == rEn
        default:
            return false
        }
    }

    static func < (lhs: YandexTracksEntry, rhs: YandexTracksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! YandexTracksArguments
        switch self {
        case let .searchField(_, text, placeholder):
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
                textUpdated: arguments.updateQuery,
                action: arguments.runSearch
            )
        case let .searchButton(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.runSearch() }
                }
            )
        case let .status(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .track(_, _, track, label, isBusy):
            let title = track.performer.isEmpty ? track.title : "\(track.title) — \(track.performer)"
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                enabled: track.isAvailable && !isBusy,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    if track.isAvailable && !isBusy {
                        arguments.openTrack(track)
                    }
                }
            )
        case let .loadMore(_, title, enabled):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: enabled ? .generic : .disabled,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if enabled { arguments.loadMore() }
                }
            )
        }
    }
}

private func beyGramYandexTracksController(
    context: AccountContext,
    service: BGYandexService,
    mode: BeyGramYandexTracksMode
) -> ViewController {
    let stateValue = Atomic(value: YandexTracksState())
    let statePromise = ValuePromise<YandexTracksState>(YandexTracksState())
    let mutate: ((inout YandexTracksState) -> Void) -> Void = { change in
        let next = stateValue.modify { cur in
            var copy = cur
            change(&copy)
            return copy
        }
        statePromise.set(next)
    }

    let waveSession: BGYandexWaveSession? = {
        if case .myWave = mode {
            return service.makeWave(seeds: [BGYandexWaveSeed.myWave])
        }
        return nil
    }()

    var presentImpl: ((ViewController, Any?) -> Void)?

    let loadInitial: () -> Void = {
        mutate {
            $0.isLoading = true
            $0.errorText = nil
        }
        switch mode {
        case .search:
            mutate { $0.isLoading = false }
        case .likes:
            service.likedTracks { result in
                mutate { state in
                    state.isLoading = false
                    switch result {
                    case let .success(tracks): state.tracks = tracks
                    case let .failure(err): state.errorText = "\(err)"
                    }
                }
            }
        case .myWave:
            waveSession?.first { result in
                mutate { state in
                    state.isLoading = false
                    switch result {
                    case let .success(tracks): state.tracks = tracks
                    case let .failure(err): state.errorText = "\(err)"
                    }
                }
            }
        case let .playlist(_, kind, ownerUid):
            service.playlistTracks(kind: kind, ownerUid: ownerUid) { result in
                mutate { state in
                    state.isLoading = false
                    switch result {
                    case let .success(tracks): state.tracks = tracks
                    case let .failure(err): state.errorText = "\(err)"
                    }
                }
            }
        }
    }

    let arguments = YandexTracksArguments(
        updateQuery: { text in
            mutate { $0.query = text }
        },
        runSearch: {
            let query = stateValue.with { $0.query }.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            mutate {
                $0.isLoading = true
                $0.errorText = nil
            }
            service.search(text: query, limit: 30) { result in
                mutate { state in
                    state.isLoading = false
                    switch result {
                    case let .success(tracks): state.tracks = tracks
                    case let .failure(err): state.errorText = "\(err)"
                    }
                }
            }
        },
        loadMore: {
            guard let waveSession else { return }
            mutate { $0.isLoading = true }
            waveSession.more { result in
                mutate { state in
                    state.isLoading = false
                    switch result {
                    case let .success(tracks): state.tracks.append(contentsOf: tracks)
                    case let .failure(err): state.errorText = "\(err)"
                    }
                }
            }
        },
        openTrack: { track in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.primaryComponent.languageCode
            let l10n = BeyGramL10n.shared

            let sheet = ActionSheetController(presentationData: presentationData)
            let playItem = ActionSheetButtonItem(title: l10n.string(.musicPlay, languageCode: lang), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                mutate { $0.busyTrackId = track.trackId }
                service.localFile(trackId: track.trackId) { result in
                    mutate { $0.busyTrackId = nil }
                    switch result {
                    case let .success(fileURL):
                        BeyGramMusicSession.shared.addTracks(urls: [fileURL])
                        BeyGramMusicSession.shared.play()
                    case let .failure(err):
                        mutate { $0.errorText = "\(err)" }
                    }
                }
            })
            let lyricsItem = ActionSheetButtonItem(title: l10n.string(.yandexLyrics, languageCode: lang), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                service.lyrics(trackId: track.trackId) { result in
                    let body: String
                    switch result {
                    case let .success(lyrics):
                        if !lyrics.lines.isEmpty {
                            body = lyrics.lines.map(\.text).joined(separator: "\n")
                        } else {
                            body = lyrics.plainText ?? "—"
                        }
                    case let .failure(err):
                        body = "\(err)"
                    }
                    let alert = textAlertController(
                        context: context,
                        title: track.title,
                        text: body,
                        actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    )
                    presentImpl?(alert, nil)
                }
            })
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [playItem, lyricsItem]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentImpl?(sheet, nil)
        }
    )

    loadInitial()

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let theme = presentationData.theme

        let title: String
        switch mode {
        case .search: title = l10n.string(.yandexSearch, languageCode: lang)
        case .likes: title = l10n.string(.yandexLikes, languageCode: lang)
        case .myWave: title = l10n.string(.yandexMyWave, languageCode: lang)
        case let .playlist(name, _, _): title = name
        }

        var entries: [YandexTracksEntry] = []
        if case .search = mode {
            entries.append(.searchField(theme, state.query, l10n.string(.commonSearch, languageCode: lang)))
            entries.append(.searchButton(theme, l10n.string(.commonSearch, languageCode: lang), !state.isLoading && !state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
        if state.isLoading {
            entries.append(.status(theme, l10n.string(.commonLoading, languageCode: lang)))
        } else if let errorText = state.errorText {
            entries.append(.status(theme, errorText))
        }
        for (idx, track) in state.tracks.enumerated() {
            let duration = track.durationMs > 0 ? l10n.formatDuration(TimeInterval(track.durationMs) / 1000.0) : ""
            let label = state.busyTrackId == track.trackId ? l10n.string(.commonLoading, languageCode: lang) : duration
            entries.append(.track(idx, theme, track, label, state.busyTrackId != nil))
        }
        if case .myWave = mode, !state.tracks.isEmpty {
            entries.append(.loadMore(theme, l10n.string(.musicNext, languageCode: lang), !state.isLoading))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
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

// MARK: - Yandex Playlists

private final class YandexPlaylistsArguments {
    let openPlaylist: (BGYandexPlaylist) -> Void
    init(openPlaylist: @escaping (BGYandexPlaylist) -> Void) {
        self.openPlaylist = openPlaylist
    }
}

private enum YandexPlaylistsEntry: ItemListNodeEntry {
    case status(PresentationTheme, String)
    case playlist(Int, PresentationTheme, BGYandexPlaylist, String)

    var section: ItemListSectionId { return 0 }
    var stableId: Int64 {
        switch self {
        case .status: return 0
        case let .playlist(idx, _, _, _): return 10 + Int64(idx)
        }
    }

    static func == (lhs: YandexPlaylistsEntry, rhs: YandexPlaylistsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.status(lt, lText), .status(rt, rText)):
            return lt === rt && lText == rText
        case let (.playlist(lIdx, lt, lPl, lLabel), .playlist(rIdx, rt, rPl, rLabel)):
            return lIdx == rIdx && lt === rt && lPl == rPl && lLabel == rLabel
        default:
            return false
        }
    }

    static func < (lhs: YandexPlaylistsEntry, rhs: YandexPlaylistsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! YandexPlaylistsArguments
        switch self {
        case let .status(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .playlist(_, _, playlist, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: playlist.title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openPlaylist(playlist)
                }
            )
        }
    }
}

private func beyGramYandexPlaylistsController(context: AccountContext, service: BGYandexService) -> ViewController {
    let playlistsPromise = ValuePromise<[BGYandexPlaylist]?>(nil)
    let errorPromise = ValuePromise<String?>(nil)
    var pushImpl: ((ViewController) -> Void)?

    service.playlists { result in
        switch result {
        case let .success(items):
            playlistsPromise.set(items)
        case let .failure(err):
            errorPromise.set("\(err)")
            playlistsPromise.set([])
        }
    }

    let arguments = YandexPlaylistsArguments { playlist in
        pushImpl?(beyGramYandexTracksController(
            context: context,
            service: service,
            mode: .playlist(title: playlist.title, kind: playlist.kind, ownerUid: playlist.ownerUid)
        ))
    }

    let signal = combineLatest(context.sharedContext.presentationData, playlistsPromise.get(), errorPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, playlists, errorText -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramL10n.shared
        let theme = presentationData.theme
        var entries: [YandexPlaylistsEntry] = []
        if let errorText {
            entries.append(.status(theme, errorText))
        } else if let playlists {
            for (idx, pl) in playlists.enumerated() {
                entries.append(.playlist(idx, theme, pl, l10n.plural(.tracksCount, count: pl.trackCount, languageCode: lang)))
            }
        } else {
            entries.append(.status(theme, l10n.string(.commonLoading, languageCode: lang)))
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(l10n.string(.yandexPlaylists, languageCode: lang)),
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
    pushImpl = { [weak controller] next in
        controller?.push(next)
    }
    return controller
}
