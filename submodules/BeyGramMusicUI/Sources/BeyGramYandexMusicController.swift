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

private final class BeyGramYandexArguments {
    let accept: () -> Void
    let revoke: () -> Void
    let signIn: () -> Void
    let cancelSignIn: () -> Void
    let copyCode: (String) -> Void
    let openVerification: () -> Void
    let signOut: () -> Void
    let openFeatureStub: (BeyGramStringKey) -> Void

    init(
        accept: @escaping () -> Void,
        revoke: @escaping () -> Void,
        signIn: @escaping () -> Void,
        cancelSignIn: @escaping () -> Void,
        copyCode: @escaping (String) -> Void,
        openVerification: @escaping () -> Void,
        signOut: @escaping () -> Void,
        openFeatureStub: @escaping (BeyGramStringKey) -> Void
    ) {
        self.accept = accept
        self.revoke = revoke
        self.signIn = signIn
        self.cancelSignIn = cancelSignIn
        self.copyCode = copyCode
        self.openVerification = openVerification
        self.signOut = signOut
        self.openFeatureStub = openFeatureStub
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
    case featureRow(Int32, PresentationTheme, BeyGramStringKey, String)
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
        case let (.featureRow(lIdx, lt, lKey, lTitle), .featureRow(rIdx, rt, rKey, rTitle)):
            return lIdx == rIdx && lt === rt && lKey == rKey && lTitle == rTitle
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
        case let .featureRow(_, _, key, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openFeatureStub(key)
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
        entries.append(.profileRow(theme, l10n.string(.yandexProfileTitle, languageCode: lang), l10n.string(.yandexSignedInStatus, languageCode: lang)))
        entries.append(.featuresHeader(theme, l10n.string(.yandexSectionFeatures, languageCode: lang).uppercased()))
        let featureKeys: [BeyGramStringKey] = [
            .yandexLibrary,
            .yandexSearch,
            .yandexLikes,
            .yandexPlaylists,
            .yandexMyWave,
            .yandexLyrics
        ]
        for (idx, key) in featureKeys.enumerated() {
            entries.append(.featureRow(Int32(idx), theme, key, l10n.string(key, languageCode: lang)))
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

/// Yandex Music source connection, authorization, and feature hub.
public func beyGramYandexMusicController(context: AccountContext) -> ViewController {
    let service = BGYandexService(
        credentials: BGYandexCredentials.fromBundle(),
        cacheDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("beygram/yandex", isDirectory: true)
    )
    let consent = BGYandexConsent(defaults: .standard)
    let initialState = BeyGramYandexState(
        accepted: consent.isAccepted,
        configured: service.credentials.isConfigured,
        signedIn: service.isSignedIn,
        waitingCode: nil,
        verificationUrl: nil,
        failure: nil
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

    var presentImpl: ((ViewController, Any?) -> Void)?

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
            mutate { $0.signedIn = false }
        },
        openFeatureStub: { key in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.primaryComponent.languageCode
            let l10n = BeyGramL10n.shared
            let alert = textAlertController(
                context: context,
                title: l10n.string(key, languageCode: lang),
                text: l10n.string(.yandexFeaturePendingBackend, languageCode: lang),
                actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                ]
            )
            presentImpl?(alert, nil)
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
    presentImpl = { [weak controller] next, arg in
        controller?.present(next, in: .window(.root), with: arg)
    }
    return controller
}
